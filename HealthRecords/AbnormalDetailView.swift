import SwiftUI
import CoreData

struct AbnormalDetailView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var summaryLanguage = "zh"
    @AppStorage("ai_provider") private var providerRaw = "gemini"
    @AppStorage("gemini_api_key") private var geminiKey = ""
    @AppStorage("deepseek_api_key") private var deepseekKey = ""

    @State private var abnormalItems: [(name: String, value: String, unit: String, status: String, refRange: String, reportDate: Date?, reportTitle: String)] = []
    @State private var aiExplanation = ""
    @State private var isGeneratingAI = false
    @State private var aiError: String?
    @State private var aiExpanded = false

    private var currentProvider: AIProvider { AIProvider(rawValue: providerRaw) ?? .gemini }
    private var currentAPIKey: String { currentProvider == .gemini ? geminiKey : deepseekKey }
    private var useEN: Bool { summaryLanguage == "en" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if abnormalItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48)).foregroundColor(.green)
                        Text(useEN ? "All indicators are normal!" : "所有指标均正常！")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(abnormalItems, id: \.name) { item in
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
            .padding()
        }
        .navigationTitle(useEN ? "Abnormal Indicators" : "异常指标详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadItems(); loadCachedAI() }
    }

    private func abnormalItemRow(_ item: (name: String, value: String, unit: String, status: String, refRange: String, reportDate: Date?, reportTitle: String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(labStatusColor(item.status)).frame(width: 10, height: 10)
                Text(labDisplayName(item.name, language: summaryLanguage))
                    .font(.headline)
                Spacer()
                Text(labStatusLabel(item.status, language: summaryLanguage))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(labStatusColor(item.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(labStatusColor(item.status).opacity(0.12))
                    .cornerRadius(6)
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
            }

            if labDisplayName(item.name, language: summaryLanguage) != item.name {
                Text(item.name).font(.caption).foregroundColor(.secondary)
            }

            HStack {
                Text(item.value)
                    .font(.title2.bold())
                    .foregroundColor(labStatusColor(item.status))
                if !item.unit.isEmpty {
                    Text(item.unit).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if !item.refRange.isEmpty {
                    Text(useEN ? "Ref: \(item.refRange)" : "参考：\(item.refRange)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            if let date = item.reportDate {
                Text("\(useEN ? "From:" : "来源：") \(item.reportTitle) (\(date.formatted(.dateTime.year().month().day())))")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - AI Section

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles").foregroundColor(.purple)
                Text(useEN ? "AI Explanation" : "AI 解读").font(.headline)
                Spacer()
                if !aiExplanation.isEmpty {
                    Button {
                        Task { await generateAI() }
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

            if aiExplanation.isEmpty {
                Button {
                    Task { await generateAI() }
                } label: {
                    HStack {
                        if isGeneratingAI {
                            ProgressView().scaleEffect(0.8)
                            Text(useEN ? "Analyzing..." : "分析中...").font(.subheadline)
                        } else {
                            Image(systemName: "sparkles")
                            Text(useEN ? "Explain these abnormals" : "AI 解读异常指标")
                                .font(.subheadline.weight(.semibold))
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
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if aiExpanded {
                        Text(aiExplanation)
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(aiExplanation)
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .lineLimit(6)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            withAnimation { aiExpanded = true }
                        } label: {
                            Text(useEN ? "Show more" : "展开全部")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.purple)
                        }
                        .padding(.top, 4)
                    }

                    if aiExpanded {
                        Button {
                            withAnimation { aiExpanded = false }
                        } label: {
                            Text(useEN ? "Collapse" : "收起")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(12)
                .background(Color.purple.opacity(0.05))
                .cornerRadius(10)
                .onTapGesture {
                    if !aiExpanded { withAnimation { aiExpanded = true } }
                }
            }

            if let err = aiError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundColor(.orange)
                    Text(err).font(.caption).foregroundColor(.red)
                    Spacer()
                    Button { Task { await generateAI() } } label: {
                        Text(useEN ? "Retry" : "重试").font(.caption.weight(.medium)).foregroundColor(.blue)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.06))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Data

    private func loadItems() {
        guard let p = pm.currentProfile else { return }

        let req = NSFetchRequest<LabValue>(entityName: "LabValue")
        req.predicate = NSPredicate(format: "report.profile == %@", p)
        req.sortDescriptors = [NSSortDescriptor(key: "report.reportDate", ascending: false)]
        let all = (try? ctx.fetch(req)) ?? []

        var seenKeys = Set<String>()
        abnormalItems = all.compactMap { lv in
            guard let name = lv.itemName else { return nil }
            let key = normalizeLabName(name)
            guard !seenKeys.contains(key) else { return nil }
            seenKeys.insert(key)
            let status = lv.status ?? ""
            guard !status.isEmpty && status != "normal" else { return nil }
            return (name: name, value: lv.value ?? "", unit: lv.unit ?? "", status: status,
                    refRange: lv.refRange ?? "", reportDate: lv.report?.reportDate,
                    reportTitle: lv.report?.title ?? "")
        }
        .sorted { labDisplayName($0.name, language: summaryLanguage) < labDisplayName($1.name, language: summaryLanguage) }
    }

    private func loadCachedAI() {
        guard let id = pm.currentProfile?.id?.uuidString else { return }
        aiExplanation = UserDefaults.standard.string(forKey: "aiAbnormalExplanation_\(id)") ?? ""
    }

    private func generateAI() async {
        guard let profile = pm.currentProfile, !abnormalItems.isEmpty else { return }
        isGeneratingAI = true
        aiError = nil

        let condReq = NSFetchRequest<Condition>(entityName: "Condition")
        condReq.predicate = NSPredicate(format: "profile == %@", profile)
        let conditions = (try? ctx.fetch(condReq)) ?? []
        let condText = conditions.filter { $0.status == "active" || $0.status == "monitoring" }
            .map { $0.name ?? "" }.joined(separator: ", ")

        let itemsList = abnormalItems.map {
            "\($0.name): \($0.value) \($0.unit) (\(labStatusLabel($0.status, language: summaryLanguage)), ref: \($0.refRange))"
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
            if let id = profile.id?.uuidString {
                UserDefaults.standard.set(result, forKey: "aiAbnormalExplanation_\(id)")
            }
        } catch {
            let msg = error.localizedDescription
            if msg.contains("high demand") || msg.contains("429") || msg.contains("rate") {
                aiError = useEN ? "AI service is busy. Try again later." : "AI 服务繁忙，请稍后重试。"
            } else {
                aiError = msg
            }
        }
        isGeneratingAI = false
    }
}
