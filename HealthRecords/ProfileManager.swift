import SwiftUI

class ProfileManager: ObservableObject {
    /// Remembered across launches — a family app that silently reset to the
    /// alphabetically-first member on every cold start showed the wrong records.
    @Published var currentProfile: Profile? { didSet { persistSelection() } }

    private let selectionKey = "selectedProfileID"

    func select(_ profile: Profile) { currentProfile = profile }

    /// Last used profile if it still exists, otherwise the first available one.
    func restoreSelection(from profiles: [Profile]) -> Profile? {
        if let saved = UserDefaults.standard.string(forKey: selectionKey),
           let uuid = UUID(uuidString: saved),
           let match = profiles.first(where: { $0.id == uuid }) {
            return match
        }
        return profiles.first
    }

    private func persistSelection() {
        if let id = currentProfile?.id?.uuidString {
            UserDefaults.standard.set(id, forKey: selectionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectionKey)
        }
    }

    var displayName: String {
        currentProfile?.name ?? (currentLang() == "en" ? "Select profile" : "选择档案")
    }
    var avatarLetter: String { String(currentProfile?.name?.prefix(1) ?? "?") }
    var avatarColor: Color { Color(hex: currentProfile?.avatarColor ?? "#2563EB") }
}
