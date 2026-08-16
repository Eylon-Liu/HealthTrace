import SwiftUI
import CoreData

struct AbnormalDetailView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var lang = "zh"
    @AppStorage("ai_provider") private var providerRaw = "gemini"
    @AppStorage("gemini_api_key") private var geminiKey = ""
    @AppStorage("deepseek_api_key") private var deepseekKey = ""

    @State private var abnormalItems: [LabSnapshot] = []
    @State private var aiExplanation = ""
    @State private var aiGeneratedAt: Date?
    @State private var aiIsStale = false
    @State private var isGeneratingAI = false
    @State private var aiError: String?
    @State private var aiExpanded = false

    private var currentProvider: AIProvider { AIProvider(rawValue: providerRaw) ?? .gemini }
    private var currentAPIKey: String { storedAPIKey(for: currentProvider) }
    private var useEN: Bool { lang == "en" }
    private var cacheKey: String {
        "aiAbnormalExplanation_\(pm.currentProfile?.id?.uuidString ?? "none")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if abnormalItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48)).foregroundColor(.green)
                        Text(T("所有指标均正常！", "All indicators are normal!", lang)).font(.headline)
                        Text(T("最近一次检验的每项数值都在参考范围内",
                               "Every test's most recent value is within range", lang))
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    Text(T("以下为每项指标最近一次检验的数值",
                           "Showing each test's most recent result", lang))
                        .font(.caption).foregroundColor(.secondary)

                    ForEach(abnormalItems) { item in
                        NavigationLink {
                            LabTrendsDetailView(initialLabItem: item.name)
                        } label: {
                            abnormalItemRow(item)
                        }
                        .foregroundColor(.primary)
                    }

                    aiSection
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(T("异常指标", "Abnormal Indicators", lang))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadItems(); loadCachedAI() }
    }

    private func abnormalItemRow(_ item: LabSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(labStatusColor(item.status)).frame(width: 10, height: 10)
                Text(labDisplayName(item.name, language: lang)).font(.headline)
                Spacer()
                Text(labStatusLabel(item.status, language: lang))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(labStatusColor(item.status))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(labStatusColor(item.status).opacity(0.12))
                    .cornerRadius(6)
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
            }

            if labDisplayName(item.name, language: lang) != item.name {
                Text(item.name).font(.caption).foregroundColor(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(item.value)
                    .font(.title2.bold())
                    .foregroundColor(labStatusColor(item.status))
                if !item.unit.isEmpty {
                    Text(item.unit).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if !item.refRange.isEmpty {
                    Text(T("参考：\(item.refRange)", "Ref: \(item.refRange)", lang))
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            if let date = item.reportDate {
                Text(T("来源：", "From: ", lang) + item.reportTitle + " (" + date.isoString + ")")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .healthCard(padding: 14)
    }

    // MARK: - AI Section

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(icon: "sparkles", title: T("AI 解读", "AI Explanation", lang), color: Theme.ai)

            if aiExplanation.isEmpty {
                AIGenerateButton(title: T("AI 解读异常指标", "Explain these abnormals", lang),
                                 subtitle: T("结合病史用通俗语言说明", "Plain language, read against your history", lang),
                                 isLoading: isGeneratingAI, lang: lang) {
                    Task { await generateAI() }
                }
                .disabled(isGeneratingAI || currentAPIKey.isEmpty)
            } else {
                AIResultCard(text: aiExplanation, isExpanded: $aiExpanded,
                             generatedAt: aiGeneratedAt, isStale: aiIsStale,
                             isLoading: isGeneratingAI, lang: lang) {
                    Task { await generateAI() }
                }
            }

            if let err = aiError {
                AIErrorBanner(message: err, isLoading: isGeneratingAI, lang: lang) {
                    Task { await generateAI() }
                }
            }

            if currentAPIKey.isEmpty { APIKeyHint(lang: lang) }
        }
        .healthCard(padding: 14)
    }

    // MARK: - Data

    private func loadItems() {
        guard let p = pm.currentProfile else { abnormalItems = []; return }
        abnormalItems = lastTestedLabValues(for: p, in: ctx)
            .filter { $0.isAbnormal }
            .sorted { labDisplayName($0.name, language: lang) < labDisplayName($1.name, language: lang) }
    }

    private func loadCachedAI() {
        guard pm.currentProfile != nil, let entry = AICache.load(cacheKey) else {
            aiExplanation = ""; aiGeneratedAt = nil; aiIsStale = false
            return
        }
        aiExplanation = entry.text
        aiGeneratedAt = entry.generatedAt
        aiIsStale = AICache.isStale(entry, current: labSignature(abnormalItems))
    }

    private func generateAI() async {
        guard let profile = pm.currentProfile, !abnormalItems.isEmpty else { return }
        isGeneratingAI = true
        aiError = nil

        let condReq = NSFetchRequest<Condition>(entityName: "Condition")
        condReq.predicate = NSPredicate(format: "profile == %@", profile)
        let conditions = (try? ctx.fetch(condReq)) ?? []
        let condText = conditions.filter { $0.status == "active" || $0.status == "monitoring" }
            .compactMap { $0.name }.joined(separator: ", ")

        let itemsList = abnormalItems.map {
            "\($0.name): \($0.value) \($0.unit) (\(labStatusLabel($0.status, language: lang)), ref: \($0.refRange))"
        }.joined(separator: "\n")

        let prompt: String
        if useEN {
            prompt = """
            You are a health advisor. Explain these abnormal lab results in simple language a patient can understand. Be reassuring but honest. Connect findings to the patient's known conditions where relevant. Do not introduce yourself or have any opening pleasantries — start directly with the analysis.

            Patient conditions: \(condText.isEmpty ? "None" : condText)
            Abnormal indicators:
            \(itemsList)

            For each abnormal indicator, explain in plain text (no markdown):
            1. What this test measures (one sentence)
            2. What the abnormal value means for the patient
            3. Whether it could be related to their conditions
            4. What they should do about it (lifestyle changes, follow-up)
            Keep each explanation to 2-3 sentences. Be concise and practical.
            """
        } else {
            prompt = """
            你是一位健康顾问。用通俗的语言解释这些异常检验结果。语气要让人安心但诚实。如果与已知病史相关，请指出关联。不要有开场白或自我介绍，直接开始分析。

            患者病史：\(condText.isEmpty ? "无" : condText)
            异常指标：
            \(itemsList)

            对每个异常指标，用纯文本（不要markdown）解释：
            1. 这项检查测的是什么（一句话）
            2. 异常值对患者意味着什么
            3. 是否与已知病史相关
            4. 患者应该怎么做（生活调整、复查建议）
            每个指标2-3句话即可，简洁实用。
            """
        }

        do {
            let result = try await callGeminiText(prompt: prompt, provider: currentProvider, apiKey: currentAPIKey)
            aiExplanation = result
            aiGeneratedAt = Date()
            aiIsStale = false
            AICache.save(cacheKey, text: result, signature: labSignature(abnormalItems))
        } catch {
            aiError = friendlyAIError(error, useEnglish: useEN)
            let saved = aiError
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if aiError == saved { aiError = nil }
            }
        }
        isGeneratingAI = false
    }
}
