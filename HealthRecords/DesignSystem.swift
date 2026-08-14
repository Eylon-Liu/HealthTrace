import SwiftUI

// MARK: - Theme

enum Theme {
    static let corner: CGFloat = 14
    /// Primary action color (the center "add" button).
    static let accent = Color(hex: "#FF2442")
    static let ai = Color.purple
}

/// Inline bilingual string. Preferred over `L()` for new strings — no dictionary to keep in sync.
func T(_ zh: String, _ en: String, _ lang: String) -> String { lang == "en" ? en : zh }

// MARK: - Card container

private struct CardModifier: ViewModifier {
    let padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

extension View {
    /// Standard elevated card. Adapts to light/dark automatically.
    func healthCard(padding: CGFloat = 0) -> some View { modifier(CardModifier(padding: padding)) }
}

/// Card title row: colored icon chip + title, optional trailing accessory.
struct CardHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var color: Color = .blue
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundColor(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.headline)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(icon: String, title: String, color: Color = .blue) {
        self.init(icon: icon, title: title, color: color) { EmptyView() }
    }
}

// MARK: - AI components
//
// One implementation of the "generate → show → expand/collapse → regenerate" flow,
// shared by the report analysis, health summary, doctor report and abnormal explainer.

/// Call-to-action shown before any AI text exists.
struct AIGenerateButton: View {
    let title: String
    var subtitle: String? = nil
    let isLoading: Bool
    var accent: Color = Theme.ai
    var lang: String = "zh"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().scaleEffect(0.8).tint(accent)
                    Text(T("分析中…", "Analyzing…", lang)).font(.subheadline)
                } else {
                    Image(systemName: "sparkles")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline.weight(.semibold))
                        if let subtitle {
                            Text(subtitle).font(.caption2).opacity(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(accent.opacity(0.1))
            .foregroundColor(accent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .disabled(isLoading)
    }
}

/// Expandable AI result with regenerate, generation time, and a stale marker
/// for when the underlying records changed after the text was produced.
struct AIResultCard: View {
    let text: String
    @Binding var isExpanded: Bool
    var accent: Color = Theme.ai
    var generatedAt: Date? = nil
    var isStale: Bool = false
    var isLoading: Bool = false
    var lang: String = "zh"
    let onRegenerate: () -> Void

    private let collapsedLines = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isStale {
                    Label(T("内容可能已过期，建议重新生成", "May be out of date — regenerate", lang),
                          systemImage: "clock.arrow.circlepath")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if let generatedAt {
                    Text(T("生成于 ", "Generated ", lang) + generatedAt.relativeString(lang: lang))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 4)
                Button(action: onRegenerate) {
                    if isLoading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.caption.weight(.semibold))
                    }
                }
                .disabled(isLoading)
                .accessibilityLabel(T("重新生成", "Regenerate", lang))
            }

            Text(text)
                .font(.system(size: 13))
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : collapsedLines)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? T("收起", "Collapse", lang) : T("展开全部", "Show more", lang))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption2)
                }
                .font(.caption.weight(.medium))
                .foregroundColor(accent)
            }

            // Lives on the card itself, so no AI output can ship without it.
            Divider().padding(.top, 2)
            AIDisclaimerNote(lang: lang)
        }
        .padding(12)
        .background(accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if !isExpanded { withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true } }
        }
    }
}

/// Inline, dismissible-by-retry error row used by every AI action.
struct AIErrorBanner: View {
    let message: String
    var isLoading: Bool = false
    var lang: String = "zh"
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption).foregroundColor(.orange)
            Text(message).font(.caption).foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onRetry) {
                Text(T("重试", "Retry", lang)).font(.caption.weight(.medium)).foregroundColor(.blue)
            }
            .disabled(isLoading)
        }
        .padding(8)
        .background(Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Shown when no API key is configured — tapping it goes straight to Settings
/// instead of telling the user to go find it themselves.
struct APIKeyHint: View {
    var lang: String = "zh"
    var body: some View {
        NavigationLink { SettingsView() } label: {
            HStack(spacing: 6) {
                Image(systemName: "key.fill").font(.caption2)
                Text(T("前往设置填写 API Key", "Set up an API key in Settings", lang)).font(.caption)
                Image(systemName: "chevron.right").font(.caption2)
            }
            .foregroundColor(.blue)
        }
    }
}

/// Single place that turns an API failure into something a patient can act on.
func friendlyAIError(_ error: Error, useEnglish: Bool) -> String {
    let msg = error.localizedDescription
    let lower = msg.lowercased()
    if lower.contains("high demand") || lower.contains("429") || lower.contains("rate") || lower.contains("quota") {
        return useEnglish
            ? "AI service is busy. Your previous result is kept — try again later."
            : "AI 服务繁忙，之前的结果已保留，请稍后重试。"
    }
    if lower.contains("internet") || lower.contains("network") || lower.contains("offline")
        || lower.contains("timed out") || lower.contains("connection") {
        return useEnglish
            ? "Network error. Check your connection and try again."
            : "网络错误，请检查网络连接后重试。"
    }
    if lower.contains("api key") || lower.contains("401") || lower.contains("403") || lower.contains("unauthorized") {
        return useEnglish
            ? "API key rejected. Check the key in Settings."
            : "API Key 无效，请在设置中检查。"
    }
    return msg
}

// MARK: - AI result cache
//
// Cached text is keyed per profile. We also store when it was generated and a
// signature of the records it was based on, so a stale summary can say so
// instead of silently describing data the user has since changed.

enum AICache {
    struct Entry {
        let text: String
        let generatedAt: Date?
        let signature: String
    }

    static func load(_ key: String) -> Entry? {
        let d = UserDefaults.standard
        guard let text = d.string(forKey: key), !text.isEmpty else { return nil }
        return Entry(text: text,
                     generatedAt: d.object(forKey: "\(key)__at") as? Date,
                     signature: d.string(forKey: "\(key)__sig") ?? "")
    }

    static func save(_ key: String, text: String, signature: String) {
        let d = UserDefaults.standard
        d.set(text, forKey: key)
        d.set(Date(), forKey: "\(key)__at")
        d.set(signature, forKey: "\(key)__sig")
    }

    static func clear(_ key: String) {
        let d = UserDefaults.standard
        d.removeObject(forKey: key)
        d.removeObject(forKey: "\(key)__at")
        d.removeObject(forKey: "\(key)__sig")
    }

    /// Stale when the records moved on — and also for entries cached before
    /// signatures existed, which predate the current prompts and can't be verified.
    static func isStale(_ entry: Entry?, current signature: String) -> Bool {
        guard let entry else { return false }
        return entry.signature != signature
    }
}

extension Date {
    func relativeString(lang: String) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: lang == "en" ? "en_US" : "zh_CN")
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
