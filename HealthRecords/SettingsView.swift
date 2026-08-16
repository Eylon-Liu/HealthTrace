import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) var ctx
    @AppStorage("ai_provider") private var providerRaw = "gemini"
    @AppStorage("gemini_api_key") private var geminiKey = ""
    @AppStorage("deepseek_api_key") private var deepseekKey = ""
    @AppStorage("gemini_model") private var geminiModel = "gemini-3.5-flash"
    @AppStorage("qwen_api_key") private var qwenKey = ""
    @AppStorage("qwen_model") private var qwenModel = "qwen-vl-max"
    @AppStorage("summaryLanguage") private var summaryLanguage = "zh"
    @State private var showImport = false
    @State private var exportData: Data?
    @State private var showShare = false
    @State private var importStatus: String?
    @State private var statusIsError = false
    @State private var showExportPicker = false
    @State private var exportURL: URL?

    var body: some View {
        Form {
            Section(summaryLanguage == "en" ? "Language" : "语言 / Language") {
                Picker(summaryLanguage == "en" ? "Language" : "界面语言", selection: $summaryLanguage) {
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker(L("AI 智能提取", summaryLanguage), selection: $providerRaw) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { p in
                        Text(p.displayName).tag(p.rawValue)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "diamond.fill").font(.caption2).foregroundColor(.blue)
                        Text("Gemini API Key").font(.subheadline.weight(.semibold))
                    }
                    SecureField("AIza...", text: $geminiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    Picker(T("Gemini 模型", "Gemini model", summaryLanguage), selection: $geminiModel) {
                        Text(T("Gemini 3.5 Flash（推荐）", "Gemini 3.5 Flash (recommended)", summaryLanguage))
                            .tag("gemini-3.5-flash")
                        Text("Gemini 3.5 Flash Lite").tag("gemini-3.5-flash-lite")
                    }
                    .pickerStyle(.menu)

                    Text(T("推荐 gemini-3.5-flash：速度快、推理质量高，免费额度可用。\ngemini-3.5-flash-lite 更省额度。\n支持文本、图像与音视频。\n前往 aistudio.google.com 免费获取。",
                           "gemini-3.5-flash is recommended: fast, good reasoning, and usable on the free tier.\ngemini-3.5-flash-lite uses less quota.\nHandles text, images, audio and video.\nGet a key free at aistudio.google.com.",
                           summaryLanguage))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "cloud.fill").font(.caption2).foregroundColor(.orange)
                        Text(T("通义千问 API Key", "Qwen API Key", summaryLanguage))
                            .font(.subheadline.weight(.semibold))
                    }
                    SecureField("sk-...", text: $qwenKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    Picker(T("通义千问模型", "Qwen model", summaryLanguage), selection: $qwenModel) {
                        Text(T("qwen-vl-max（识别最准）", "qwen-vl-max (most accurate)", summaryLanguage))
                            .tag("qwen-vl-max")
                        Text(T("qwen-vl-plus（更省）", "qwen-vl-plus (cheaper)", summaryLanguage))
                            .tag("qwen-vl-plus")
                    }
                    .pickerStyle(.menu)

                    Text(T("国内可直接访问，无需梯子。能识别照片和扫描件。\n前往 bailian.console.aliyun.com 获取 API Key。",
                           "Reachable from mainland China without a VPN. Reads photos and scans.\nGet a key at bailian.console.aliyun.com.",
                           summaryLanguage))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "brain.fill").font(.caption2).foregroundColor(.green)
                        Text("DeepSeek API Key").font(.subheadline.weight(.semibold))
                    }
                    SecureField("sk-...", text: $deepseekKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    Text(T("模型：deepseek-chat，费用最低。\n只能读取文字版 PDF，无法识别照片或扫描件。\n前往 platform.deepseek.com 获取。",
                           "Uses deepseek-chat, the cheapest option.\nText PDFs only — it cannot read photos or scans.\nGet a key at platform.deepseek.com.",
                           summaryLanguage))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text(L("AI 智能提取", summaryLanguage))
            } footer: {
                Text(L("上传报告时，AI 自动提取标题、日期、医院、检验数值等信息。", summaryLanguage))
            }

            Section {
                Button {
                    showExportPicker = true
                } label: {
                    Label(L("导出备份（JSON）", summaryLanguage), systemImage: "square.and.arrow.up")
                }

                Button {
                    showImport = true
                } label: {
                    Label(L("导入备份", summaryLanguage), systemImage: "square.and.arrow.down")
                }

                if let status = importStatus {
                    HStack {
                        Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(statusIsError ? .red : .green)
                        Text(status).font(.caption)
                            .foregroundColor(statusIsError ? .red : .green)
                    }
                }
            } header: {
                Text(L("数据备份", summaryLanguage))
            } footer: {
                Text(L("换手机时：导出备份 → 将 JSON 文件发到新手机 → 在新手机导入。", summaryLanguage))
            }

            Section(L("关于", summaryLanguage)) {
                // Read from the bundle — a hardcoded "1.0.0" here disagreed with
                // every build after the first one.
                HStack {
                    Text(L("版本", summaryLanguage)); Spacer()
                    Text(appVersionString).foregroundColor(.secondary)
                }
                HStack {
                    Text(L("数据存储", summaryLanguage)); Spacer()
                    Text(L("本地设备", summaryLanguage)).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(L("设置", summaryLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImport) {
            DocumentPicker(types: [.json, .healthRecord]) { url in
                importBackup(from: url)
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ActivityView(items: [url])
            }
        }
        .sheet(isPresented: $showExportPicker, onDismiss: {
            if exportURL != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showShare = true
                }
            }
        }) {
            ExportProfilePicker { selectedData in
                exportURL = nil
                if let data = selectedData, let url = saveToTemp(data: data, name: "FamilyVitals_备份.json") {
                    exportData = data
                    exportURL = url
                }
            }
        }
        .onAppear {
            let allowed = ["gemini-3.5-flash", "gemini-3.5-flash-lite"]
            if !allowed.contains(geminiModel) {
                geminiModel = "gemini-3.5-flash"
            }
        }
    }

    private func saveToTemp(data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }

    private func importBackup(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            if let _ = try? JSONDecoder().decode(ProfileExportData.self, from: data) {
                let profile = try ProfileExporter.importProfile(from: url, context: ctx)
                let name = profile.name ?? ""
                importStatus = T("导入成功！已恢复「\(name)」的档案",
                                 "Imported — restored \(name)'s profile", summaryLanguage)
                statusIsError = false
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let profilesData = json["profiles"] as? [[String: Any]]
            else {
                importStatus = L("文件格式不正确", summaryLanguage)
                statusIsError = true
                return
            }

            for pd in profilesData {
                let p = Profile(context: ctx)
                p.id = UUID()
                p.createdAt = Date()
                p.name = pd["name"] as? String
                p.avatarColor = pd["avatarColor"] as? String ?? "#2563EB"
                p.gender = pd["gender"] as? String
                p.bloodType = pd["bloodType"] as? String
                p.allergies = pd["allergies"] as? String
                p.notes = pd["notes"] as? String
                if let s = pd["birthDate"] as? String { p.birthDate = s.isoDate }

                for rd in (pd["reports"] as? [[String: Any]]) ?? [] {
                    let r = MedicalReport(context: ctx)
                    r.id = UUID(); r.createdAt = Date(); r.profile = p
                    r.title = rd["title"] as? String
                    r.hospital = rd["hospital"] as? String
                    r.doctor = rd["doctor"] as? String
                    r.reportType = rd["reportType"] as? String
                    r.bodyPart = rd["bodyPart"] as? String
                    r.language = rd["language"] as? String ?? "zh"
                    r.findings = rd["findings"] as? String
                    r.conclusion = rd["conclusion"] as? String
                    r.recommendations = rd["recommendations"] as? String
                    r.fileName = rd["fileName"] as? String
                    r.notes = rd["notes"] as? String
                    if let s = rd["reportDate"] as? String { r.reportDate = s.isoDate }
                    for ld in (rd["labValues"] as? [[String: Any]]) ?? [] {
                        let lv = LabValue(context: ctx)
                        lv.id = UUID()
                        lv.itemName = ld["itemName"] as? String
                        lv.value = ld["value"] as? String
                        lv.unit = ld["unit"] as? String
                        lv.refRange = ld["refRange"] as? String
                        lv.status = ld["status"] as? String
                        lv.report = r
                    }
                }

                for cd in (pd["conditions"] as? [[String: Any]]) ?? [] {
                    let c = Condition(context: ctx)
                    c.id = UUID(); c.createdAt = Date(); c.profile = p
                    c.name = cd["name"] as? String
                    c.category = cd["category"] as? String
                    c.status = cd["status"] as? String ?? "active"
                    c.severity = cd["severity"] as? String
                    c.hospital = cd["hospital"] as? String
                    c.doctor = cd["doctor"] as? String
                    c.restrictions = cd["restrictions"] as? String
                    c.notes = cd["notes"] as? String
                    if let s = cd["dateOnset"] as? String { c.dateOnset = s.isoDate }
                    if let s = cd["dateResolved"] as? String { c.dateResolved = s.isoDate }
                }
            }

            try ctx.save()
            importStatus = T("导入成功！共恢复 \(profilesData.count) 个档案",
                             "Imported \(profilesData.count) profile(s)", summaryLanguage)
            statusIsError = false
        } catch {
            importStatus = T("导入失败：\(error.localizedDescription)",
                             "Import failed: \(error.localizedDescription)", summaryLanguage)
            statusIsError = true
        }
    }
}

