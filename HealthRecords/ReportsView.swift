import SwiftUI

struct ReportsView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var lang = "zh"

    @FetchRequest(sortDescriptors: [SortDescriptor(\.reportDate, order: .reverse),
                                    SortDescriptor(\.createdAt, order: .reverse)])
    private var allReports: FetchedResults<MedicalReport>

    @State private var showAdd = false
    @State private var filterType = ""
    @State private var filterPart = ""

    private var reports: [MedicalReport] {
        guard let p = pm.currentProfile else { return [] }
        return allReports.filter { r in
            r.profile == p &&
            (filterType.isEmpty || r.reportType == filterType) &&
            (filterPart.isEmpty || r.bodyPart == filterPart)
        }
    }

    private var grouped: [(String, [MedicalReport])] {
        let dict = Dictionary(grouping: reports) { $0.bodyPart ?? "其他" }
        return dict.sorted { bodyPartSortKey($0.key) < bodyPartSortKey($1.key) }
    }

    private var hasFilter: Bool { !filterType.isEmpty || !filterPart.isEmpty }

    var body: some View {
        Group {
            if pm.currentProfile == nil {
                EmptyStateView(icon: "doc.text", message: T("请先选择档案", "Please select a profile", lang))
            } else if reports.isEmpty {
                EmptyStateView(
                    icon: hasFilter ? "line.3.horizontal.decrease.circle" : "doc.text",
                    message: hasFilter
                        ? T("没有符合筛选条件的报告", "No reports match these filters", lang)
                        : T("还没有报告\n点击下方红色按钮添加第一份", "No reports yet\nTap the red button below to add one", lang),
                    actionTitle: hasFilter
                        ? T("清除筛选", "Clear filters", lang)
                        : T("添加报告", "Add report", lang),
                    action: {
                        if hasFilter { filterType = ""; filterPart = "" } else { showAdd = true }
                    })
            } else {
                List {
                    ForEach(grouped, id: \.0) { part, reps in
                        Section(bodyPartLabel(part, lang: lang)) {
                            ForEach(reps, id: \.id) { r in
                                NavigationLink { ReportDetailView(report: r) } label: {
                                    ReportRowView(report: r)
                                }
                            }
                            .onDelete { offsets in deleteReports(reps, at: offsets) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(T("检查报告", "Reports", lang))
        // No "+" here: the red button in the tab bar is the one way to add a report.
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Menu(T("按类型筛选", "Filter by Type", lang)) {
                        Button(T("全部", "All", lang)) { filterType = "" }
                        ForEach(["MRI","CT","X光","血检","超声","骨密度","心电图","病理","其他"], id: \.self) { t in
                            Button(reportTypeLabel(t, lang: lang)) { filterType = t }
                        }
                    }
                    Menu(T("按部位筛选", "Filter by Area", lang)) {
                        Button(T("全部", "All", lang)) { filterPart = "" }
                        ForEach(["腰椎","颈椎","胸椎","膝关节","髋关节","肩关节","头颅","胸部","腹部","血液","其他"], id: \.self) { p in
                            Button(bodyPartLabel(p, lang: lang)) { filterPart = p }
                        }
                    }
                    if hasFilter {
                        Button(T("清除筛选", "Clear Filters", lang), role: .destructive) {
                            filterType = ""; filterPart = ""
                        }
                    }
                } label: {
                    Image(systemName: hasFilter
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(T("筛选", "Filter", lang))
            }
        }
        .sheet(isPresented: $showAdd) {
            AddReportView(profile: pm.currentProfile)
        }
    }

    private func deleteReports(_ reps: [MedicalReport], at offsets: IndexSet) {
        for i in offsets {
            let r = reps[i]
            if let path = r.filePath {
                let url = PersistenceController.uploadsURL.appendingPathComponent(path)
                try? FileManager.default.removeItem(at: url)
            }
            ctx.delete(r)
        }
        try? ctx.save()
    }
}

struct ReportRowView: View {
    let report: MedicalReport
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TypeBadge(type: report.reportType)
                Spacer()
                if report.filePath != nil {
                    Image(systemName: "paperclip").font(.caption2).foregroundColor(.secondary)
                }
            }
            Text(report.title ?? "").font(.subheadline.weight(.semibold))
            HStack(spacing: 4) {
                if let d = report.reportDate {
                    Text(d.displayString).font(.caption).foregroundColor(.secondary)
                }
                if let h = report.hospital, !h.isEmpty {
                    Text("·").font(.caption).foregroundColor(.secondary)
                    Text(h).font(.caption).foregroundColor(.secondary)
                }
            }
            if let c = report.conclusion, !c.isEmpty {
                Text(c)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Report Detail

struct ReportDetailView: View {
    let report: MedicalReport
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @State private var showEdit = false
    @State private var showFile = false
    @State private var isAnalyzing = false
    @State private var aiSummary: String = ""
    @State private var aiError: String?
    @State private var aiExpanded = false
    @State private var showAllLabs = false
    @FetchRequest(sortDescriptors: []) private var allFavorites: FetchedResults<FavoriteLabItem>

    @AppStorage("ai_provider") private var providerRaw = "gemini"
    @AppStorage("gemini_api_key") private var geminiKey = ""
    @AppStorage("deepseek_api_key") private var deepseekKey = ""
    @AppStorage("summaryLanguage") private var summaryLanguage = "zh"

    private var currentProvider: AIProvider { AIProvider(rawValue: providerRaw) ?? .gemini }
    private var currentAPIKey: String { currentProvider == .gemini ? geminiKey : deepseekKey }

    private var labValues: [LabValue] {
        (report.labValues as? Set<LabValue>)?.sorted { ($0.itemName ?? "") < ($1.itemName ?? "") } ?? []
    }

    private var abnormalValues: [LabValue] {
        labValues.filter { $0.status != "normal" && $0.status != nil && !($0.status ?? "").isEmpty }
    }

    private var favorites: Set<String> {
        guard let p = pm.currentProfile else { return [] }
        return Set(allFavorites.filter { $0.profile == p }.compactMap { $0.itemName })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetaItem(label: useEnglish ? "Type" : "类型",
                             value: report.reportType.map { reportTypeLabel($0, lang: summaryLanguage) } ?? "—")
                    MetaItem(label: useEnglish ? "Body Part" : "部位",
                             value: report.bodyPart.map { bodyPartLabel($0, lang: summaryLanguage) } ?? "—")
                    MetaItem(label: useEnglish ? "Date" : "日期", value: report.reportDate?.isoString ?? "—")
                    MetaItem(label: useEnglish ? "Hospital" : "医院", value: report.hospital ?? "—")
                    MetaItem(label: useEnglish ? "Doctor" : "医生", value: report.doctor ?? "—")
                    MetaItem(label: useEnglish ? "Language" : "语言", value: langLabel(report.language))
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                if !abnormalValues.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text(useEnglish ? "Abnormal Indicators" : "异常指标").font(.headline)
                        }
                        ForEach(abnormalValues, id: \.id) { lv in
                            HStack {
                                Circle().fill(labStatusColor(lv.status)).frame(width: 8, height: 8)
                                Text(labDisplayName(lv.itemName ?? "", language: summaryLanguage)).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(lv.value ?? "").font(.subheadline.bold()).foregroundColor(labStatusColor(lv.status))
                                if let u = lv.unit { Text(u).font(.caption).foregroundColor(.secondary) }
                                Text(labStatusLabel(lv.status, language: summaryLanguage)).font(.caption2).foregroundColor(labStatusColor(lv.status))
                            }
                            .padding(10)
                            .background(labStatusColor(lv.status).opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                }

                aiAnalysisSection

                if let f = report.findings, !f.isEmpty {
                    DetailSection(title: useEnglish ? "FINDINGS" : "检查发现", content: f)
                }
                if let c = report.conclusion, !c.isEmpty {
                    DetailSection(title: useEnglish ? "IMPRESSION" : "结论", content: c)
                }
                if let r = report.recommendations, !r.isEmpty {
                    DetailSection(title: useEnglish ? "RECOMMENDATIONS" : "建议", content: r)
                }

                // Collapsed by default: the abnormal values are already called out
                // above, so expanding this by default just repeated them inside a
                // wall of forty normal rows.
                if !labValues.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showAllLabs.toggle() }
                        } label: {
                            HStack {
                                Text(useEnglish ? "Lab Values" : "检验数值").font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(useEnglish ? "\(labValues.count) items" : "\(labValues.count) 项")
                                    .font(.caption).foregroundColor(.secondary)
                                Image(systemName: showAllLabs ? "chevron.up" : "chevron.down")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }

                        if showAllLabs {
                        ForEach(labValues, id: \.id) { lv in
                            HStack {
                                Button {
                                    toggleFavorite(lv.itemName ?? "")
                                } label: {
                                    Image(systemName: favorites.contains(lv.itemName ?? "") ? "star.fill" : "star")
                                        .font(.caption)
                                        .foregroundColor(favorites.contains(lv.itemName ?? "") ? .yellow : .secondary)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(labDisplayName(lv.itemName ?? "", language: summaryLanguage)).font(.subheadline)
                                    if labDisplayName(lv.itemName ?? "", language: summaryLanguage) != (lv.itemName ?? "") {
                                        Text(lv.itemName ?? "").font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Text(lv.value ?? "—")
                                    .font(.subheadline.bold())
                                    .foregroundColor(labStatusColor(lv.status))
                                if let u = lv.unit { Text(u).font(.caption).foregroundColor(.secondary) }
                                if let s = lv.status, !s.isEmpty, s != "normal" {
                                    Text(labStatusLabel(s, language: summaryLanguage)).font(.caption2).foregroundColor(labStatusColor(s))
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        }
                    }
                }

                if let notes = report.notes, !notes.isEmpty {
                    DetailSection(title: useEnglish ? "Notes" : "备注", content: notes)
                }
            }
            .padding()
        }
        .navigationTitle(report.title ?? (useEnglish ? "Report" : "报告详情"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if report.filePath != nil {
                    Button { showFile = true } label: { Image(systemName: "paperclip") }
                }
                Button { showEdit = true } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $showEdit) { AddReportView(report: report) }
        .sheet(isPresented: $showFile) { FilePreviewView(report: report) }
        .onAppear { aiSummary = report.aiSummary ?? "" }
    }

    private var useEnglish: Bool { summaryLanguage == "en" }

    private var aiAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(icon: "sparkles", title: T("AI 分析", "AI Analysis", summaryLanguage), color: Theme.ai)

            if aiSummary.isEmpty {
                AIGenerateButton(title: T("AI 分析本报告", "Analyze this report", summaryLanguage),
                                 subtitle: T("结合病史解读本次结果", "Reads this result against your history", summaryLanguage),
                                 isLoading: isAnalyzing, lang: summaryLanguage) {
                    Task { await runAnalysis() }
                }
                .disabled(isAnalyzing || currentAPIKey.isEmpty)
            } else {
                AIResultCard(text: aiSummary, isExpanded: $aiExpanded,
                             isLoading: isAnalyzing, lang: summaryLanguage) {
                    Task { await runAnalysis() }
                }
            }

            if let err = aiError {
                AIErrorBanner(message: err, isLoading: isAnalyzing, lang: summaryLanguage) {
                    Task { await runAnalysis() }
                }
            }

            if currentAPIKey.isEmpty { APIKeyHint(lang: summaryLanguage) }
        }
    }

    private func runAnalysis() async {
        isAnalyzing = true
        aiError = nil
        do {
            let condNames = (pm.currentProfile?.conditions as? Set<Condition>)?
                .filter { $0.status == "active" || $0.status == "monitoring" }
                .compactMap { $0.name } ?? []
            let result = try await generateReportSummary(
                report: report, language: summaryLanguage, provider: currentProvider, apiKey: currentAPIKey,
                conditions: condNames)
            aiSummary = result
            report.aiSummary = result
            try? ctx.save()
        } catch {
            aiError = friendlyAIError(error, useEnglish: useEnglish)
            let saved = aiError
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if aiError == saved { aiError = nil }
            }
        }
        isAnalyzing = false
    }

    private func toggleFavorite(_ itemName: String) {
        guard let profile = pm.currentProfile, !itemName.isEmpty else { return }
        if let existing = allFavorites.first(where: { $0.profile == profile && $0.itemName == itemName }) {
            ctx.delete(existing)
        } else {
            let fav = FavoriteLabItem(context: ctx)
            fav.id = UUID()
            fav.itemName = itemName
            fav.createdAt = Date()
            fav.profile = profile
        }
        try? ctx.save()
    }

    private func langLabel(_ l: String?) -> String {
        switch l { case "zh": return "中文"; case "en": return "English"; case "zh-en": return "中英"; default: return l ?? "中文" }
    }
}

struct MetaItem: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption.weight(.medium)).lineLimit(2)
        }
    }
}

struct DetailSection: View {
    let title: String
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.secondary).textCase(.uppercase)
            Text(content).font(.subheadline).lineSpacing(4)
        }
    }
}

struct FilePreviewView: View {
    let report: MedicalReport
    @Environment(\.dismiss) var dismiss
    @AppStorage("summaryLanguage") private var lang = "zh"

    var body: some View {
        NavigationView {
            Group {
                if let path = report.filePath {
                    let url = PersistenceController.uploadsURL.appendingPathComponent(path)
                    if FileManager.default.fileExists(atPath: url.path) {
                        QuickLookView(url: url)
                    } else {
                        EmptyStateView(icon: "doc.slash",
                                       message: T("文件未找到", "File not found", lang))
                    }
                } else {
                    EmptyStateView(icon: "doc.slash", message: T("无附件", "No attachment", lang))
                }
            }
            .navigationTitle(report.fileName ?? T("报告文件", "Report file", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(T("关闭", "Close", lang)) { dismiss() }
                }
            }
        }
    }
}

import QuickLook
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
