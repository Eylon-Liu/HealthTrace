import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// Import several photos or files at once. The model reads them together, so it
/// can tell pages of one report apart from separate exams, and the user approves
/// the result before anything is written.
struct BatchImportView: View {
    @Environment(\.managedObjectContext) var ctx
    @Environment(\.dismiss) var dismiss
    @AppStorage("summaryLanguage") private var lang = "zh"
    @AppStorage("ai_provider") private var providerRaw = "gemini"
    @AppStorage("gemini_api_key") private var geminiKey = ""
    @AppStorage("deepseek_api_key") private var deepseekKey = ""

    var profile: Profile?

    @State private var files: [URL] = []
    @State private var mode: ImportMode = .separateReports
    @State private var drafts: [ReportDraft] = []
    @State private var isExtracting = false
    @State private var errorMessage: String?
    @State private var activeSheet: PickerSheet?
    @State private var showManualEntry = false
    @State private var savedNote: String?

    private enum PickerSheet: Identifiable {
        case photos, documents
        var id: Int { self == .photos ? 0 : 1 }
    }

    private var provider: AIProvider { AIProvider(rawValue: providerRaw) ?? .gemini }
    private var apiKey: String { storedAPIKey(for: provider) }
    private var selectedDrafts: [ReportDraft] { drafts.filter { $0.include } }

    var body: some View {
        NavigationView {
            Group {
                if drafts.isEmpty {
                    pickPhase
                } else {
                    reviewPhase
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(drafts.isEmpty
                             ? T("添加报告", "Add Reports", lang)
                             : T("确认识别结果", "Review", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(T("取消", "Cancel", lang)) { dismiss() }
                }
                if !drafts.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(T("重新识别", "Redo", lang)) { drafts = [] }
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .photos:
                    MultiPhotoPicker { urls in addFiles(urls) }
                case .documents:
                    MultiDocumentPicker(types: [.pdf, .image, .jpeg, .png,
                                                UTType(filenameExtension: "heic") ?? .image]) { urls in
                        addFiles(urls)
                    }
                }
            }
            .sheet(isPresented: $showManualEntry) {
                AddReportView(profile: profile)
            }
        }
    }

    // MARK: - Phase 1: pick files

    private var pickPhase: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    pickButton(icon: "photo.on.rectangle.angled",
                               title: T("选择照片", "Choose Photos", lang),
                               subtitle: T("可多选，按顺序即为页序", "Multi-select; order is page order", lang),
                               color: .green) { activeSheet = .photos }

                    pickButton(icon: "doc.badge.plus",
                               title: T("选择文件", "Choose Files", lang),
                               subtitle: T("PDF 或图片，可多选", "PDFs or images, multi-select", lang),
                               color: .blue) { activeSheet = .documents }
                }
                .healthCard(padding: 14)

                if !files.isEmpty {
                    fileListCard
                    if providerCannotReadSelection { providerWarningCard }
                    modeCard
                    extractButton
                }

                if let errorMessage {
                    AIErrorBanner(message: errorMessage, isLoading: isExtracting, lang: lang) {
                        Task { await runExtraction() }
                    }
                    .padding(.horizontal, 2)
                }

                Button { showManualEntry = true } label: {
                    Text(T("不用 AI，手动填写一份报告", "Skip AI — enter a report manually", lang))
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
    }

