import SwiftUI

final class AppState: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var preselectedLabItem: String? = nil

    func navigateToTrends(select item: String? = nil) {
        selectedTab = 3
        preselectedLabItem = item
    }
}
