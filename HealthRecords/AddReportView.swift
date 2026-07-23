import SwiftUI
import UniformTypeIdentifiers

struct AddReportView: View {
    @Environment(\.managedObjectContext) var ctx
    @Environment(\.dismiss) var dismiss

    var profile: Profile?
    var report: MedicalReport?

    // Form state
    @State private var title = ""
    @State private var reportDate = Date()
    @State private var hasDate = false
    @State private var reportType = ""
    @State private var bodyPart = ""
    @State private var language = "zh"
    @State private var hospital = ""
    @State private var doctor = ""
    @State private var findings = ""
    @State private var conclusion = ""
    @State private var recommendations = ""
    @State private var notes = ""
    @State private var labRows: [LabRow] = []

    // File
    @State private var selectedFileURL: URL?
    @State private var selectedFileName = ""
    @State private var showSourceDialog = false
    @State private var activeSheet: UploadSheet?

    enum UploadSheet: Identifiable {
        case photo, file
        var id: Int { self == .photo ? 0 : 1 }
    }

    // AI
    @AppStorage("ai_provider") private var providerRaw = "gemini"
    @AppStorage("gemini_api_key") private var geminiKey = ""
    @AppStorage("deepseek_api_key") private var deepseekKey = ""
    @State private var isExtracting = false
    @State private var extractError: String?
    @State private var extractSuccess = false

    private var currentProvider: AIProvider {
        AIProvider(rawValue: providerRaw) ?? .gemini
    }
    private var currentAPIKey: String {
        currentProvider == .gemini ? geminiKey : deepseekKey
    }

    init(profile: Profile? = nil, report: MedicalReport? = nil) {
        self.profile = profile
        self.report = report
    }

    var body: some View {
        NavigationView {
            Form {
                uploadAndExtractSection
                basicSection
                medicalSection
                labValuesSection
            }
            .navigationTitle(report == nil ? "添加报告" : "编辑报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .disabled(title.isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadExisting() }
            .confirmationDialog("上传报告", isPresented: $showSourceDialog, titleVisibility: .visible) {
                Button("从相册选择照片") { activeSheet = .photo }
                Button("从文件选择（PDF / 图片）") { activeSheet = .file }
                Button("取消", role: .cancel) {}
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .photo:
                    PhotoPicker { url in onFilePicked(url) }
                case .file:
                    DocumentPicker(types: [.pdf, .image, .jpeg, .png, UTType(filenameExtension: "heic") ?? .image]) { url in
                        onFilePicked(url)
                    }
                }
            }
        }
    }

    private func onFilePicked(_ url: URL) {
        selectedFileURL = url
        selectedFileName = url.lastPathComponent
        extractError = nil
        extractSuccess = false
    }

    // MARK: - Upload & AI Extract (TOP section)