    private func pickButton(icon: String, title: String, subtitle: String,
                            color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var fileListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(icon: "doc.on.doc.fill",
                       title: T("已选 \(files.count) 个文件", "\(files.count) files selected", lang),
                       color: .indigo) {
                Button(T("清空", "Clear", lang)) { files = [] }
                    .font(.caption)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            ForEach(Array(files.enumerated()), id: \.offset) { index, url in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Image(systemName: url.pathExtension.lowercased() == "pdf"
                          ? "doc.richtext" : "photo")
                        .font(.caption).foregroundColor(.secondary)
                    Text(url.lastPathComponent)
                        .font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button {
                        files.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                Divider().padding(.leading, 14)
            }
        }
        .healthCard()
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(icon: "square.stack.3d.up.fill",
                       title: T("这些文件是…", "These files are…", lang), color: .orange)

            Picker("", selection: $mode) {
                Text(T("多份报告", "Separate reports", lang)).tag(ImportMode.separateReports)
                Text(T("同一份报告", "One report", lang)).tag(ImportMode.singleReport)
            }
            .pickerStyle(.segmented)

            Text(mode == .separateReports
                 ? T("AI 会判断哪些页属于同一次检查，并为每次检查单独建立一条记录。",
                     "The AI works out which pages belong to the same exam and creates one entry per exam.", lang)
                 : T("所有文件会合并成一条记录，适合一份多页的报告。",
                     "Everything is merged into a single entry — right for one report spread over several pages.", lang))
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .healthCard(padding: 14)
    }

    /// DeepSeek is text-only. Saying so here beats letting the user spend a
    /// request and get "DeepSeek can't read images" back.
    private var providerCannotReadSelection: Bool {
        !provider.supportsVision && files.contains { $0.pathExtension.lowercased() != "pdf" }
    }

    /// A vision provider the user has actually set up, preferring one reachable
    /// from China so we never suggest Gemini to someone who can't reach it.
    private var visionAlternative: AIProvider? {
        AIProvider.allCases
            .filter { $0.supportsVision && !storedAPIKey(for: $0).isEmpty }
            .sorted { $0.availableInChina && !$1.availableInChina }
            .first
    }

    private var providerWarningCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(T("\(provider.displayName) 只能读取文字版 PDF，无法识别照片或扫描件。",
                       "\(provider.displayName) can only read text PDFs — it cannot read photos or scans.", lang))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let alternative = visionAlternative {
                Button {
                    providerRaw = alternative.rawValue
                } label: {
                    Text(T("切换到 \(alternative.displayName)", "Switch to \(alternative.displayName)", lang))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            } else {
                APIKeyHint(lang: lang)
            }
        }
        .healthCard(padding: 14)
    }