struct ExportProfilePicker: View {
    @Environment(\.managedObjectContext) var ctx
    @Environment(\.dismiss) var dismiss
    @AppStorage("summaryLanguage") private var lang = "zh"

    @State private var profiles: [Profile] = []
    @State private var selected: Set<NSManagedObjectID> = []
    var onExport: (Data?) -> Void

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        if selected.count == profiles.count {
                            selected.removeAll()
                        } else {
                            selected = Set(profiles.map { $0.objectID })
                        }
                    } label: {
                        HStack {
                            Image(systemName: selected.count == profiles.count ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selected.count == profiles.count ? .blue : .secondary)
                            Text(L("全选", lang))
                        }
                    }
                }

                Section(L("选择要导出的档案", lang)) {
                    ForEach(profiles, id: \.objectID) { profile in
                        Button {
                            if selected.contains(profile.objectID) {
                                selected.remove(profile.objectID)
                            } else {
                                selected.insert(profile.objectID)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(profile.objectID) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selected.contains(profile.objectID) ? .blue : .secondary)

                                let initial = (profile.name ?? "?").prefix(1).uppercased()
                                ZStack {
                                    Circle().fill(Color(hex: profile.avatarColor ?? "#2563EB")).frame(width: 32, height: 32)
                                    Text(initial).font(.caption.bold()).foregroundColor(.white)
                                }

                                VStack(alignment: .leading) {
                                    Text(profile.name ?? L("未命名", lang)).font(.body)
                                    let reportCount = (profile.reports as? Set<MedicalReport>)?.count ?? 0
                                    let condCount = (profile.conditions as? Set<Condition>)?.count ?? 0
                                    Text(lang == "en" ? "\(reportCount) reports · \(condCount) conditions" : "\(reportCount) 份报告 · \(condCount) 条病史")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle(L("导出备份", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消", lang)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("导出", lang)) {
                        let chosen = profiles.filter { selected.contains($0.objectID) }
                        let data = generateExport(profiles: chosen)
                        onExport(data)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .onAppear {
                let req = NSFetchRequest<Profile>(entityName: "Profile")
                req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
                profiles = (try? ctx.fetch(req)) ?? []
                selected = Set(profiles.map { $0.objectID })
            }
        }
    }

    private func generateExport(profiles: [Profile]) -> Data? {
        var export: [[String: Any]] = []
        for p in profiles {
            var pd: [String: Any] = [
                "id": p.id?.uuidString ?? UUID().uuidString,
                "name": p.name ?? "",
                "avatarColor": p.avatarColor ?? "#2563EB"
            ]
            if let bd = p.birthDate { pd["birthDate"] = bd.isoString }
            if let g = p.gender { pd["gender"] = g }
            if let bt = p.bloodType { pd["bloodType"] = bt }
            if let al = p.allergies { pd["allergies"] = al }
            if let n = p.notes { pd["notes"] = n }

            let reports = (p.reports as? Set<MedicalReport>) ?? []
            pd["reports"] = reports.map { r -> [String: Any] in
                var rd: [String: Any] = ["id": r.id?.uuidString ?? UUID().uuidString, "title": r.title ?? ""]
                if let v = r.reportDate { rd["reportDate"] = v.isoString }
                if let v = r.hospital { rd["hospital"] = v }
                if let v = r.doctor { rd["doctor"] = v }
                if let v = r.reportType { rd["reportType"] = v }
                if let v = r.bodyPart { rd["bodyPart"] = v }
                if let v = r.language { rd["language"] = v }
                if let v = r.findings { rd["findings"] = v }
                if let v = r.conclusion { rd["conclusion"] = v }
                if let v = r.recommendations { rd["recommendations"] = v }
                if let v = r.fileName { rd["fileName"] = v }
                if let v = r.notes { rd["notes"] = v }
                if let v = r.aiSummary { rd["aiSummary"] = v }
                let lvs = (r.labValues as? Set<LabValue>) ?? []
                rd["labValues"] = lvs.map { lv -> [String: Any] in
                    var d: [String: Any] = ["itemName": lv.itemName ?? ""]
                    if let v = lv.value { d["value"] = v }
                    if let v = lv.unit { d["unit"] = v }
                    if let v = lv.refRange { d["refRange"] = v }
                    if let v = lv.status { d["status"] = v }
                    return d
                }
                return rd
            }

            let conds = (p.conditions as? Set<Condition>) ?? []
            pd["conditions"] = conds.map { c -> [String: Any] in
                var cd: [String: Any] = ["id": c.id?.uuidString ?? UUID().uuidString, "name": c.name ?? ""]
                if let v = c.category { cd["category"] = v }
                if let v = c.dateOnset { cd["dateOnset"] = v.isoString }
                if let v = c.dateResolved { cd["dateResolved"] = v.isoString }
                if let v = c.hospital { cd["hospital"] = v }
                if let v = c.doctor { cd["doctor"] = v }
                if let v = c.status { cd["status"] = v }
                if let v = c.severity { cd["severity"] = v }
                if let v = c.restrictions { cd["restrictions"] = v }
                if let v = c.notes { cd["notes"] = v }
                return cd
            }

            let favs = (p.favoriteLabItems as? Set<FavoriteLabItem>) ?? []
            pd["favoriteLabItems"] = favs.compactMap { $0.itemName }

            export.append(pd)
        }

        let wrapper: [String: Any] = [
            "version": 1,
            "exportDate": Date().isoString,
            "profiles": export
        ]
        return try? JSONSerialization.data(withJSONObject: wrapper, options: .prettyPrinted)
    }
}