    private var uploadAndExtractSection: some View {
        Section {
            // Upload button
            Button {
                showSourceDialog = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: selectedFileName.isEmpty ? "doc.badge.plus" : "doc.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedFileName.isEmpty
                             ? (report?.fileName ?? "上传报告文件")
                             : selectedFileName)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(selectedFileName.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Text("支持 PDF、照片")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // AI Extract button
            if !selectedFileName.isEmpty || report?.filePath != nil {
                Button {
                    Task { await runAIExtract() }
                } label: {
                    HStack(spacing: 8) {
                        if isExtracting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isExtracting ? "AI 分析中..." : "AI 智能提取内容")
                                .font(.subheadline.weight(.semibold))
                            Text("使用 \(currentProvider.displayName) 自动填写表格")
                                .font(.caption2)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(
                        LinearGradient(colors: [Color(hex: "#7C3AED"), Color(hex: "#2563EB")],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isExtracting || currentAPIKey.isEmpty)
                .listRowInsets(.init(top: 4, leading: 16, bottom: 4, trailing: 16))

                if currentAPIKey.isEmpty {
                    Label("请先在设置中填写 \(currentProvider.displayName) API Key", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(.orange)
                }

                if let err = extractError {
                    Label(err, systemImage: "xmark.circle.fill")
                        .font(.caption).foregroundColor(.red)
                }
                if extractSuccess {
                    Label("提取成功！请检查下方数据确认无误后保存。", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundColor(.green)
                }
            }
        } header: {
            Text("第一步：上传报告")
        } footer: {
            if selectedFileName.isEmpty && report?.filePath == nil {
                Text("上传 PDF 或报告照片，AI 将自动提取所有信息填入下方表格。")
            }
        }
    }

    // MARK: - Basic info

    private var basicSection: some View {
        Section {
            LabeledTextField("报告标题 *", text: $title, placeholder: "例：2025年度体检报告")
            Toggle("填写检查日期", isOn: $hasDate)
            if hasDate {
                DatePicker("检查日期", selection: $reportDate, displayedComponents: .date)
            }
            Picker("检查类型", selection: $reportType) {
                Text("选择类型").tag("")
                ForEach(["血检","体检","MRI","CT","X光","超声","骨密度","心电图","病理","其他"], id: \.self) { Text($0).tag($0) }
            }
            Picker("检查部位", selection: $bodyPart) {
                Text("选择部位").tag("")
                ForEach(["全身","腰椎","颈椎","胸椎","膝关节","髋关节","肩关节","头颅","胸部","腹部","血液","其他"], id: \.self) { Text($0).tag($0) }
            }
            Picker("报告语言", selection: $language) {
                Text("中文").tag("zh")
                Text("English").tag("en")
                Text("中英文").tag("zh-en")
            }
            LabeledTextField("医院/机构", text: $hospital, placeholder: "医院或体检机构名称")
            LabeledTextField("医生", text: $doctor, placeholder: "医生姓名")
        } header: {
            Text("第二步：确认基本信息")
        }
    }

    // MARK: - Medical content

    private var medicalSection: some View {
        Section("医疗内容") {
            VStack(alignment: .leading, spacing: 4) {
                Text("检查发现 / Findings").font(.caption).foregroundColor(.secondary)
                TextEditor(text: $findings).frame(minHeight: 80)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("结论 / Impression").font(.caption).foregroundColor(.secondary)
                TextEditor(text: $conclusion).frame(minHeight: 60)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("建议 / Recommendations").font(.caption).foregroundColor(.secondary)
                TextEditor(text: $recommendations).frame(minHeight: 60)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("备注").font(.caption).foregroundColor(.secondary)
                TextEditor(text: $notes).frame(minHeight: 50)
            }
        }
    }

    // MARK: - Lab values

    private var labValuesSection: some View {
        Section {
            if !labRows.isEmpty {
                Text("\(labRows.count) 项检验数据").font(.caption).foregroundColor(.secondary)
            }
            ForEach($labRows) { $row in
                VStack(spacing: 6) {
                    HStack {
                        TextField("指标名称", text: $row.name).font(.subheadline)
                        Spacer()
                        Picker("", selection: $row.status) {
                            Text("—").tag("")
                            Text("正常").tag("normal")
                            Text("↑偏高").tag("high")
                            Text("↓偏低").tag("low")
                            Text("⚠️危急").tag("critical")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    HStack(spacing: 8) {
                        TextField("数值", text: $row.value)
                        TextField("单位", text: $row.unit)
                        TextField("参考范围", text: $row.refRange)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }
            .onDelete { labRows.remove(atOffsets: $0) }

            Button { labRows.append(LabRow()) } label: {
                Label("手动添加检验指标", systemImage: "plus")
            }
        } header: {
            Text("检验数值")
        }
    }

    // MARK: - AI extraction

    @MainActor
    private func runAIExtract() async {
        let fileURL: URL?
        if let url = selectedFileURL {
            fileURL = url
        } else if let path = report?.filePath {
            fileURL = PersistenceController.uploadsURL.appendingPathComponent(path)
        } else {
            fileURL = nil
        }

        guard let url = fileURL else {
            extractError = "请先选择文件"
            return
        }

        isExtracting = true
        extractError = nil
        extractSuccess = false

        do {
            let extracted = try await extractReportFromFile(url, provider: currentProvider, apiKey: currentAPIKey)
            applyExtracted(extracted)
            extractSuccess = true
        } catch {
            extractError = error.localizedDescription
        }
        isExtracting = false
    }

    private func applyExtracted(_ e: ExtractedReport) {
        if let v = e.title, !v.isEmpty { title = v }
        if let v = e.report_date, let d = v.isoDate { reportDate = d; hasDate = true }
        if let v = e.hospital, !v.isEmpty { hospital = v }
        if let v = e.doctor, !v.isEmpty { doctor = v }
        if let v = e.report_type, !v.isEmpty { reportType = v }
        if let v = e.body_part, !v.isEmpty { bodyPart = v }
        if let v = e.language, !v.isEmpty { language = v }
        if let v = e.findings, !v.isEmpty { findings = v }
        if let v = e.conclusion, !v.isEmpty { conclusion = v }
        if let v = e.recommendations, !v.isEmpty { recommendations = v }
        if let lvs = e.lab_values, !lvs.isEmpty {
            labRows = lvs.map { LabRow(name: $0.name ?? "", value: $0.value ?? "", unit: $0.unit ?? "", refRange: $0.ref_range ?? "", status: $0.status ?? "") }
        }
    }

    // MARK: - Load existing

    private func loadExisting() {
        guard let r = report else { return }
        title = r.title ?? ""
        if let d = r.reportDate { reportDate = d; hasDate = true }
        reportType = r.reportType ?? ""
        bodyPart = r.bodyPart ?? ""
        language = r.language ?? "zh"
        hospital = r.hospital ?? ""
        doctor = r.doctor ?? ""
        findings = r.findings ?? ""
        conclusion = r.conclusion ?? ""
        recommendations = r.recommendations ?? ""
        notes = r.notes ?? ""
        let lvs = (r.labValues as? Set<LabValue>)?.sorted { ($0.itemName ?? "") < ($1.itemName ?? "") } ?? []
        labRows = lvs.map { LabRow(name: $0.itemName ?? "", value: $0.value ?? "", unit: $0.unit ?? "", refRange: $0.refRange ?? "", status: $0.status ?? "") }
    }

    // MARK: - Save

    private func save() {
        let r = report ?? MedicalReport(context: ctx)
        if report == nil {
            r.id = UUID()
            r.createdAt = Date()
            r.profile = profile
        }
        r.title = title
        r.reportDate = hasDate ? reportDate : nil
        r.reportType = reportType.isEmpty ? nil : reportType
        r.bodyPart = bodyPart.isEmpty ? nil : bodyPart
        r.language = language
        r.hospital = hospital.isEmpty ? nil : hospital
        r.doctor = doctor.isEmpty ? nil : doctor
        r.findings = findings.isEmpty ? nil : findings
        r.conclusion = conclusion.isEmpty ? nil : conclusion
        r.recommendations = recommendations.isEmpty ? nil : recommendations
        r.notes = notes.isEmpty ? nil : notes

        if let srcURL = selectedFileURL {
            let destName = UUID().uuidString + "_" + srcURL.lastPathComponent
            let destURL = PersistenceController.uploadsURL.appendingPathComponent(destName)
            try? FileManager.default.copyItem(at: srcURL, to: destURL)
            if let old = r.filePath {
                try? FileManager.default.removeItem(at: PersistenceController.uploadsURL.appendingPathComponent(old))
            }
            r.filePath = destName
            r.fileName = srcURL.lastPathComponent
        }

        if let existing = r.labValues as? Set<LabValue> {
            existing.forEach { ctx.delete($0) }
        }
        for row in labRows where !row.name.isEmpty {
            let lv = LabValue(context: ctx)
            lv.id = UUID()
            lv.itemName = row.name
            lv.value = row.value.isEmpty ? nil : row.value
            lv.unit = row.unit.isEmpty ? nil : row.unit
            lv.refRange = row.refRange.isEmpty ? nil : row.refRange
            lv.status = row.status.isEmpty ? nil : row.status
            lv.report = r
        }

        try? ctx.save()
        dismiss()
    }
}

// MARK: - Helpers

struct LabRow: Identifiable {
    var id = UUID()
    var name = ""
    var value = ""
    var unit = ""
    var refRange = ""
    var status = ""
}

struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    init(_ label: String, text: Binding<String>, placeholder: String = "") {
        self.label = label
        self._text = text
        self.placeholder = placeholder
    }

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary).frame(minWidth: 90, alignment: .leading)
            TextField(placeholder, text: $text)
        }
    }
}
