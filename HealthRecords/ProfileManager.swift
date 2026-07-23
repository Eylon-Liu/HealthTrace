import SwiftUI

class ProfileManager: ObservableObject {
    @Published var currentProfile: Profile?

    func select(_ profile: Profile) {
        currentProfile = profile
    }

    var displayName: String { currentProfile?.name ?? "选择档案" }
    var avatarLetter: String { String(currentProfile?.name?.prefix(1) ?? "?") }
    var avatarColor: Color { Color(hex: currentProfile?.avatarColor ?? "#2563EB") }
}