    private var extractButton: some View {
        VStack(spacing: 8) {
            Button {
                Task { await runExtraction() }
            } label: {
                HStack(spacing: 8) {
                    if isExtracting {
                        ProgressView().tint(.white)
                        Text(T("正在读取 \(files.count) 个文件…", "Reading \(files.count) files…", lang))
                    } else {
                        Image(systemName: "sparkles")
                        Text(T("AI 识别并生成记录", "Read with AI", lang))
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(
                    LinearGradient(colors: [Color(hex: "#7C3AED"), Color(hex: "#2563EB")],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(isExtracting || apiKey.isEmpty)
            .opacity(apiKey.isEmpty ? 0.5 : 1)

            if apiKey.isEmpty { APIKeyHint(lang: lang) }
        }
    }

    // MARK: - Phase 2: review

    private var reviewPhase: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(drafts.count == 1
                     ? T("识别出 1 份报告，确认后保存。", "Found 1 report. Check it, then save.", lang)
                     : T("识别出 \(drafts.count) 份报告，取消勾选可跳过。",
                         "Found \(drafts.count) reports. Uncheck any you don't want.", lang))
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach($drafts) { $draft in
                    draftCard($draft)
                }

                Button { saveAll() } label: {
                    Text(selectedDrafts.count == 1
                         ? T("保存这份报告", "Save report", lang)
                         : T("保存 \(selectedDrafts.count) 份报告", "Save \(selectedDrafts.count) reports", lang))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(selectedDrafts.isEmpty ? Color.gray.opacity(0.4) : Theme.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(selectedDrafts.isEmpty)

                if let savedNote {
                    Text(savedNote).font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func draftCard(_ draft: Binding<ReportDraft>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    draft.wrappedValue.include.toggle()
                } label: {
                    Image(systemName: draft.wrappedValue.include ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(draft.wrappedValue.include ? .blue : .secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextField(T("报告标题", "Report title", lang), text: Binding(
                        get: { draft.wrappedValue.extracted.title ?? "" },
                        set: { draft.wrappedValue.extracted.title = $0 }
                    ))
                    .font(.subheadline.weight(.semibold))
                    .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        if let type = draft.wrappedValue.extracted.report_type?.nilIfBlank {
                            TypeBadge(type: type)
                        }
                        if let d = draft.wrappedValue.date {
                            Text(d.isoString).font(.caption).foregroundColor(.secondary)
                        }
                        if let h = draft.wrappedValue.extracted.hospital?.nilIfBlank {
                            Text(h).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                metric(T("页", "pages", lang), "\(draft.wrappedValue.sourceURLs.count)")
                metric(T("指标", "labs", lang), "\(draft.wrappedValue.labCount)")
                if draft.wrappedValue.abnormalCount > 0 {
                    metric(T("异常", "abnormal", lang), "\(draft.wrappedValue.abnormalCount)", color: .red)
                }
            }

            if !draft.wrappedValue.conditions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(T("将同时记录以下诊断", "Will also record these diagnoses", lang))
                        .font(.caption.weight(.medium)).foregroundColor(.secondary)
                    ForEach(Array(draft.wrappedValue.conditions.enumerated()), id: \.offset) { _, c in
                        conditionChip(c)
                    }
                }
                .padding(.top, 2)
            }
        }
        .healthCard(padding: 14)
        .opacity(draft.wrappedValue.include ? 1 : 0.5)
    }

    private func metric(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.subheadline.bold()).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    private func conditionChip(_ c: ExtractedCondition) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: c.isChronic ? "infinity.circle.fill" : "clock.circle.fill")
                .font(.caption)
                .foregroundColor(c.isChronic ? .red : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name ?? "").font(.caption.weight(.medium))
                Text(c.isChronic
                     ? T("长期关注，无结束日期", "Ongoing — no end date", lang)
                     : (c.expected_end?.nilIfBlank.map {
                            T("短期，预计 \($0) 结束", "Temporary — expected to clear \($0)", lang)
                        } ?? T("短期", "Temporary", lang)))
                    .font(.caption2).foregroundColor(.secondary)
                if let r = c.restrictions?.nilIfBlank {
                    Text("⚠️ " + r).font(.caption2).foregroundColor(.orange)
                }
            }
            Spacer()
        }
        .padding(8)
        .background((c.isChronic ? Color.red : Color.orange).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Actions

    private func addFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        files.append(contentsOf: urls)
        errorMessage = nil
    }

    private func runExtraction() async {
        guard !files.isEmpty else { return }
        isExtracting = true
        errorMessage = nil

        do {
            let results = try await extractReports(from: files, mode: mode,
                                                   provider: provider, apiKey: apiKey)
            guard !results.isEmpty else {
                errorMessage = T("没有识别出任何报告，请检查文件是否清晰。",
                                 "No reports were recognised — check the files are legible.", lang)
                isExtracting = false
                return
            }
            drafts = results.map { extracted in
                let indices = extracted.source_files ?? Array(1...files.count)
                let urls = indices.compactMap { idx -> URL? in
                    let zeroBased = idx - 1
                    return files.indices.contains(zeroBased) ? files[zeroBased] : nil
                }
                return ReportDraft(extracted: extracted,
                                   sourceURLs: urls.isEmpty ? files : urls)
            }
        } catch {
            errorMessage = friendlyAIError(error, useEnglish: lang == "en")
        }
        isExtracting = false
    }

    private func saveAll() {
        guard let profile else { return }
        var created = 0
        var conditionNames: [String] = []

        for draft in selectedDrafts {
            let result = saveDraft(draft, to: profile, ctx: ctx)
            created += 1
            conditionNames.append(contentsOf: result.created)
        }

        do {
            try ctx.save()
        } catch {
            errorMessage = T("保存失败：\(error.localizedDescription)",
                             "Could not save: \(error.localizedDescription)", lang)
            return
        }

        if conditionNames.isEmpty {
            dismiss()
        } else {
            // Worth naming: a condition appearing on its own is surprising otherwise.
            savedNote = T("已保存 \(created) 份报告，并新增病史：\(conditionNames.joined(separator: "、"))",
                          "Saved \(created) report(s) and added conditions: \(conditionNames.joined(separator: ", "))",
                          lang)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { dismiss() }
        }
    }
}
