import SwiftUI
import CoreData

/// Lets any screen jump to a tab (e.g. a dashboard stat card opening the reports list)
/// instead of pushing a second copy of a screen that already exists as a tab.
final class TabRouter: ObservableObject {
    @Published var tab: Int = 0

    static let overview = 0
    static let reports = 1
    static let trends = 2
    static let me = 3
}

struct ContentView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) var profiles: FetchedResults<Profile>

    @StateObject private var router = TabRouter()
    @State private var showProfiles = false
    @State private var showAddProfile = false
    @State private var showAddReport = false
    @AppStorage("summaryLanguage") private var lang = "zh"

    var body: some View {
        // Each tab owns its NavigationView. With a single NavigationView wrapping
        // the TabView, the tabs' own .navigationTitle and .toolbar never reached
        // the navigation bar — the reports filter had no way to be tapped.
        // The bar is a sibling, not an overlay or a safe-area inset: TabView does
        // not pass insets down to its pages, so anything drawn over it covered the
        // bottom of every screen with no way to scroll clear.
        VStack(spacing: 0) {
            TabView(selection: $router.tab) {
                navTab { DashboardView() }.tag(TabRouter.overview)
                navTab { ReportsView() }.tag(TabRouter.reports)
                navTab { TrendsView() }.tag(TabRouter.trends)
                navTab(showsProfile: false) { MeView() }.tag(TabRouter.me)
            }
            AppTabBar(selection: $router.tab, lang: lang) { showAddReport = true }
        }
        .environmentObject(router)
        .sheet(isPresented: $showProfiles) {
            ProfilesView(showAddNew: $showAddProfile)
        }
        .sheet(isPresented: $showAddProfile) {
            AddProfileView()
        }
        .sheet(isPresented: $showAddReport) {
            AddReportView(profile: pm.currentProfile)
        }
        .onAppear { restoreProfileSelection() }
        .onChange(of: profiles.count) { _ in
            if pm.currentProfile == nil { restoreProfileSelection() }
        }
    }

    /// A tab root: its own navigation stack, the system tab bar hidden, and the
    /// profile switcher in the leading slot (omitted on Me, which already shows it).
    @ViewBuilder
    private func navTab<Content: View>(showsProfile: Bool = true,
                                       @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .toolbar(.hidden, for: .tabBar)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showsProfile {
                        ToolbarItem(placement: .navigationBarLeading) { profileButton }
                    }
                }
        }
    }

    private var profileButton: some View {
        Button { showProfiles = true } label: {
            HStack(spacing: 6) {
                AvatarView(letter: pm.avatarLetter, color: pm.avatarColor, size: 28)
                Text(pm.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundColor(.primary)
        }
        .accessibilityLabel(T("切换档案", "Switch profile", lang))
    }

    private func restoreProfileSelection() {
        guard pm.currentProfile == nil else { return }
        if let restored = pm.restoreSelection(from: Array(profiles)) {
            pm.select(restored)
        } else if profiles.isEmpty {
            showAddProfile = true
        }
    }
}

// MARK: - Custom tab bar
//
// Replaces a TabView whose center slot was an empty `Label("", systemImage: "")`.
// That placeholder logged "No symbol named ''" on every launch, was reachable by
// VoiceOver as a nameless tab, and needed a hardcoded pixel offset to sit right.

private struct AppTabBar: View {
    /// Height above the home indicator. Tab content reserves exactly this much.
    static let height: CGFloat = 52

    @Binding var selection: Int
    let lang: String
    let onAdd: () -> Void

    private struct Item {
        let tag: Int
        let zh: String
        let en: String
        let icon: String
        let selectedIcon: String
    }

    private let leading: [Item] = [
        Item(tag: TabRouter.overview, zh: "概览", en: "Overview",
             icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill"),
        Item(tag: TabRouter.reports, zh: "报告", en: "Reports",
             icon: "doc.text", selectedIcon: "doc.text.fill"),
    ]

    private let trailing: [Item] = [
        Item(tag: TabRouter.trends, zh: "趋势", en: "Trends",
             icon: "chart.xyaxis.line", selectedIcon: "chart.xyaxis.line"),
        Item(tag: TabRouter.me, zh: "我的", en: "Me",
             icon: "person", selectedIcon: "person.fill"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(leading, id: \.tag) { tabButton($0) }
            addButton
            ForEach(trailing, id: \.tag) { tabButton($0) }
        }
        .frame(height: Self.height)
        .background(alignment: .top) { Divider() }
        .background { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) }
    }

    private func tabButton(_ item: Item) -> some View {
        let isSelected = selection == item.tag
        return Button {
            selection = item.tag
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? item.selectedIcon : item.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Text(T(item.zh, item.en, lang))
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T(item.zh, item.en, lang))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#FF4D4F"), Theme.accent],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 50, height: 32)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: Theme.accent.opacity(0.3), radius: 5, y: 2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("添加报告", "Add report", lang))
    }
}
