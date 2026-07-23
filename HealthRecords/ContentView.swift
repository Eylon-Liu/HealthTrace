import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) var profiles: FetchedResults<Profile>

    @State private var selectedTab = 0
    @State private var showProfiles = false
    @State private var showAddProfile = false
    @State private var showAddReport = false
    @AppStorage("summaryLanguage") private var lang = "zh"

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    DashboardView()
                        .tabItem { Label(L("概览", lang), systemImage: "square.grid.2x2.fill") }
                        .tag(0)
                    ReportsView()
                        .tabItem { Label(L("报告", lang), systemImage: "doc.text.fill") }
                        .tag(1)
                    Color.clear
                        .tabItem { Label("", systemImage: "") }
                        .tag(99)
                    TrendsView()
                        .tabItem { Label(L("趋势", lang), systemImage: "chart.line.uptrend.xyaxis") }
                        .tag(3)
                    MoreView()
                        .tabItem { Label(L("更多", lang), systemImage: "ellipsis.circle.fill") }
                        .tag(4)
                }
                .tint(.blue)

                Button {
                    showAddReport = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [Color(hex: "#FF4D4F"), Color(hex: "#FF2442")],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 38, height: 38)
                            .shadow(color: Color(hex: "#FF2442").opacity(0.3), radius: 4, y: 2)
                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .foregroundColor(.white)
                    }
                }
                .offset(y: -42)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showProfiles = true } label: {
                        HStack(spacing: 6) {
                            AvatarView(letter: pm.avatarLetter, color: pm.avatarColor, size: 28)
                            Text(pm.displayName).font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: selectedTab) { newVal in
            if newVal == 99 {
                selectedTab = 0
                showAddReport = true
            }
        }
        .sheet(isPresented: $showProfiles) {
            ProfilesView(showAddNew: $showAddProfile)
        }
        .sheet(isPresented: $showAddProfile) {
            AddProfileView()
        }
        .sheet(isPresented: $showAddReport) {
            AddReportView(profile: pm.currentProfile)
        }
        .onAppear {
            if pm.currentProfile == nil {
                if let first = profiles.first {
                    pm.select(first)
                } else {
                    showAddProfile = true
                }
            }
        }
        .onChange(of: profiles.count) { _ in
            if pm.currentProfile == nil, let first = profiles.first {
                pm.select(first)
            }
        }
    }
}
