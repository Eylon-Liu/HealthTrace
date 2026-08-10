import SwiftUI
import CoreData

struct AllLabItemsView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var lang = "zh"

    @FetchRequest(sortDescriptors: [SortDescriptor(\.itemName)])
    private var allFavorites: FetchedResults<FavoriteLabItem>

    @State private var labItems: [LabSnapshot] = []
    @State private var trendArrows: [String: String] = [:]
    @State private var searchText = ""

    private var favoriteKeys: Set<String> {
        guard let p = pm.currentProfile else { return [] }
        return Set(allFavorites.filter { $0.profile == p }
            .compactMap { $0.itemName }
            .map { normalizeLabName($0) })
    }

    private var filteredItems: [LabSnapshot] {
        guard !searchText.isEmpty else { return labItems }
        let query = searchText.lowercased()
        return labItems.filter {
            $0.name.lowercased().contains(query)
            || labDisplayName($0.name, language: lang).lowercased().contains(query)
        }
    }

    private var grouped: [(title: String, items: [LabSnapshot])] {
        let abnormal = filteredItems.filter { $0.isAbnormal }
        let normal = filteredItems.filter { !$0.isAbnormal }
        var result: [(title: String, items: [LabSnapshot])] = []
        if !abnormal.isEmpty { result.append((L("异常指标", lang), abnormal)) }
        if !normal.isEmpty { result.append((L("正常指标", lang), normal)) }
        return result
    }

    var body: some View {
        Group {
            if labItems.isEmpty {
                EmptyStateView(icon: "chart.xyaxis.line",
                               message: T("暂无检验数据", "No lab data yet", lang))
            } else if filteredItems.isEmpty {
                EmptyStateView(icon: "magnifyingglass",
                               message: T("没有匹配的指标", "No matching tests", lang))
            } else {
                List {
                    ForEach(grouped, id: \.title) { section in
                        Section {
                            ForEach(section.items) { item in
                                NavigationLink {
                                    LabTrendsDetailView(initialLabItem: item.name)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        LabValueRow(item: item, lang: lang,
                                                    trend: trendArrows[item.key] ?? "",
                                                    showChevron: false,
                                                    isFavorite: favoriteKeys.contains(item.key))
                                        if let date = item.reportDate {
                                            Text(T("最近检验：", "Last tested ", lang) + date.isoString)
                                                .font(.caption2).foregroundColor(.secondary)
                                                .padding(.leading, 16)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("\(section.title) · \(section.items.count)")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $searchText, prompt: L("搜索指标", lang))
        .navigationTitle(L("全部检验指标", lang))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadItems() }
        .onChange(of: pm.currentProfile) { _ in loadItems() }
    }

    private func loadItems() {
        guard let p = pm.currentProfile else { labItems = []; trendArrows = [:]; return }
        labItems = lastTestedLabValues(for: p, in: ctx)
            .sorted { labDisplayName($0.name, language: lang) < labDisplayName($1.name, language: lang) }
        trendArrows = labTrendArrows(for: p, in: ctx)
    }
}
