import SwiftUI

// MARK: - Medical disclaimer
//
// Health apps are reviewed against App Store guideline 1.4.1 (physical harm).
// The disclaimer has to be inside the app, acknowledged once before use, and
// re-readable afterwards — a line in the App Store description is not enough.

enum MedicalDisclaimer {
    /// Bump when the wording changes materially; users are asked to acknowledge again.
    static let version = 1

    static func title(_ lang: String) -> String {
        T("重要提示", "Important", lang)
    }

    static func lead(_ lang: String) -> String {
        T("HealthTrace 是个人健康档案的记录与整理工具，不是医疗器械，不提供医疗建议、诊断或治疗方案。",
          "HealthTrace is a personal record-keeping tool. It is not a medical device and does not provide medical advice, diagnosis, or treatment.",
          lang)
    }

    static func points(_ lang: String) -> [(icon: String, text: String)] {
        [
            ("sparkles",
             T("AI 生成的摘要与解读仅供一般参考，可能不完整或有误。",
               "AI-generated summaries and explanations are for general information only, and may be incomplete or wrong.", lang)),
            ("stethoscope",
             T("请就检查结果咨询专业医护人员，并在做出任何健康决定前听取专业意见。",
               "Always consult a qualified healthcare professional about your results, and before making any health decision.", lang)),
            ("clock.badge.exclamationmark",
             T("请勿因本应用中的内容而延误或忽视专业医疗意见。",
               "Never delay or disregard professional medical advice because of something you read in this app.", lang)),
            ("phone.fill",
             T("紧急情况请立即拨打当地急救电话。",
               "In an emergency, call your local emergency number.", lang)),
        ]
    }

    /// One-line note attached to every AI output and to shared summaries.
    static func shortNote(_ lang: String) -> String {
        T("本内容由 AI 生成，仅供参考，不构成医疗建议，请咨询医生。",
          "AI-generated, for reference only. Not medical advice — please consult your doctor.",
          lang)
    }
}

// MARK: - Reusable pieces

/// The full disclaimer body, shared by the first-run gate and the readable copy in Me.
struct DisclaimerBody: View {
    var lang: String = "zh"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(MedicalDisclaimer.lead(lang))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(MedicalDisclaimer.points(lang), id: \.text) { point in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: point.icon)
                            .font(.footnote)
                            .foregroundColor(.orange)
                            .frame(width: 22)
                        Text(point.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Small print under any AI-generated text.
struct AIDisclaimerNote: View {
    var lang: String = "zh"

    var body: some View {
        Text(MedicalDisclaimer.shortNote(lang))
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - First-run gate

/// Shown until the current disclaimer version is acknowledged. Existing users
/// who already finished onboarding see this once after updating.
struct DisclaimerGateView: View {
    @AppStorage("summaryLanguage") private var lang = "zh"
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 52))
                            .foregroundColor(.orange)
                        Text(MedicalDisclaimer.title(lang))
                            .font(.title2.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)

                    DisclaimerBody(lang: lang)
                }
                .padding(24)
            }

            VStack(spacing: 10) {
                Divider()
                Button(action: onAccept) {
                    Text(T("我已阅读并理解", "I have read and understand", lang))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Text(T("继续使用即表示你理解本应用不能替代专业医疗意见。",
                       "By continuing you understand this app is not a substitute for professional medical advice.", lang))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Readable copy inside the app

struct MedicalDisclaimerScreen: View {
    @AppStorage("summaryLanguage") private var lang = "zh"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DisclaimerBody(lang: lang)

                Divider()

                Text(T("隐私：你的记录仅保存在本机。只有在你填写自己的 API Key 并主动点击 AI 功能时，报告内容才会发送给你选择的 AI 服务商（Google Gemini 或 DeepSeek）。开发者不收集任何数据。",
                       "Privacy: your records stay on this device. Report contents are sent to the AI provider you choose (Google Gemini or DeepSeek) only when you have entered your own API key and tap an AI action. The developer collects nothing.",
                       lang))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(T("免责声明", "Disclaimer", lang))
        .navigationBarTitleDisplayMode(.inline)
    }
}
