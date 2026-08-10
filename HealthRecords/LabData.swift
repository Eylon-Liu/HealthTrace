import SwiftUI
import CoreData

// MARK: - Last tested value
//
// The dashboard, the abnormal list and the all-labs list all answer the same
// question: "what is the most recent result for each test this person has had?"
// They used to each re-implement the fetch and the dedup. This is that logic, once.

/// One lab item at its most recently tested value.
struct LabSnapshot: Identifiable {
    /// Normalized name — stable identity for the same test across reports that spell it differently.
    let key: String
    /// Raw name as printed on the newest report that contains it.
    let name: String
    let value: String
    let unit: String
    let status: String
    let refRange: String
    let reportDate: Date?
    let reportTitle: String

    var id: String { key }
    var isAbnormal: Bool { !status.isEmpty && status != "normal" }
}

/// Every lab item a profile has ever had, at its latest tested value.
///
/// An item stays in the list at its last known value even if the newest report
/// didn't re-test it — not being re-tested is not the same as being resolved.
func lastTestedLabValues(for profile: Profile, in ctx: NSManagedObjectContext) -> [LabSnapshot] {
    let req = NSFetchRequest<LabValue>(entityName: "LabValue")
    req.predicate = NSPredicate(format: "report.profile == %@", profile)
    req.sortDescriptors = [NSSortDescriptor(key: "report.reportDate", ascending: false)]
    let all = (try? ctx.fetch(req)) ?? []

    var seen = Set<String>()
    return all.compactMap { lv in
        guard let name = lv.itemName, !name.isEmpty else { return nil }
        let key = normalizeLabName(name)
        guard !seen.contains(key) else { return nil }
        seen.insert(key)
        return LabSnapshot(key: key, name: name, value: lv.value ?? "", unit: lv.unit ?? "",
                           status: lv.status ?? "", refRange: lv.refRange ?? "",
                           reportDate: lv.report?.reportDate, reportTitle: lv.report?.title ?? "")
    }
}

/// Trend arrow (↑ / ↓ / →) per normalized lab key, comparing the two most recent numeric results.
/// Keyed by normalized name so a rename between reports doesn't silently drop the comparison.
func labTrendArrows(for profile: Profile, in ctx: NSManagedObjectContext) -> [String: String] {
    let req = NSFetchRequest<LabValue>(entityName: "LabValue")
    req.predicate = NSPredicate(format: "report.profile == %@", profile)
    req.sortDescriptors = [NSSortDescriptor(key: "report.reportDate", ascending: false)]
    let all = (try? ctx.fetch(req)) ?? []

    var byKey: [String: [Double]] = [:]
    for lv in all {
        guard let name = lv.itemName,
              let v = Double((lv.value ?? "").trimmingCharacters(in: .whitespaces)) else { continue }
        let key = normalizeLabName(name)
        if (byKey[key]?.count ?? 0) < 2 { byKey[key, default: []].append(v) }
    }

    var arrows: [String: String] = [:]
    for (key, values) in byKey where values.count >= 2 {
        let diff = values[0] - values[1]
        let threshold = abs(values[1]) * 0.05
        arrows[key] = diff > threshold ? "↑" : (diff < -threshold ? "↓" : "→")
    }
    return arrows
}

/// Fingerprint of the records an AI summary was based on. When this changes,
/// cached AI text is flagged as out of date rather than shown as if current.
func recordsSignature(for profile: Profile, in ctx: NSManagedObjectContext) -> String {
    let reportReq = NSFetchRequest<MedicalReport>(entityName: "MedicalReport")
    reportReq.predicate = NSPredicate(format: "profile == %@", profile)
    let reports = (try? ctx.fetch(reportReq)) ?? []
    let newest = reports.compactMap { $0.reportDate }.max()?.isoString ?? "-"

    let condReq = NSFetchRequest<Condition>(entityName: "Condition")
    condReq.predicate = NSPredicate(format: "profile == %@", profile)
    let conditions = (try? ctx.fetch(condReq)) ?? []

    return "r\(reports.count)-c\(conditions.count)-\(newest)"
}

func labSignature(_ items: [LabSnapshot]) -> String {
    items.map { "\($0.key):\($0.value)" }.sorted().joined(separator: "|")
}

// MARK: - Display labels for stored Chinese enum values
//
// Report type and body part are stored as Chinese strings. They were rendered
// raw everywhere, so English mode showed Chinese badges and section headers.

private let reportTypeEN: [String: String] = [
    "MRI": "MRI", "CT": "CT", "X光": "X-ray", "血检": "Blood Test", "超声": "Ultrasound",
    "骨密度": "Bone Density", "心电图": "ECG", "病理": "Pathology", "其他": "Other",
    // Types that arrive from AI extraction rather than the picker.
    "体检": "Check-up", "化验": "Lab Test", "尿检": "Urinalysis", "核磁": "MRI",
    "内镜": "Endoscopy", "胃镜": "Gastroscopy", "肠镜": "Colonoscopy", "报告": "Report",
]

private let bodyPartEN: [String: String] = [
    "腰椎": "Lumbar Spine", "颈椎": "Cervical Spine", "胸椎": "Thoracic Spine",
    "膝关节": "Knee", "髋关节": "Hip", "肩关节": "Shoulder", "头颅": "Head",
    "胸部": "Chest", "腹部": "Abdomen", "血液": "Blood", "其他": "Other",
]

func reportTypeLabel(_ type: String?, lang: String) -> String {
    guard let type, !type.isEmpty else { return lang == "en" ? "Report" : "报告" }
    return lang == "en" ? (reportTypeEN[type] ?? type) : type
}

func bodyPartLabel(_ part: String?, lang: String) -> String {
    guard let part, !part.isEmpty else { return lang == "en" ? "Other" : "其他" }
    return lang == "en" ? (bodyPartEN[part] ?? part) : part
}

/// "Other" sorts last rather than wherever its name happens to fall alphabetically.
func bodyPartSortKey(_ part: String) -> String {
    (part == "其他" || part == "Other") ? "\u{FFFF}" : part
}

// MARK: - Shared lab row

/// One lab result line, used by the dashboard, the abnormal list and the all-labs list
/// so the same value never renders three different ways.
struct LabValueRow: View {
    let item: LabSnapshot
    var lang: String = "zh"
    var trend: String = ""
    var showChevron: Bool = true
    var isFavorite: Bool = false

    private var display: String { labDisplayName(item.name, language: lang) }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(labStatusColor(item.status)).frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if isFavorite {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundColor(.yellow)
                    }
                    Text(display).font(.subheadline).lineLimit(1)
                }
                if display != item.name {
                    Text(item.name).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Text(item.value).font(.subheadline.bold()).foregroundColor(labStatusColor(item.status))
            if !item.unit.isEmpty {
                Text(item.unit).font(.caption2).foregroundColor(.secondary)
            }
            if item.isAbnormal {
                Text(labStatusLabel(item.status, language: lang))
                    .font(.caption2).foregroundColor(labStatusColor(item.status))
            }
            if !trend.isEmpty { Text(trend).font(.caption) }
            if showChevron {
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}
