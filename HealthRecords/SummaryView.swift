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
                    let text = aiSummary.isEmpty ? summaryText : "【AI 健康摘要】\n\(aiSummary)\n\n【基础摘要】\n\(summaryText)"
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
            let text = aiSummary.isEmpty ? summaryText : "【AI 健康摘要】\n\(aiSummary)\n\n【基础摘要】\n\(summaryText)"
            ActivityView(items: [text])
        }
        .onAppear { generate(); loadCachedAISummary() }
        .onChange(of: pm.currentProfile) { _ in generate(); loadCachedAISummary() }
        .onChange(of: includeConditions) { _ in generate() }
        .onChange(of: includeReports) { _ in generate() }
        .onChange(of: includeRestrictions) { _ in generate() }
        .onChange(of: summaryLanguage) { _ in generate() }
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
                if !aiSummary.isEmpty {
                    Button {
                        Task { await generateAISummary() }
                    } label: {
                        if isGeneratingAI {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.caption)
                        }
                    }
                    .disabled(isGeneratingAI)
                }
            }

            if aiSummary.isEmpty {
                Button {
                    Task { await generateAISummary() }
                } label: {
                    HStack {
                        if isGeneratingAI {
                            ProgressView().scaleEffect(0.8)
                            Text(useEnglish ? "Analyzing..." : "AI 分析中...").font(.subheadline)
                        } else {
                            Image(systemName: "sparkles")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(useEnglish ? "Generate AI Health Summary" : "AI 生成健康摘要")
                                    .font(.subheadline.weight(.semibold))
                                Text(useEnglish ? "Analyze all reports and generate comprehensive summary" : "综合分析所有报告，生成全面健康评估")
                                    .font(.caption2)
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
                .disabled(isGeneratingAI || currentAPIKey.isEmpty)

                if currentAPIKey.isEmpty {
                    Text(useEnglish ? "Set up API key in Settings first" : "请先在设置中填写 API Key")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                Text(aiSummary)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(10)
            }

            if let err = aiError {
                Text(err).font(.caption).foregroundColor(.red)
            }
        }
    }

    // MARK: - AI generation

    private func loadCachedAISummary() {
        guard let id = pm.currentProfile?.id?.uuidString else { aiSummary = ""; return }
        aiSummary = UserDefaults.standard.string(forKey: "aiGlobalSummary_\(id)") ?? ""
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
            aiError = error.localizedDescription
        }
        isGeneratingAI = false
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
