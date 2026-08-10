import SwiftUI
import Charts
import CoreData
import Combine

struct DashboardView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @EnvironmentObject var router: TabRouter
    @AppStorage("summaryLanguage") private var lang = "zh"

    @FetchRequest(sortDescriptors: [SortDescriptor(\.reportDate, order: .reverse)])
    private var allReports: FetchedResults<MedicalReport>

    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)])
    private var allConditions: FetchedResults<Condition>

    @FetchRequest(sortDescriptors: [SortDescriptor(\.itemName)])
    private var allFavorites: FetchedResults<FavoriteLabItem>

    @State private var labItemCount = 0
    @State private var abnormalItems: [LabSnapshot] = []
    @State private var trendArrows: [String: String] = [:]
    @State private var favoriteTrends: [(name: String, points: [LabDataPoint])] = []
    @State private var abnormalHistory: [AbnormalPoint] = []

    /// One report's position in the abnormal timeline.
    struct AbnormalPoint {
        let date: Date
        let title: String
        let abnormalCount: Int
        let newAbnormals: [String]
        let resolved: [String]
    }

    private let previewLimit = 5

    private var reports: [MedicalReport] {
        guard let p = pm.currentProfile else { return [] }
        return allReports.filter { $0.profile == p }
    }

    private var activeConditions: [Condition] {
        guard let p = pm.currentProfile else { return [] }
        return allConditions.filter { $0.profile == p && ($0.status == "active" || $0.status == "monitoring") }
    }

    var body: some View {
        Group {
            if pm.currentProfile == nil {
                EmptyStateView(icon: "person.crop.circle", message: L("请先选择或创建档案", lang))
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        statsGrid
                        if !abnormalItems.isEmpty { abnormalCard }
                        if abnormalHistory.count >= 2 { abnormalProgressCard }
                        if !favoriteTrends.isEmpty { favoriteTrendsCard }
                        recentReportsCard
                        if !activeConditions.isEmpty { activeConditionsCard }
                    }
                    .padding(16)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(L("概览", lang))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadDashboardData() }
        .onChange(of: pm.currentProfile) { _ in loadDashboardData() }
        // A tab's onAppear does not fire again after the first visit, so adding a
        // report from another screen used to leave these numbers stale until relaunch.
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)) { _ in loadDashboardData() }
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            NavigationLink { AllLabItemsView() } label: {
                StatCard(title: L("检验指标", lang), value: "\(labItemCount)",
                         icon: "chart.line.uptrend.xyaxis", color: .green)
            }.buttonStyle(.plain)

            NavigationLink { AbnormalDetailView() } label: {
                StatCard(title: L("异常指标", lang), value: "\(abnormalItems.count)",
                         icon: "exclamationmark.triangle.fill", color: .red)
            }.buttonStyle(.plain)

            NavigationLink { ConditionsView() } label: {
                StatCard(title: L("活跃问题", lang), value: "\(activeConditions.count)",
                         icon: "exclamationmark.circle.fill", color: .orange)
            }.buttonStyle(.plain)

            // Goes to the reports tab rather than the summary screen, which is what
            // this card's number actually counts.
            Button { router.tab = TabRouter.reports } label: {
                StatCard(title: L("检查报告", lang), value: "\(reports.count)",
                         icon: "doc.text.fill", color: .blue)
            }.buttonStyle(.plain)
        }
    }

    // MARK: - Abnormal indicators

    private var abnormalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(icon: "exclamationmark.triangle.fill",
                       title: L("异常指标", lang), color: .orange) {
                Text(T("最新数值", "Latest value", lang)).font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            ForEach(abnormalItems.prefix(previewLimit)) { item in
                NavigationLink {
                    LabTrendsDetailView(initialLabItem: item.name)
                } label: {
                    LabValueRow(item: item, lang: lang, trend: trendArrows[item.key] ?? "")
                        .padding(.horizontal, 16).padding(.vertical, 9)
                }
                .foregroundColor(.primary)
                Divider().padding(.leading, 16)
            }

            NavigationLink { AbnormalDetailView() } label: {
                HStack {
                    Text(abnormalItems.count > previewLimit
                         ? T("查看全部 \(abnormalItems.count) 项异常", "See all \(abnormalItems.count) abnormal", lang)
                         : T("查看详情与 AI 解读", "Details & AI explanation", lang))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.blue)
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .healthCard()
    }

    // MARK: - Favorite trends sparklines

    private var favoriteTrendsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(icon: "star.fill", title: L("关注趋势", lang), color: .yellow)
                .padding(.horizontal, 16).padding(.vertical, 12)

            ForEach(favoriteTrends, id: \.name) { trend in
                NavigationLink { LabTrendsDetailView(initialLabItem: trend.name) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(labDisplayName(trend.name, language: lang))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if let last = trend.points.last {
                                Text("\(String(format: "%g", last.numericValue)) \(last.unit)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(labStatusColor(last.status))
                            }
                            Text(trendDirection(trend.points)).font(.caption)
                        }

                        if trend.points.count >= 2 {
                            sparkline(trend.points)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .foregroundColor(.primary)
                Divider().padding(.leading, 16)
            }
        }
        .healthCard()
    }

    private func sparkline(_ points: [LabDataPoint]) -> some View {
        Chart {
            let refPoint = points.first { $0.refLow != nil || $0.refHigh != nil }
            if let lo = refPoint?.refLow, let hi = refPoint?.refHigh,
               let first = points.first, let last = points.last {
                RectangleMark(xStart: .value("", first.date), xEnd: .value("", last.date),
                              yStart: .value("lo", lo), yEnd: .value("hi", hi))
                .foregroundStyle(.green.opacity(0.1))
            }
            ForEach(points) { p in
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

    // MARK: - Abnormal progress

    private var abnormalProgressCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(icon: "chart.bar.fill",
                       title: T("异常指标趋势", "Abnormal Trend", lang), color: .blue)
                .padding(.horizontal, 16).padding(.vertical, 12)

            if let latest = abnormalHistory.last, let earliest = abnormalHistory.first {
                let diff = latest.abnormalCount - earliest.abnormalCount
                HStack(spacing: 5) {
                    Image(systemName: diff < 0 ? "arrow.down.circle.fill"
                          : (diff > 0 ? "arrow.up.circle.fill" : "equal.circle.fill"))
                        .foregroundColor(diff < 0 ? .green : (diff > 0 ? .red : .blue))
                    Text(diff < 0
                         ? T("比首次报告减少 \(abs(diff)) 项异常", "\(abs(diff)) fewer abnormals vs first report", lang)
                         : (diff > 0
                            ? T("比首次报告增加 \(diff) 项异常", "\(diff) more abnormals vs first report", lang)
                            : T("异常数量无变化", "Abnormal count unchanged", lang)))
                    .font(.caption)
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }

            // Plotted against the report index, not a month label: two reports in the
            // same month share a label and used to collapse into one bar.
            // Each bar is keyed by report index, so equal spacing survives two
            // reports landing in the same month (a shared month label used to
            // collapse them into a single bar).
            Chart {
                ForEach(Array(abnormalHistory.enumerated()), id: \.offset) { idx, h in
                    BarMark(x: .value("", "\(idx)"), y: .value("", h.abnormalCount),
                            width: .ratio(0.5))
                        .foregroundStyle(h.abnormalCount == 0 ? .green : .red.opacity(0.75))
                        .annotation(position: .top) {
                            Text("\(h.abnormalCount)").font(.system(size: 9)).foregroundColor(.secondary)
                        }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    if let s = value.as(String.self), let i = Int(s),
                       abnormalHistory.indices.contains(i) {
                        AxisValueLabel {
                            Text(abnormalHistory[i].date
                                .formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 110)
            .padding(.horizontal, 16).padding(.bottom, 8)

            if let latest = abnormalHistory.last {
                if !latest.resolved.isEmpty {
                    changeRow(icon: "checkmark.circle.fill", color: .green,
                              title: T("好转：", "Improved: ", lang), names: latest.resolved)
                }
                if !latest.newAbnormals.isEmpty {
                    changeRow(icon: "exclamationmark.circle.fill", color: .red,
                              title: T("新增异常：", "New concerns: ", lang), names: latest.newAbnormals)
                }
            }
        }
        .healthCard()
    }

    private func changeRow(icon: String, color: Color, title: String, names: [String]) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: icon).foregroundColor(color).font(.caption)
            Text(title + names.map { labDisplayName($0, language: lang) }.joined(separator: "、"))
                .font(.caption).foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    // MARK: - Recent reports

    private var recentReportsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(icon: "doc.text.fill", title: L("最近报告", lang), color: .blue)
                .padding(.horizontal, 16).padding(.vertical, 12)

            if reports.isEmpty {
                Text(L("暂无报告", lang))
                    .font(.subheadline).foregroundColor(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 16)
            } else {
                ForEach(reports.prefix(previewLimit), id: \.objectID) { r in
                    NavigationLink { ReportDetailView(report: r) } label: {
                        reportRow(r)
                    }
                    Divider().padding(.leading, 16)
                }

                if reports.count > previewLimit {
                    Button { router.tab = TabRouter.reports } label: {
                        HStack {
                            Text(T("查看全部 \(reports.count) 份报告", "See all \(reports.count) reports", lang))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .font(.subheadline.weight(.medium)).foregroundColor(.blue)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
            }
        }
        .healthCard()
    }

    private func reportRow(_ r: MedicalReport) -> some View {
        HStack(spacing: 12) {
            TypeBadge(type: r.reportType)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title ?? "").font(.subheadline.weight(.medium))
                    .foregroundColor(.primary).lineLimit(1)
                Text([r.reportDate?.displayString, r.hospital].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            let abnCount = (r.labValues as? Set<LabValue>)?
                .filter { ($0.status ?? "").isEmpty == false && $0.status != "normal" }.count ?? 0
            if abnCount > 0 {
                Text(T("\(abnCount) 项异常", "\(abnCount) abnormal", lang))
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red.opacity(0.12))
                    .foregroundColor(.red)
                    .cornerRadius(4)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Active conditions

    private var activeConditionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(icon: "heart.fill", title: L("活跃病症 & 限制", lang), color: .red)
                .padding(.horizontal, 16).padding(.vertical, 12)

            ForEach(activeConditions, id: \.objectID) { c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(statusColor(c.status)).frame(width: 8, height: 8)
                        Text(c.name ?? "").font(.subheadline.weight(.medium))
                        Spacer()
                        Text(statusLabel(c.status, language: lang))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if let r = c.restrictions, !r.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange).font(.caption)
                            Text(r).font(.caption).foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider().padding(.leading, 16)
            }
        }
        .healthCard()
    }

    // MARK: - Data loading

    private func loadDashboardData() {
        guard let p = pm.currentProfile else {
            labItemCount = 0; abnormalItems = []; favoriteTrends = []; abnormalHistory = []
            return
        }

        let snapshots = lastTestedLabValues(for: p, in: ctx)
        labItemCount = snapshots.count
        abnormalItems = snapshots.filter { $0.isAbnormal }
            .sorted { labDisplayName($0.name, language: lang) < labDisplayName($1.name, language: lang) }
        trendArrows = labTrendArrows(for: p, in: ctx)

        loadAbnormalHistory()
        loadFavoriteTrends(profile: p)
    }

    /// Walks reports oldest → newest carrying each item's last known status forward.
    /// An item counts as resolved only when a later report re-tested it and it came
    /// back normal; simply not being re-tested leaves it abnormal.
    private func loadAbnormalHistory() {
        let sorted = reports.sorted { ($0.reportDate ?? .distantPast) < ($1.reportDate ?? .distantPast) }
        var lastStatus: [String: String] = [:]
        var displayName: [String: String] = [:]

        abnormalHistory = sorted.compactMap { r -> AbnormalPoint? in
            guard let date = r.reportDate else { return nil }
            let lvs = (r.labValues as? Set<LabValue>) ?? []
            let scored = lvs.filter { !($0.status ?? "").isEmpty }
            guard !scored.isEmpty else { return nil }

            let testedNow = Set(scored.compactMap { $0.itemName }.map { normalizeLabName($0) })
            let previouslyAbnormal = Set(lastStatus.filter { $0.value != "normal" }.keys)

            for lv in scored {
                guard let name = lv.itemName, let status = lv.status else { continue }
                let key = normalizeLabName(name)
                lastStatus[key] = status
                displayName[key] = name
            }

            let nowAbnormal = Set(lastStatus.filter { $0.value != "normal" }.keys)
            let newlyAbnormal = nowAbnormal.subtracting(previouslyAbnormal)
            let resolved = previouslyAbnormal.filter { testedNow.contains($0) && !nowAbnormal.contains($0) }

            return AbnormalPoint(
                date: date,
                title: r.title ?? "",
                abnormalCount: nowAbnormal.count,
                newAbnormals: newlyAbnormal.map { displayName[$0] ?? $0 }.sorted(),
                resolved: resolved.map { displayName[$0] ?? $0 }.sorted())
        }
    }

    private func loadFavoriteTrends(profile p: Profile) {
        let favNames = allFavorites.filter { $0.profile == p }.compactMap { $0.itemName }
        favoriteTrends = favNames.compactMap { name in
            let key = normalizeLabName(name)
            let req = NSFetchRequest<LabValue>(entityName: "LabValue")
            req.predicate = NSPredicate(format: "report.profile == %@", p)
            req.sortDescriptors = [NSSortDescriptor(key: "report.reportDate", ascending: true)]
            let results = (try? ctx.fetch(req)) ?? []
            let points = results
                .filter { normalizeLabName($0.itemName ?? "") == key }
                .compactMap { lv -> LabDataPoint? in
                    guard let date = lv.report?.reportDate,
                          let val = Double((lv.value ?? "").trimmingCharacters(in: .whitespaces))
                    else { return nil }
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title2.bold())
                Text(title).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .healthCard(padding: 14)
    }
}
