import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ContentView()
            .onReceive(appState.$selectedTab) { _ in }
            .environment(\.selectedTabBinding, Binding(
                get: { appState.selectedTab },
                set: { appState.selectedTab = $0 }
            ))
    }
}

// Provide an EnvironmentKey to let ContentView bind to selected tab from AppState
private struct SelectedTabBindingKey: EnvironmentKey {
    static let defaultValue: Binding<Int> = .constant(0)
}

extension EnvironmentValues {
    var selectedTabBinding: Binding<Int> { get { self[SelectedTabBindingKey.self] } set { self[SelectedTabBindingKey.self] = newValue } }
}
