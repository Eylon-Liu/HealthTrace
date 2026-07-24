import SwiftUI
import CoreData

struct SummaryView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager

    @State private var includeConditions = true
    @State private var includeReports = true
    @State private var includeRestrictions = true
    @AppStorage("summaryLanguage") private var summaryLanguage = "zh"
    @State private var summaryText = ""
    @State private var showShare = false
    @State private var copied = false

    @AppStorage("ai_provider") private var providerRaw = "gemini"
    @AppStorage("gemini_api_key") private var geminiKey = ""
    @AppStorage("deepseek_api_key") private var deepseekKey = ""
    @State private var isGeneratingAI = false
    @State private var aiSummary = ""
    @State private var aiError: String?
    @State private var aiMode = 0 // 0 = health summary, 1 = doctor report
    @State private var doctorSummary = ""
    @State private var isGeneratingDoctor = false
    @State private var doctorError: String?
    @State private var aiExpanded = false
    @State private var doctorExpanded = false

    private var currentProvider: AIProvider { AIProvider(rawValue: providerRaw) ?? .gemini }
    private var currentAPIKey: String { currentProvider == .gemini ? geminiKey : deepseekKey }

    private var useEnglish: Bool { summaryLanguage == "en" }

    var body: some View {
        VStack(spacing: 0) {
            optionsBar

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aiSummarySection

                    if !summaryText.isEmpty {
                        Text(summaryText)
                            .font(.system(size: 14))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        EmptyStateView(icon: "list.clipboard", message: L("选择档案后生成病历摘要", summaryLanguage))
                    }
                }
                .padding()
            }
        }
        .navigationTitle(L("病历摘要", summaryLanguage))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    let text = shareText
                    UIPasteboard.general.string = text
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: [shareText])
        }
        .onAppear { generate(); loadCachedSummaries() }
        .onChange(of: pm.currentProfile) { _ in generate(); loadCachedSummaries() }
        .onChange(of: includeConditions) { _ in generate() }
        .onChange(of: includeReports) { _ in generate() }
        .onChange(of: includeRestrictions) { _ in generate() }
        .onChange(of: summaryLanguage) { _ in generate() }
    }

    private var shareText: String {
        var parts: [String] = []
        if aiMode == 0 && !aiSummary.isEmpty {
            parts.append(useEnglish ? "【AI Health Summary】\n\(aiSummary)" : "【AI 健康摘要】\n\(aiSummary)")
        }
        if aiMode == 1 && !doctorSummary.isEmpty {
            let header: String
            if let p = pm.currentProfile {
                let name = p.name ?? ""
                let date = Date().displayString
                header = useEnglish ? "Patient: \(name) | Generated: \(date)" : "患者：\(name) | 生成日期：\(date)"
            } else { header = "" }
            parts.append(useEnglish ? "【Doctor Report】\n\(header)\n\(doctorSummary)" : "【医生报告】\n\(header)\n\(doctorSummary)")
        }
        if !summaryText.isEmpty {
            parts.append(useEnglish ? "【Basic Summary】\n\(summaryText)" : "【基础摘要】\n\(summaryText)")
        }
        return parts.joined(separator: "\n\n")
    }

    private var optionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ToggleChip(label: useEnglish ? "Conditions" : "病史记录", isOn: $includeConditions)
                ToggleChip(label: useEnglish ? "Reports" : "检查报告", isOn: $includeReports)
                ToggleChip(label: useEnglish ? "Restrictions" : "注意事项", isOn: $includeRestrictions)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - AI Summary Section

    private var aiSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles").foregroundColor(.purple)
                Text(useEnglish ? "AI Health Summary" : "AI 健康摘要").font(.headline)
                Spacer()
            }

            Picker("", selection: $aiMode) {
                Text(useEnglish ? "Health Summary" : "健康摘要").tag(0)
                Text(useEnglish ? "Doctor Report" : "医生报告").tag(1)
            }
            .pickerStyle(.segmented)

            if aiMode == 0 {
                healthSummaryContent
            } else {
                doctorSummaryContent
            }
        }
    }

    private var healthSummaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if aiSummary.isEmpty {
                generateButton(
                    isLoading: isGeneratingAI,
                    title: useEnglish ? "Generate AI Health Summary" : "AI 生成健康摘要",
                    subtitle: useEnglish ? "Analyze all reports and generate comprehensive summary" : "综合分析所有报告，生成全面健康评估"
                ) {
                    Task { await generateAISummary() }
                }
                .disabled(isGeneratingAI || currentAPIKey.isEmpty)

                if currentAPIKey.isEmpty {
                    Text(useEnglish ? "Set up API key in Settings first" : "请先在设置中填写 API Key")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                expandableSummaryCard(
                    text: aiSummary,
                    isExpanded: $aiExpanded,
                    color: .purple,
                    isLoading: isGeneratingAI
                ) {
                    Task { await generateAISummary() }
                }
            }

            errorView(error: aiError, isLoading: isGeneratingAI) {
                Task { await generateAISummary() }
            }
        }
    }

    private var doctorSummaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if doctorSummary.isEmpty {
                generateButton(
                    isLoading: isGeneratingDoctor,
                    title: useEnglish ? "Generate Doctor Report" : "生成医生报告",
                    subtitle: useEnglish ? "Clinical summary organized by condition for physician review" : "按病症整理的临床摘要，供医生参考"
                ) {
                    Task { await generateDoctorSummaryAction() }
                }
                .disabled(isGeneratingDoctor || currentAPIKey.isEmpty)

                if currentAPIKey.isEmpty {
                    Text(useEnglish ? "Set up API key in Settings first" : "请先在设置中填写 API Key")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                expandableSummaryCard(
                    text: doctorSummary,
                    isExpanded: $doctorExpanded,
                    color: .blue,
                    isLoading: isGeneratingDoctor
                ) {
                    Task { await generateDoctorSummaryAction() }
                }
            }

            errorView(error: doctorError, isLoading: isGeneratingDoctor) {
                Task { await generateDoctorSummaryAction() }
            }
        }
    }

    private func generateButton(isLoading: Bool, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                    Text(useEnglish ? "Analyzing..." : "分析中...").font(.subheadline)
                } else {
                    Image(systemName: "sparkles")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Text(subtitle).font(.caption2)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Color.purple.opacity(0.1))
            .foregroundColor(.purple)
            .cornerRadius(10)
        }
    }

    private func expandableSummaryCard(text: String, isExpanded: Binding<Bool>, color: Color, isLoading: Bool, refreshAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(action: refreshAction) {
                    if isLoading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                }
                .disabled(isLoading)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded.wrappedValue ? "minus" : "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(color)
                }
            }
            .padding(.bottom, 4)

            if isExpanded.wrappedValue {
                Text(text)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.wrappedValue = true
                    }
                } label: {
                    Text(useEnglish ? "Show more" : "展开全部")
                        .font(.caption.weight(.medium))
                        .foregroundColor(color)
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(color.opacity(0.05))
        .cornerRadius(10)
        .onTapGesture {
            if !isExpanded.wrappedValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue = true
                }
            }
        }
    }

    @ViewBuilder
    private func errorView(error: String?, isLoading: Bool, retryAction: @escaping () -> Void) -> some View {
        if let err = error {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.orange)
                Text(err).font(.caption).foregroundColor(.red)
                Spacer()
                Button(action: retryAction) {
                    Text(useEnglish ? "Retry" : "重试")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.blue)
                }
                .disabled(isLoading)
            }
            .padding(8)
            .background(Color.red.opacity(0.06))
            .cornerRadius(8)
        }
    }

    // MARK: - AI generation

    private func loadCachedSummaries() {
        guard let id = pm.currentProfile?.id?.uuidString else {
            aiSummary = ""
            doctorSummary = ""
            return
        }
        aiSummary = UserDefaults.standard.string(forKey: "aiGlobalSummary_\(id)") ?? ""
        doctorSummary = UserDefaults.standard.string(forKey: "aiDoctorSummary_\(id)") ?? ""
    }

    private func generateAISummary() async {
        guard let profile = pm.currentProfile else { return }
        isGeneratingAI = true
        aiError = nil

        let reportReq = NSFetchRequest<MedicalReport>(entityName: "MedicalReport")
        reportReq.predicate = NSPredicate(format: "profile == %@", profile)
        reportReq.sortDescriptors = [NSSortDescriptor(key: "reportDate", ascending: false)]
        let reports = (try? ctx.fetch(reportReq)) ?? []

        let condReq = NSFetchRequest<Condition>(entityName: "Condition")
        condReq.predicate = NSPredicate(format: "profile == %@", profile)
        let conditions = (try? ctx.fetch(condReq)) ?? []

        do {
            let result = try await generateGlobalSummary(
                profile: profile, reports: reports, conditions: conditions,
                language: summaryLanguage, provider: currentProvider, apiKey: currentAPIKey)
            aiSummary = result
            if let id = profile.id?.uuidString {
                UserDefaults.standard.set(result, forKey: "aiGlobalSummary_\(id)")
            }
        } catch {
            aiError = friendlyError(error)
            let saved = aiError
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if aiError == saved { aiError = nil }
            }
        }
        isGeneratingAI = false
    }

    private func generateDoctorSummaryAction() async {
        guard let profile = pm.currentProfile else { return }
        isGeneratingDoctor = true
        doctorError = nil

        let reportReq = NSFetchRequest<MedicalReport>(entityName: "MedicalReport")
        reportReq.predicate = NSPredicate(format: "profile == %@", profile)
        reportReq.sortDescriptors = [NSSortDescriptor(key: "reportDate", ascending: false)]
        let reports = (try? ctx.fetch(reportReq)) ?? []

        let condReq = NSFetchRequest<Condition>(entityName: "Condition")
        condReq.predicate = NSPredicate(format: "profile == %@", profile)
        let conditions = (try? ctx.fetch(condReq)) ?? []

        do {
            let result = try await generateDoctorSummary(
                profile: profile, reports: reports, conditions: conditions,
                language: summaryLanguage, provider: currentProvider, apiKey: currentAPIKey)
            doctorSummary = result
            if let id = profile.id?.uuidString {
                UserDefaults.standard.set(result, forKey: "aiDoctorSummary_\(id)")
            }
        } catch {
            doctorError = friendlyError(error)
            let saved = doctorError
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if doctorError == saved { doctorError = nil }
            }
        }
        isGeneratingDoctor = false
    }

    private func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.contains("high demand") || msg.contains("429") || msg.contains("rate") || msg.contains("quota") {
            return useEnglish
                ? "AI service is busy. Previous result preserved. Try again later."
                : "AI 服务繁忙，之前的结果已保留，请稍后重试。"
        }
        if msg.contains("internet") || msg.contains("network") || msg.contains("offline") || msg.contains("timed out") {
            return useEnglish
                ? "Network error. Check your connection and try again."
                : "网络错误，请检查网络连接后重试。"
        }
        return msg
    }

    // MARK: - Basic summary generation

    private func generate() {
        guard let p = pm.currentProfile else { summaryText = ""; return }

        let en = useEnglish
        var lines: [String] = []

        lines.append(p.name ?? "")
        lines.append((en ? "Generated: " : "生成时间：") + Date().displayString)
        lines.append(String(repeating: "─", count: 36))

        lines.append("")
        lines.append(en ? "── Basic Information ──" : "── 基本信息 ──")
        if let bd = p.birthDate {
            lines.append((en ? "Age: " : "年龄：") + ageString(from: bd))
        }
        if let g = p.gender, !g.isEmpty {
            lines.append((en ? "Gender: " : "性别：") + g)
        }
        if let bt = p.bloodType, !bt.isEmpty {
            lines.append((en ? "Blood Type: " : "血型：") + bt)
        }
        if let al = p.allergies, !al.isEmpty {
            lines.append((en ? "Allergies: " : "过敏史：") + al)
        }

        if includeConditions {
            let req = NSFetchRequest<Condition>(entityName: "Condition")
            req.predicate = NSPredicate(format: "profile == %@", p)
            req.sortDescriptors = [NSSortDescriptor(key: "dateOnset", ascending: true)]
            let conds = (try? ctx.fetch(req)) ?? []
            if !conds.isEmpty {
                lines.append("")
                lines.append(en ? "── Medical History ──" : "── 病史记录 ──")
                for c in conds {
                    var line = "• \(c.name ?? "")"
                    line += " [\(statusLabel(c.status))]"
                    if let do_ = c.dateOnset { line += " (\(do_.isoString)" }
                    if let dr = c.dateResolved { line += " → \(dr.isoString)" }
                    if c.dateOnset != nil { line += ")" }
                    if let h = c.hospital, !h.isEmpty { line += " | \(h)" }
                    lines.append(line)
                    if let n = c.notes, !n.isEmpty { lines.append("  \(n)") }
                    if includeRestrictions, let r = c.restrictions, !r.isEmpty {
                        lines.append("  ⚠️ \(en ? "Restrictions:" : "注意事项：") \(r)")
                    }
                }
            }
        }

        if includeReports {
            let req = NSFetchRequest<MedicalReport>(entityName: "MedicalReport")
            req.predicate = NSPredicate(format: "profile == %@", p)
            req.sortDescriptors = [NSSortDescriptor(key: "reportDate", ascending: false)]
            let reports = (try? ctx.fetch(req)) ?? []
            if !reports.isEmpty {
                lines.append("")
                lines.append(en ? "── Examination Reports ──" : "── 检查报告 ──")
                let grouped = Dictionary(grouping: reports) { $0.bodyPart ?? (en ? "Other" : "其他") }
                for (part, reps) in grouped.sorted(by: { $0.key < $1.key }) {
                    lines.append("\n[\(part)]")
                    for r in reps {
                        var line = "  • \(r.title ?? "")"
                        if let d = r.reportDate { line += " (\(d.isoString))" }
                        if let rt = r.reportType { line += " [\(rt)]" }
                        lines.append(line)
                        if let h = r.hospital, !h.isEmpty { lines.append("    \(en ? "Hospital:" : "医院：")\(h)") }
                        if let c = r.conclusion, !c.isEmpty { lines.append("    \(en ? "Conclusion:" : "结论：")\(c)") }

                        let labValues = (r.labValues as? Set<LabValue>) ?? []
                        let abnormal = labValues.filter { $0.status != "normal" && $0.status != nil && !($0.status ?? "").isEmpty }
                        if !abnormal.isEmpty {
                            lines.append("    \(en ? "Abnormal:" : "异常：")")
                            for lv in abnormal.sorted(by: { ($0.itemName ?? "") < ($1.itemName ?? "") }) {
                                lines.append("      ⚠ \(lv.itemName ?? ""): \(lv.value ?? "") \(lv.unit ?? "") (\(labStatusLabel(lv.status)))")
                            }
                        }
                    }
                }
            }
        }

        summaryText = lines.joined(separator: "\n")
    }
}

struct ToggleChip: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.blue : Color(.tertiarySystemFill))
                .foregroundColor(isOn ? .white : .primary)
                .cornerRadius(20)
        }
    }
}
