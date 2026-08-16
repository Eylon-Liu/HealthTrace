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
    @State private var aiGeneratedAt: Date?
    @State private var doctorGeneratedAt: Date?
    @State private var aiStale = false
    @State private var doctorStale = false

    private var currentProvider: AIProvider { AIProvider(rawValue: providerRaw) ?? .gemini }
    private var currentAPIKey: String { storedAPIKey(for: currentProvider) }

    private var useEnglish: Bool { summaryLanguage == "en" }

    private var profileID: String { pm.currentProfile?.id?.uuidString ?? "none" }
    private var healthCacheKey: String { "aiGlobalSummary_\(profileID)" }
    private var doctorCacheKey: String { "aiDoctorSummary_\(profileID)" }
    private var currentSignature: String {
        guard let p = pm.currentProfile else { return "" }
        return recordsSignature(for: p, in: ctx)
    }

    var body: some View {
        VStack(spacing: 0) {
            optionsBar

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aiSummarySection.healthCard(padding: 14)

                    if !summaryText.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            CardHeader(icon: "list.clipboard.fill",
                                       title: T("基础摘要", "Basic Summary", summaryLanguage), color: .gray)
                            Text(summaryText)
                                .font(.system(size: 13))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .healthCard(padding: 14)
                    } else {
                        EmptyStateView(icon: "list.clipboard", message: L("选择档案后生成病历摘要", summaryLanguage))
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
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
                .accessibilityLabel(T("复制", "Copy", summaryLanguage))
                .disabled(shareText.isEmpty)
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
        guard !parts.isEmpty else { return "" }
        // Travels with the text: a summary handed to a doctor or pasted into a
        // message should carry the same caveat the screen shows.
        parts.append("— " + MedicalDisclaimer.shortNote(summaryLanguage))
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
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(icon: "sparkles", title: T("AI 摘要", "AI Summary", summaryLanguage),
                       color: aiMode == 0 ? Theme.ai : .blue)

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
                AIGenerateButton(
                    title: T("AI 生成健康摘要", "Generate AI Health Summary", summaryLanguage),
                    subtitle: T("综合分析所有报告，生成全面健康评估",
                                "Analyzes every report into one overall assessment", summaryLanguage),
                    isLoading: isGeneratingAI, lang: summaryLanguage
                ) {
                    Task { await generateAISummary() }
                }
                .disabled(isGeneratingAI || currentAPIKey.isEmpty)

                if currentAPIKey.isEmpty { APIKeyHint(lang: summaryLanguage) }
            } else {
                AIResultCard(text: aiSummary, isExpanded: $aiExpanded, accent: Theme.ai,
                             generatedAt: aiGeneratedAt, isStale: aiStale,
                             isLoading: isGeneratingAI, lang: summaryLanguage) {
                    Task { await generateAISummary() }
                }
            }

            if let err = aiError {
                AIErrorBanner(message: err, isLoading: isGeneratingAI, lang: summaryLanguage) {
                    Task { await generateAISummary() }
                }
            }
        }
    }

    private var doctorSummaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if doctorSummary.isEmpty {
                AIGenerateButton(
                    title: T("生成医生报告", "Generate Doctor Report", summaryLanguage),
                    subtitle: T("按病症整理的临床摘要，供医生参考",
                                "Clinical summary by condition, for a physician", summaryLanguage),
                    isLoading: isGeneratingDoctor, accent: .blue, lang: summaryLanguage
                ) {
                    Task { await generateDoctorSummaryAction() }
                }
                .disabled(isGeneratingDoctor || currentAPIKey.isEmpty)

                if currentAPIKey.isEmpty { APIKeyHint(lang: summaryLanguage) }
            } else {
                AIResultCard(text: doctorSummary, isExpanded: $doctorExpanded, accent: .blue,
                             generatedAt: doctorGeneratedAt, isStale: doctorStale,
                             isLoading: isGeneratingDoctor, lang: summaryLanguage) {
                    Task { await generateDoctorSummaryAction() }
                }
            }

            if let err = doctorError {
                AIErrorBanner(message: err, isLoading: isGeneratingDoctor, lang: summaryLanguage) {
                    Task { await generateDoctorSummaryAction() }
                }
            }
        }
    }

    // MARK: - AI generation

    private func loadCachedSummaries() {
        guard pm.currentProfile != nil else {
            aiSummary = ""; doctorSummary = ""
            aiGeneratedAt = nil; doctorGeneratedAt = nil
            aiStale = false; doctorStale = false
            return
        }
        let signature = currentSignature

        let health = AICache.load(healthCacheKey)
        aiSummary = health?.text ?? ""
        aiGeneratedAt = health?.generatedAt
        aiStale = AICache.isStale(health, current: signature)

        let doctor = AICache.load(doctorCacheKey)
        doctorSummary = doctor?.text ?? ""
        doctorGeneratedAt = doctor?.generatedAt
        doctorStale = AICache.isStale(doctor, current: signature)
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
            aiGeneratedAt = Date()
            aiStale = false
            AICache.save(healthCacheKey, text: result, signature: currentSignature)
        } catch {
            aiError = friendlyAIError(error, useEnglish: useEnglish)
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
            doctorGeneratedAt = Date()
            doctorStale = false
            AICache.save(doctorCacheKey, text: result, signature: currentSignature)
        } catch {
            doctorError = friendlyAIError(error, useEnglish: useEnglish)
            let saved = doctorError
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if doctorError == saved { doctorError = nil }
            }
        }
        isGeneratingDoctor = false
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
