import SwiftUI
import Charts
import CoreData

struct DashboardView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var summaryLanguage = "zh"

    @FetchRequest(sortDescriptors: [SortDescriptor(\.reportDate, order: .reverse)])
    private var allReports: FetchedResults<MedicalReport>

    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)])
    private var allConditions: FetchedResults<Condition>

    @FetchRequest(sortDescriptors: [SortDescriptor(\.itemName)])
    private var allFavorites: FetchedResults<FavoriteLabItem>

    @State private var labItemCount = 0
    @State private var abnormalItems: [(name: String, value: String, unit: String, status: String, trend: String)] = []
    @State private var favoriteTrends: [(name: String, points: [LabDataPoint])] = []
    @State private var abnormalHistory: [(date: Date, title: String, abnormalCount: Int, totalCount: Int, newAbnormals: [String], resolved: [String])] = []

    private var reports: [MedicalReport] {
        guard let p = pm.currentProfile else { return [] }
        return allReports.filter { $0.profile == p }
    }

    private var conditions: [Condition] {
        guard let p = pm.currentProfile else { return [] }
        return allConditions.filter { $0.profile == p }
    }

    private var activeConditions: [Condition] {
        conditions.filter { $0.status == "active" || $0.status == "monitoring" }
    }

    var body: some View {
        Group {
            if pm.currentProfile == nil {
                EmptyStateView(icon: "person.crop.circle", message: L("请先选择或创建档案", summaryLanguage))
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        statsGrid
                        if !abnormalItems.isEmpty { abnormalCard }
                        if abnormalHistory.count >= 2 { abnormalProgressCard }
                        if !favoriteTrends.isEmpty { favoriteTrendsCard }
                        recentReportsCard
                        activeConditionsCard
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(pm.currentProfile.map { summaryLanguage == "en" ? "\($0.name ?? "")'s Health Overview" : "\($0.name ?? "")的健康概览" } ?? L("健康概览", summaryLanguage))
        .navigationBarTitleDisplayMode(.large)
        .onAppear { loadDashboardData() }
        .onChange(of: pm.currentProfile) { _ in loadDashboardData() }
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            NavigationLink { AllLabItemsView() } label: {
                StatCard(title: L("检验指标", summaryLanguage), value: "\(labItemCount)", icon: "chart.line.uptrend.xyaxis", color: .green)
            }.buttonStyle(.plain)

            NavigationLink { AbnormalDetailView() } label: {
                StatCard(title: L("异常指标", summaryLanguage), value: "\(abnormalItems.count)", icon: "exclamationmark.triangle.fill", color: .red)
            }.buttonStyle(.plain)

            NavigationLink { ConditionsView() } label: {
                StatCard(title: L("活跃问题", summaryLanguage), value: "\(activeConditions.count)", icon: "exclamationmark.circle.fill", color: .orange)
            }.buttonStyle(.plain)

            NavigationLink { SummaryView() } label: {
                StatCard(title: L("检查报告", summaryLanguage), value: "\(reports.count)", icon: "doc.text.fill", color: .blue)
            }.buttonStyle(.plain)
        }
    }

    // MARK: - Abnormal indicators

    private var abnormalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(L("异常指标", summaryLanguage)).font(.headline)
                Spacer()
                Text(L("最近报告", summaryLanguage)).font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ForEach(abnormalItems, id: \.name) { item in
                NavigationLink {
                    LabTrendsDetailView(initialLabItem: item.name)
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(labStatusColor(item.status)).frame(width: 8, height: 8)
                        Text(labDisplayName(item.name, language: summaryLanguage)).font(.subheadline)
                        Spacer()
                        Text(item.value).font(.subheadline.bold()).foregroundColor(labStatusColor(item.status))
                        if !item.unit.isEmpty {
                            Text(item.unit).font(.caption2).foregroundColor(.secondary)
                        }
                        Text(labStatusLabel(item.status, language: summaryLanguage)).font(.caption2).foregroundColor(labStatusColor(item.status))
                        if !item.trend.isEmpty {
                            Text(item.trend).font(.caption)
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider().padding(.leading, 16)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Favorite trends sparklines

    private var favoriteTrendsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "star.fill").foregroundColor(.yellow)
                Text(L("关注趋势", summaryLanguage)).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ForEach(favoriteTrends, id: \.name) { trend in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(labDisplayName(trend.name, language: summaryLanguage)).font(.subheadline.weight(.medium))
                        Spacer()
                        if let last = trend.points.last {
                            Text("\(String(format: "%g", last.numericValue)) \(last.unit)")
                                .font(.subheadline.bold())
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
                                    yStart: .value("lo", lo),
                                    yEnd: .value("hi", hi)
                                )
                                .foregroundStyle(.green.opacity(0.1))
                            }
                            ForEach(trend.points) { p in
                                LineMark(x: .value("", p.date), y: .value("", p.numericValue))
                                    .foregroundStyle(.blue)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                                PointMark(x: .value("", p.date), y: .value("", p.numericValue))
                                    .foregroundStyle(labStatusColor(p.status))
                                    .symbolSize(30)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 50)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider().padding(.leading, 16)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Abnormal progress card

    private var abnormalProgressCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "chart.bar.fill").foregroundColor(.blue)
                Text(summaryLanguage == "en" ? "Abnormal Trend" : "异常指标趋势").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if let latest = abnormalHistory.last, let earliest = abnormalHistory.first {
                let diff = latest.abnormalCount - earliest.abnormalCount
                HStack(spacing: 4) {
                    Image(systemName: diff < 0 ? "arrow.down.circle.fill" : (diff > 0 ? "arrow.up.circle.fill" : "equal.circle.fill"))
                        .foregroundColor(diff < 0 ? .green : (diff > 0 ? .red : .blue))
                    Text(diff < 0
                         ? (summaryLanguage == "en" ? "\(abs(diff)) fewer abnormals vs first report" : "比首次报告减少 \(abs(diff)) 项异常")
                         : (diff > 0
                            ? (summaryLanguage == "en" ? "\(diff) more abnormals vs first report" : "比首次报告增加 \(diff) 项异常")
                            : (summaryLanguage == "en" ? "Abnormal count unchanged" : "异常数量无变化")))
                    .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Chart {
                ForEach(abnormalHistory, id: \.date) { h in
                    let label = h.date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
                    BarMark(x: .value("", label), y: .value("", h.abnormalCount))
                        .foregroundStyle(h.abnormalCount == 0 ? .green : .red.opacity(0.7))
                        .annotation(position: .top) {
                            Text("\(h.abnormalCount)").font(.system(size: 9)).foregroundColor(.secondary)
                        }
                }
            }
            .frame(height: 100)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Show what improved / worsened
            if let latest = abnormalHistory.last {
                if !latest.resolved.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                        Text((summaryLanguage == "en" ? "Improved: " : "好转：") + latest.resolved.map { labDisplayName($0, language: summaryLanguage) }.joined(separator: ", "))
                            .font(.caption).foregroundColor(.green)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 4)
                }
                if !latest.newAbnormals.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red).font(.caption)
                        Text((summaryLanguage == "en" ? "New concerns: " : "新增异常：") + latest.newAbnormals.map { labDisplayName($0, language: summaryLanguage) }.joined(separator: ", "))
                            .font(.caption).foregroundColor(.red)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Recent reports

    private var recentReportsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("最近报告", summaryLanguage)).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if reports.isEmpty {
                Text(L("暂无报告", summaryLanguage))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(reports.prefix(5), id: \.id) { r in
                    NavigationLink {
                        ReportDetailView(report: r)
                    } label: {
                        HStack(spacing: 12) {
                            TypeBadge(type: r.reportType)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title ?? "").font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                Text([r.reportDate?.displayString, r.hospital].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            let abnCount = (r.labValues as? Set<LabValue>)?.filter { $0.status != "normal" && $0.status != nil && !($0.status ?? "").isEmpty }.count ?? 0
                            if abnCount > 0 {
                                Text(summaryLanguage == "en" ? "\(abnCount) abnormal" : "\(abnCount)项异常")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(4)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Active conditions

    private var activeConditionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("活跃病症 & 限制", summaryLanguage))
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if activeConditions.isEmpty {
                Text(L("暂无活跃病史记录", summaryLanguage))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(activeConditions, id: \.id) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor(c.status))
                                .frame(width: 8, height: 8)
                            Text(c.name ?? "").font(.subheadline.weight(.medium))
                            Spacer()
                            Text(statusLabel(c.status, language: summaryLanguage)).font(.caption).foregroundColor(.secondary)
                        }
                        if let r = c.restrictions, !r.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text(r).font(.caption).foregroundColor(.orange)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Data loading

    private func loadDashboardData() {
        guard let p = pm.currentProfile else {
            labItemCount = 0; abnormalItems = []; favoriteTrends = []
            return
        }

        // Lab item count (deduplicated by normalized key)
        let req = NSFetchRequest<NSDictionary>(entityName: "LabValue")
        req.resultType = .dictionaryResultType
        req.propertiesToFetch = ["itemName"]
        req.returnsDistinctResults = true
        req.predicate = NSPredicate(format: "report.profile == %@", p)
        let rawNames = ((try? ctx.fetch(req)) ?? []).compactMap { $0["itemName"] as? String }
        var seenKeys = Set<String>()
        for name in rawNames { seenKeys.insert(normalizeLabName(name)) }
        labItemCount = seenKeys.count

        // Abnormal items: last-tested value per item across ALL reports
        let allLVReq = NSFetchRequest<LabValue>(entityName: "LabValue")
        allLVReq.predicate = NSPredicate(format: "report.profile == %@", p)
        allLVReq.sortDescriptors = [NSSortDescriptor(key: "report.reportDate", ascending: false)]
        let allLVs = (try? ctx.fetch(allLVReq)) ?? []

        var seenItemKeys = Set<String>()
        var lastTestedAbnormals: [(name: String, value: String, unit: String, status: String)] = []
        var abnormalNames = Set<String>()

        for lv in allLVs {
            guard let name = lv.itemName else { continue }
            let key = normalizeLabName(name)
            guard !seenItemKeys.contains(key) else { continue }
            seenItemKeys.insert(key)
            let status = lv.status ?? ""
            if !status.isEmpty && status != "normal" {
                lastTestedAbnormals.append((name: name, value: lv.value ?? "", unit: lv.unit ?? "", status: status))
                abnormalNames.insert(name)
            }
        }

        var trendMap: [String: String] = [:]
        if !abnormalNames.isEmpty {
            let grouped = Dictionary(grouping: allLVs.filter { abnormalNames.contains($0.itemName ?? "") }) { $0.itemName ?? "" }
            for (name, vals) in grouped {
                let values = vals.prefix(3).compactMap { Double($0.value ?? "") }
                guard values.count >= 2 else { continue }
                let diff = values[0] - values[1]
                let threshold = abs(values[1]) * 0.05
                trendMap[name] = diff > threshold ? "↑" : (diff < -threshold ? "↓" : "→")
            }
        }

        abnormalItems = lastTestedAbnormals
            .sorted { ($0.name) < ($1.name) }
            .map { item in
                let trend = trendMap[item.name] ?? ""
                return (name: item.name, value: item.value, unit: item.unit, status: item.status, trend: trend)
            }

        // Abnormal history across reports (running state tracks last-tested status per item)
        let sortedReports = reports.sorted { ($0.reportDate ?? .distantPast) < ($1.reportDate ?? .distantPast) }
        var itemLastStatus: [String: String] = [:]
        abnormalHistory = sortedReports.compactMap { r -> (date: Date, title: String, abnormalCount: Int, totalCount: Int, newAbnormals: [String], resolved: [String])? in
            guard let date = r.reportDate else { return nil }
            let lvs = (r.labValues as? Set<LabValue>) ?? []
            let labReports = lvs.filter { $0.status != nil && !($0.status ?? "").isEmpty }
            guard !labReports.isEmpty else { return nil }

            let testedInThisReport = Set(lvs.compactMap { $0.itemName }.map { normalizeLabName($0) })
            let prevAbnormalKeys = Set(itemLastStatus.filter { $0.value != "normal" }.keys)

            for lv in lvs {
                guard let name = lv.itemName, let status = lv.status, !status.isEmpty else { continue }
                itemLastStatus[normalizeLabName(name)] = status
            }

            let currentAbnormalKeys = Set(itemLastStatus.filter { $0.value != "normal" }.keys)
            let newAbnormals = Array(currentAbnormalKeys.subtracting(prevAbnormalKeys))
            let resolved = Array(prevAbnormalKeys.filter { key in
                testedInThisReport.contains(key) && !currentAbnormalKeys.contains(key)
            })

            return (date: date, title: r.title ?? "", abnormalCount: currentAbnormalKeys.count, totalCount: labReports.count,
                    newAbnormals: newAbnormals, resolved: resolved)
        }

        // Favorite trends
        let favNames = allFavorites.filter { $0.profile == p }.compactMap { $0.itemName }
        favoriteTrends = favNames.compactMap { name in
            let lvReq = NSFetchRequest<LabValue>(entityName: "LabValue")
            lvReq.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "report.profile == %@", p),
                NSPredicate(format: "itemName == %@", name)
            ])
            lvReq.sortDescriptors = [NSSortDescriptor(key: "report.reportDate", ascending: true)]
            let results = (try? ctx.fetch(lvReq)) ?? []
            let points = results.compactMap { lv -> LabDataPoint? in
                guard let date = lv.report?.reportDate,
                      let valStr = lv.value,
                      let val = Double(valStr.trimmingCharacters(in: .whitespaces)) else { return nil }
                let (low, high) = parseRefRange(lv.refRange)
                return LabDataPoint(date: date, numericValue: val, unit: lv.unit ?? "",
                                    status: lv.status ?? "", refLow: low, refHigh: high)
            }
            guard !points.isEmpty else { return nil }
            return (name: name, points: points)
        }
    }


}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12))
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title2.bold())
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}
