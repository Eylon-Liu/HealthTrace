import SwiftUI
import Charts
import CoreData

struct TrendsView: View {
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var lang = "zh"

    var body: some View {
        Group {
            if pm.currentProfile == nil {
                EmptyStateView(icon: "chart.line.uptrend.xyaxis", message: L("请先选择档案", lang))
            } else {
                List {
                    NavigationLink {
                        LabTrendsDetailView()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.title2).foregroundColor(.blue)
                                .frame(width: 44, height: 44)
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("检验指标趋势", lang)).font(.subheadline.weight(.semibold))
                                Text(L("血检数值历史对比与趋势分析", lang)).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink {
                        ImagingCompareView()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.title2).foregroundColor(.purple)
                                .frame(width: 44, height: 44)
                                .background(Color.purple.opacity(0.12))
                                .cornerRadius(10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("影像报告对比", lang)).font(.subheadline.weight(.semibold))
                                Text(L("MRI/CT/X光等报告文字对比", lang)).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(lang == "en" ? "Trends" : "趋势分析")
    }
}

// MARK: - Lab Trends Detail View

struct LabTrendsDetailView: View {
    var initialLabItem: String? = nil

    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var summaryLanguage = "zh"

    @FetchRequest(sortDescriptors: [SortDescriptor(\.itemName)])
    private var allFavorites: FetchedResults<FavoriteLabItem>

    @FetchRequest(sortDescriptors: [SortDescriptor(\.reportDate, order: .reverse)])
    private var allReports: FetchedResults<MedicalReport>

    @State private var labItems: [String] = []
    @State private var selectedLabItem: String = ""
    @State private var labData: [LabDataPoint] = []
    @State private var favoriteTrends: [(name: String, points: [LabDataPoint])] = []

    private var favoriteNames: Set<String> {
        guard let p = pm.currentProfile else { return [] }
        return Set(allFavorites.filter { $0.profile == p }.compactMap { $0.itemName })
    }

    private var conditionNames: [String] {
        guard let p = pm.currentProfile else { return [] }
        return (p.conditions as? Set<Condition>)?.filter { $0.status == "active" || $0.status == "monitoring" }.compactMap { $0.name } ?? []
    }

    private var conditionRelatedItems: Set<String> {
        let conditions = conditionNames.map { $0.lowercased() }
        var related = Set<String>()
        for item in labItems {
            let lower = item.lowercased()
            let normalized = normalizeLabName(item).lowercased()
            for cond in conditions {
                if cond.contains("尿酸") && (normalized.contains("uric") || lower.contains("uric") || lower.contains("尿酸")) {
                    related.insert(item)
                }
                if (cond.contains("糖尿") || cond.contains("血糖")) && (normalized.contains("glucose") || normalized.contains("hba1c") || lower.contains("血糖") || lower.contains("糖化")) {
                    related.insert(item)
                }
                if cond.contains("肝") && (["ALT", "AST", "GGT", "ALP", "ALBUMIN", "BILIRUBIN_TOTAL", "BILIRUBIN_DIRECT"].contains(normalizeLabName(item))) {
                    related.insert(item)
                }
                if cond.contains("肾") && (["CREATININE", "BUN", "URIC_ACID"].contains(normalizeLabName(item))) {
                    related.insert(item)
                }
                if (cond.contains("贫血") || cond.contains("血")) && (["HGB", "RBC", "HCT", "IRON", "FERRITIN"].contains(normalizeLabName(item))) {
                    related.insert(item)
                }
                if cond.contains("甲状腺") && (["TSH", "T3", "T4", "FT3", "FT4"].contains(normalizeLabName(item))) {
                    related.insert(item)
                }
                if (cond.contains("胆固醇") || cond.contains("血脂")) && (["CHOLESTEROL", "TRIGLYCERIDES", "HDL", "LDL"].contains(normalizeLabName(item))) {
                    related.insert(item)
                }
            }
        }
        return related
    }

    private var sortedLabItems: [String] {
        let related = conditionRelatedItems
        let favs = favoriteNames
        return labItems.sorted { a, b in
            let aScore = (related.contains(a) ? 100 : 0) + (favs.contains(a) ? 50 : 0)
            let bScore = (related.contains(b) ? 100 : 0) + (favs.contains(b) ? 50 : 0)
            if aScore != bScore { return aScore > bScore }
            return labDisplayName(a, language: summaryLanguage) < labDisplayName(b, language: summaryLanguage)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !favoriteTrends.isEmpty { favoriteSection }

                VStack(alignment: .leading, spacing: 12) {
                    if labItems.isEmpty {
                        EmptyStateView(icon: "chart.line.uptrend.xyaxis", message: summaryLanguage == "en" ? "No lab data yet" : "暂无血检数据")
                    } else {
                        Picker(summaryLanguage == "en" ? "Select Lab" : "选择指标", selection: $selectedLabItem) {
                            Text(summaryLanguage == "en" ? "Select Lab" : "选择指标").tag("")
                            ForEach(sortedLabItems, id: \.self) { item in
                                let display = labDisplayName(item, language: summaryLanguage)
                                let prefix = conditionRelatedItems.contains(item) ? "🔴 " : (favoriteNames.contains(item) ? "⭐ " : "")
                                Text("\(prefix)\(display)").tag(item)
                            }
                        }
                        .pickerStyle(.menu)

                        if !selectedLabItem.isEmpty {
                            if labData.isEmpty {
                                Text(summaryLanguage == "en" ? "No data" : "暂无数据").foregroundColor(.secondary)
                            } else {
                                labChart
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            }
            .padding()
        }
        .navigationTitle(L("检验指标趋势", summaryLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadData()
            if let initial = initialLabItem, !initial.isEmpty, selectedLabItem.isEmpty {
                let key = normalizeLabName(initial)
                if let match = labItems.first(where: { normalizeLabName($0) == key }) {
                    selectedLabItem = match
                } else {
                    selectedLabItem = initial
                }
                loadLabData()
            }
        }
        .onChange(of: pm.currentProfile) { _ in loadData() }
        .onChange(of: selectedLabItem) { _ in loadLabData() }
    }

    // MARK: - Favorite section

    private var favoriteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill").foregroundColor(.yellow)
                Text(summaryLanguage == "en" ? "Favorites" : "关注指标").font(.headline)
            }

            ForEach(favoriteTrends, id: \.name) { trend in
                Button {
                    selectedLabItem = trend.name
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(labDisplayName(trend.name, language: summaryLanguage))
                                .font(.subheadline.weight(.medium))
                            if conditionRelatedItems.contains(trend.name) {
                                Text(summaryLanguage == "en" ? "Related" : "病史相关").font(.caption2).foregroundColor(.white)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Color.red).cornerRadius(3)
                            }
                            Spacer()
                            if let last = trend.points.last {
                                Text("\(String(format: "%g", last.numericValue)) \(last.unit)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(labStatusColor(last.status))
                                Text(labStatusLabel(last.status, language: summaryLanguage))
                                    .font(.caption2)
                                    .foregroundColor(labStatusColor(last.status))
                            }
                            Text(trendDirection(trend.points)).font(.caption)
                        }

                        if trend.points.count >= 2 {
                            Chart {
                                let refPoint = trend.points.first { $0.refLow != nil || $0.refHigh != nil }
                                if let lo = refPoint?.refLow, let hi = refPoint?.refHigh {
                                    RectangleMark(
                                        xStart: .value("", trend.points.first!.date),
                                        xEnd: .value("", trend.points.last!.date),
                                        yStart: .value("lo", lo), yEnd: .value("hi", hi)
                                    ).foregroundStyle(.green.opacity(0.1))
                                }
                                ForEach(trend.points) { p in
                                    LineMark(x: .value("", p.date), y: .value("", p.numericValue))
                                        .foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 2))
                                    PointMark(x: .value("", p.date), y: .value("", p.numericValue))
                                        .foregroundStyle(labStatusColor(p.status)).symbolSize(40)
                                }
                            }
                            .chartXAxis(.hidden).chartYAxis(.hidden)
                            .frame(height: 80)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .foregroundColor(.primary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Lab chart

    private var labChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            let displayName = labDisplayName(selectedLabItem, language: summaryLanguage)
            let unit = labData.first?.unit ?? ""
            let refPoint = labData.first { $0.refLow != nil || $0.refHigh != nil }
            let refLow = refPoint?.refLow
            let refHigh = refPoint?.refHigh

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(displayName)\(unit.isEmpty ? "" : " (\(unit))")")
                        .font(.subheadline.weight(.medium))
                    if selectedLabItem != displayName {
                        Text(selectedLabItem).font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let last = labData.last {
                    Text("\(String(format: "%g", last.numericValue))")
                        .font(.title3.bold()).foregroundColor(labStatusColor(last.status))
                    Text(labStatusLabel(last.status, language: summaryLanguage)).font(.caption).foregroundColor(labStatusColor(last.status))
                }
            }

            let refLabel = summaryLanguage == "en" ? "Ref range" : "正常范围"
            if let lo = refLow, let hi = refHigh {
                Text("\(refLabel)：\(fmt(lo)) – \(fmt(hi))\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.caption).foregroundColor(.secondary)
            } else if let hi = refHigh {
                Text("\(refLabel)：< \(fmt(hi))\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.caption).foregroundColor(.secondary)
            } else if let lo = refLow {
                Text("\(refLabel)：> \(fmt(lo))\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.caption).foregroundColor(.secondary)
            }

            if labData.count >= 2 {
                HStack(spacing: 4) {
                    Text(trendDirection(labData)).font(.caption)
                    Text(trendLabel(labData)).font(.caption).foregroundColor(.secondary)
                }
            }

            Chart {
                if let lo = refLow, let hi = refHigh, let first = labData.first, let last = labData.last {
                    RectangleMark(xStart: .value("", first.date), xEnd: .value("", last.date),
                                  yStart: .value("lo", lo), yEnd: .value("hi", hi))
                    .foregroundStyle(.green.opacity(0.1))
                }
                if let lo = refLow {
                    RuleMark(y: .value("下限", lo)).foregroundStyle(.green.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if let hi = refHigh {
                    RuleMark(y: .value("上限", hi)).foregroundStyle(.green.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                ForEach(labData) { point in
                    LineMark(x: .value("日期", point.date), y: .value("数值", point.numericValue))
                        .foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("日期", point.date), y: .value("数值", point.numericValue))
                        .foregroundStyle(labStatusColor(point.status)).symbolSize(60)
                        .annotation(position: .top) {
                            if point.status != "normal" {
                                Text(String(format: "%g", point.numericValue))
                                    .font(.system(size: 9)).foregroundColor(labStatusColor(point.status))
                            }
                        }
                }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }

            HStack(spacing: 16) {
                legendItem(color: .green, label: summaryLanguage == "en" ? "Normal" : "正常")
                legendItem(color: .red, label: summaryLanguage == "en" ? "High ↑" : "偏高 ↑")
                legendItem(color: .blue, label: summaryLanguage == "en" ? "Low ↓" : "偏低 ↓")
                HStack(spacing: 4) {
                    Rectangle().fill(.green.opacity(0.2)).frame(width: 12, height: 8).cornerRadius(2)
                    Text(summaryLanguage == "en" ? "Ref Range" : "正常范围")
                }
            }.font(.caption)

            Button { toggleFavorite(selectedLabItem) } label: {
                HStack {
                    Image(systemName: favoriteNames.contains(selectedLabItem) ? "star.fill" : "star")
                    Text(favoriteNames.contains(selectedLabItem)
                         ? (summaryLanguage == "en" ? "Tracked" : "已关注")
                         : (summaryLanguage == "en" ? "Track This" : "关注此指标"))
                }
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(favoriteNames.contains(selectedLabItem) ? Color.yellow.opacity(0.15) : Color(.tertiarySystemFill))
                .foregroundColor(favoriteNames.contains(selectedLabItem) ? .orange : .primary)
                .cornerRadius(20)
            }
        }
    }

    // MARK: - Helpers

    private func trendLabel(_ points: [LabDataPoint]) -> String {
        let en = summaryLanguage == "en"
        switch trendDirection(points) {
        case "↑": return en ? "Increasing" : "近期上升趋势"
        case "↓": return en ? "Decreasing" : "近期下降趋势"
        default: return en ? "Stable" : "趋势稳定"
        }
    }

    private func toggleFavorite(_ itemName: String) {
        guard let profile = pm.currentProfile, !itemName.isEmpty else { return }
        if let existing = allFavorites.first(where: { $0.profile == profile && $0.itemName == itemName }) {
            ctx.delete(existing)
        } else {
            let fav = FavoriteLabItem(context: ctx)
            fav.id = UUID()
            fav.itemName = itemName
            fav.createdAt = Date()
            fav.profile = profile
        }
        try? ctx.save()
        loadFavoriteTrends()
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 8, height: 8); Text(label) }
    }

    // MARK: - Data loading

    private func loadData() {
        guard let profile = pm.currentProfile else { return }

        let req = NSFetchRequest<NSDictionary>(entityName: "LabValue")
        req.resultType = .dictionaryResultType
        req.propertiesToFetch = ["itemName"]
        req.returnsDistinctResults = true
        req.predicate = NSPredicate(format: "report.profile == %@", profile)
        req.sortDescriptors = [NSSortDescriptor(key: "itemName", ascending: true)]
        let rawNames = ((try? ctx.fetch(req)) ?? []).compactMap { $0["itemName"] as? String }

        var seenKeys = Set<String>()
        var deduped = [String]()
        for name in rawNames {
            let key = normalizeLabName(name)
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                deduped.append(name)
            }
        }
        labItems = deduped
        if !labItems.contains(selectedLabItem) {
            // Check if selectedLabItem matches by normalized key
            let selectedKey = normalizeLabName(selectedLabItem)
            if let match = deduped.first(where: { normalizeLabName($0) == selectedKey }) {
                selectedLabItem = match
            } else {
                selectedLabItem = ""
            }
        }
        loadFavoriteTrends()
    }

    private func loadFavoriteTrends() {
        guard let profile = pm.currentProfile else { favoriteTrends = []; return }
        let favNames = allFavorites.filter { $0.profile == profile }.compactMap { $0.itemName }
        favoriteTrends = favNames.compactMap { name in
            let points = loadLabPoints(itemName: name, profile: profile)
            guard !points.isEmpty else { return nil }
            return (name: name, points: points)
        }
    }

    private func loadLabData() {
        guard let profile = pm.currentProfile, !selectedLabItem.isEmpty else { labData = []; return }
        labData = loadLabPoints(itemName: selectedLabItem, profile: profile)
    }

    private func loadLabPoints(itemName: String, profile: Profile) -> [LabDataPoint] {
        let normalizedKey = normalizeLabName(itemName)

        let req = NSFetchRequest<LabValue>(entityName: "LabValue")
        req.predicate = NSPredicate(format: "report.profile == %@", profile)
        req.sortDescriptors = [NSSortDescriptor(key: "report.reportDate", ascending: true)]
        let all = (try? ctx.fetch(req)) ?? []

        let matched = all.filter { normalizeLabName($0.itemName ?? "") == normalizedKey }
            .compactMap { lv -> LabDataPoint? in
                guard let date = lv.report?.reportDate,
                      let valStr = lv.value,
                      let val = Double(valStr.trimmingCharacters(in: .whitespaces)) else { return nil }
                let (low, high) = parseRefRange(lv.refRange)
                return LabDataPoint(date: date, numericValue: val, unit: lv.unit ?? "",
                                    status: lv.status ?? "", refLow: low, refHigh: high)
            }

        // Convert all points to the most common unit
        guard !matched.isEmpty else { return matched }
        let unitCounts = Dictionary(grouping: matched, by: { normalizeUnit($0.unit) })
        let targetUnit = unitCounts.max(by: { $0.value.count < $1.value.count })?.value.first?.unit ?? matched[0].unit

        return matched.map { point in
            if normalizeUnit(point.unit) == normalizeUnit(targetUnit) { return point }
            if let converted = convertLabValue(point.numericValue, from: point.unit, normalizedKey: normalizedKey, targetUnit: targetUnit) {
                let (lo, hi) = (
                    point.refLow.flatMap { convertLabValue($0, from: point.unit, normalizedKey: normalizedKey, targetUnit: targetUnit) },
                    point.refHigh.flatMap { convertLabValue($0, from: point.unit, normalizedKey: normalizedKey, targetUnit: targetUnit) }
                )
                return LabDataPoint(date: point.date, numericValue: converted, unit: targetUnit,
                                    status: point.status, refLow: lo, refHigh: hi)
            }
            return point
        }
    }

}

// MARK: - Imaging Compare View

struct ImagingCompareView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var lang = "zh"

    @State private var imagingReports: [MedicalReport] = []
    @State private var selectedForCompare: Set<NSManagedObjectID> = []
    @State private var showCompare = false

    private var useEN: Bool { lang == "en" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if imagingReports.isEmpty {
                    EmptyStateView(icon: "doc.text.magnifyingglass",
                                   message: useEN ? "No imaging records\n(MRI/CT/X-ray/Ultrasound)" : "暂无影像检查记录\n（MRI/CT/X光/超声）")
                } else {
                    Text(useEN ? "Select 2+ reports to compare" : "选择 2 份或更多报告进行文字对比")
                        .font(.caption).foregroundColor(.secondary).padding(.horizontal)
                    Text(useEN ? "Compare findings and conclusions across reports" : "对比报告中的检查发现和结论，追踪病情变化")
                        .font(.caption2).foregroundColor(.secondary).padding(.horizontal)

                    ForEach(imagingReports, id: \.id) { r in
                        let isSelected = selectedForCompare.contains(r.objectID)
                        Button {
                            if isSelected { selectedForCompare.remove(r.objectID) }
                            else { selectedForCompare.insert(r.objectID) }
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .blue : .secondary)
                                TypeBadge(type: r.reportType)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title ?? "").font(.subheadline).foregroundColor(.primary)
                                    Text([r.reportDate?.isoString, r.hospital].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(isSelected ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                    }

                    if selectedForCompare.count >= 2 {
                        Button {
                            showCompare = true
                        } label: {
                            Text(useEN ? "Compare \(selectedForCompare.count) Reports" : "对比 \(selectedForCompare.count) 份报告")
                                .frame(maxWidth: .infinity).padding(10)
                                .background(.blue).foregroundColor(.white).cornerRadius(8)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(useEN ? "Imaging Comparison" : "影像报告对比")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadReports() }
        .sheet(isPresented: $showCompare) {
            let reports = imagingReports.filter { selectedForCompare.contains($0.objectID) }
                .sorted { ($0.reportDate ?? .distantPast) < ($1.reportDate ?? .distantPast) }
            CompareView(reports: reports)
        }
    }

    private func loadReports() {
        guard let p = pm.currentProfile else { return }
        let req = NSFetchRequest<MedicalReport>(entityName: "MedicalReport")
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "profile == %@", p),
            NSPredicate(format: "reportType IN %@", ["MRI","CT","X光","超声","骨密度"])
        ])
        req.sortDescriptors = [NSSortDescriptor(key: "reportDate", ascending: false)]
        imagingReports = (try? ctx.fetch(req)) ?? []
    }
}

// MARK: - Data types

struct LabDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let numericValue: Double
    let unit: String
    let status: String
    var refLow: Double? = nil
    var refHigh: Double? = nil
}

struct CompareView: View {
    let reports: [MedicalReport]
    @Environment(\.dismiss) var dismiss
    @AppStorage("summaryLanguage") private var lang = "zh"
    @State private var viewMode = 0

    private var useEN: Bool { lang == "en" }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $viewMode) {
                    Text(useEN ? "Timeline" : "时间线").tag(0)
                    Text(useEN ? "Side by Side" : "并列对比").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if viewMode == 0 {
                    timelineView
                } else {
                    sideBySideView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(useEN ? "Report Comparison" : "报告对比")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(useEN ? "Close" : "关闭") { dismiss() } } }
        }
    }

    private var timelineView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(reports.enumerated()), id: \.element.id) { idx, r in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle().fill(idx == reports.count - 1 ? Color.blue : Color.gray.opacity(0.4))
                                .frame(width: 10, height: 10)
                            if idx < reports.count - 1 {
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 2)
                            }
                        }
                        .frame(width: 10)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TypeBadge(type: r.reportType)
                                Text(r.reportDate?.displayString ?? "").font(.caption).foregroundColor(.secondary)
                            }
                            Text(r.title ?? "").font(.subheadline.weight(.semibold))
                            if let h = r.hospital { Text(h).font(.caption).foregroundColor(.secondary) }

                            if let c = r.conclusion, !c.isEmpty {
                                Text(c).font(.caption).lineSpacing(3)
                                    .padding(8).background(Color.blue.opacity(0.06)).cornerRadius(6)
                            }

                            if let f = r.findings, !f.isEmpty {
                                Text(f).font(.caption).foregroundColor(.secondary).lineSpacing(3).lineLimit(4)
                            }

                            // Show changes vs previous report
                            if idx > 0 {
                                let changes = compareFindings(prev: reports[idx - 1], current: r)
                                if !changes.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(useEN ? "Changes from previous:" : "相比上次变化：")
                                            .font(.caption2.weight(.semibold)).foregroundColor(.orange)
                                        ForEach(changes, id: \.self) { change in
                                            Text(change).font(.caption2).foregroundColor(.orange)
                                        }
                                    }
                                    .padding(8).background(Color.orange.opacity(0.08)).cornerRadius(6)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .padding()
        }
    }

    private var sideBySideView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(reports, id: \.id) { r in
                    VStack(alignment: .leading, spacing: 10) {
                        TypeBadge(type: r.reportType)
                        Text(r.reportDate?.isoString ?? (useEN ? "Unknown" : "未知日期")).font(.caption).foregroundColor(.secondary)
                        Text(r.title ?? "").font(.subheadline.weight(.semibold))
                        if let h = r.hospital { Text(h).font(.caption).foregroundColor(.secondary) }
                        if let f = r.findings, !f.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(useEN ? "Findings" : "检查发现").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                                Text(f).font(.caption).lineSpacing(4)
                            }
                            .padding(8).background(Color(.secondarySystemBackground)).cornerRadius(6)
                        }
                        if let c = r.conclusion, !c.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(useEN ? "Conclusion" : "结论").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                                Text(c).font(.caption.weight(.medium))
                            }
                            .padding(8).background(Color.blue.opacity(0.06)).cornerRadius(6)
                        }
                    }
                    .frame(width: 280).padding()
                    .background(Color(.systemBackground)).cornerRadius(12)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                }
            }
            .padding()
        }
    }

    private func compareFindings(prev: MedicalReport, current: MedicalReport) -> [String] {
        var changes: [String] = []
        let prevConclusion = prev.conclusion ?? ""
        let currConclusion = current.conclusion ?? ""
        if !prevConclusion.isEmpty && !currConclusion.isEmpty && prevConclusion != currConclusion {
            if currConclusion.count < prevConclusion.count {
                changes.append(useEN ? "▼ Conclusion shortened (possible improvement)" : "▼ 结论缩短（可能好转）")
            } else if currConclusion.count > prevConclusion.count {
                changes.append(useEN ? "▲ Conclusion expanded (more findings)" : "▲ 结论增加（更多发现）")
            } else {
                changes.append(useEN ? "◆ Conclusion changed" : "◆ 结论有变化")
            }
        }
        let prevFindings = prev.findings ?? ""
        let currFindings = current.findings ?? ""
        if !prevFindings.isEmpty && !currFindings.isEmpty && prevFindings != currFindings {
            changes.append(useEN ? "◆ Findings changed from previous" : "◆ 检查发现有变化")
        }
        return changes
    }
}
