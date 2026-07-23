import SwiftUI
import CoreData

struct AllLabItemsView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var summaryLanguage = "zh"

    @FetchRequest(sortDescriptors: [SortDescriptor(\.itemName)])
    private var allFavorites: FetchedResults<FavoriteLabItem>

    @State private var labItems: [(name: String, value: String, unit: String, status: String, date: Date?, reportTitle: String)] = []
    @State private var searchText = ""

    private var favoriteNames: Set<String> {
        guard let p = pm.currentProfile else { return [] }
        return Set(allFavorites.filter { $0.profile == p }.compactMap { $0.itemName })
    }

    private var filteredItems: [(name: String, value: String, unit: String, status: String, date: Date?, reportTitle: String)] {
        if searchText.isEmpty { return labItems }
        let query = searchText.lowercased()
        return labItems.filter {
            $0.name.lowercased().contains(query) ||
            labDisplayName($0.name, language: summaryLanguage).lowercased().contains(query)
        }
    }

    private var grouped: [(String, [(name: String, value: String, unit: String, status: String, date: Date?, reportTitle: String)])] {
        let abnormal = filteredItems.filter { $0.status != "normal" && !$0.status.isEmpty }
        let normal = filteredItems.filter { $0.status == "normal" || $0.status.isEmpty }
        var result: [(String, [(name: String, value: String, unit: String, status: String, date: Date?, reportTitle: String)])] = []
        if !abnormal.isEmpty { result.append((L("异常指标", summaryLanguage), abnormal)) }
        if !normal.isEmpty { result.append((L("正常指标", summaryLanguage), normal)) }
        return result
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.0) { section, items in
                Section(section) {
                    ForEach(items, id: \.name) { item in
                        NavigationLink {
                            LabTrendsDetailView(initialLabItem: item.name)
                        } label: {
                            HStack {
                                if favoriteNames.contains(item.name) {
                                    Image(systemName: "star.fill").font(.caption2).foregroundColor(.yellow)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(labDisplayName(item.name, language: summaryLanguage))
                                        .font(.subheadline.weight(.medium))
                                    if labDisplayName(item.name, language: summaryLanguage) != item.name {
                                        Text(item.name).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Text(item.value).font(.subheadline.bold())
                                    .foregroundColor(labStatusColor(item.status))
                                if !item.unit.isEmpty {
                                    Text(item.unit).font(.caption2).foregroundColor(.secondary)
                                }
                                if !item.status.isEmpty && item.status != "normal" {
                                    Text(labStatusLabel(item.status, language: summaryLanguage)).font(.caption2)
                                        .foregroundColor(labStatusColor(item.status))
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: L("搜索指标", summaryLanguage))
        .navigationTitle(L("全部检验指标", summaryLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadItems() }
    }

    private func loadItems() {
        guard let p = pm.currentProfile else { return }

        let req = NSFetchRequest<LabValue>(entityName: "LabValue")
        req.predicate = NSPredicate(format: "report.profile == %@", p)
        req.sortDescriptors = [NSSortDescriptor(key: "report.reportDate", ascending: false)]
        let all = (try? ctx.fetch(req)) ?? []

        var seenKeys = Set<String>()
        labItems = all.compactMap { lv in
            guard let name = lv.itemName else { return nil }
            let key = normalizeLabName(name)
            guard !seenKeys.contains(key) else { return nil }
            seenKeys.insert(key)
            return (name: name, value: lv.value ?? "", unit: lv.unit ?? "",
                    status: lv.status ?? "", date: lv.report?.reportDate,
                    reportTitle: lv.report?.title ?? "")
        }
        .sorted { labDisplayName($0.name, language: summaryLanguage) < labDisplayName($1.name, language: summaryLanguage) }
    }
}
