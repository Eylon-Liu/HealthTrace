import SwiftUI

// MARK: - Localization

private let translations: [String: String] = [
    "概览": "Overview", "报告": "Reports", "趋势": "Trends", "更多": "More",
    "检验指标": "Lab Tests", "病史记录": "Conditions", "活跃问题": "Active Issues",
    "检查报告": "Reports", "异常指标": "Abnormal", "最近报告": "Recent Reports",
    "关注趋势": "Tracked Trends", "活跃病症 & 限制": "Active Conditions & Restrictions",
    "暂无报告": "No reports yet", "暂无活跃病史记录": "No active conditions",
    "请先选择或创建档案": "Please select or create a profile",
    "请先选择档案": "Please select a profile",
    "的健康概览": "'s Health Overview", "健康概览": "Health Overview",
    "检验指标趋势": "Lab Trends", "血检数值历史对比与趋势分析": "Compare lab results over time",
    "影像报告对比": "Imaging Comparison", "MRI/CT/X光等报告文字对比": "Compare MRI/CT/X-ray reports",
    "病历摘要": "Medical Summary", "选择档案后生成病历摘要": "Select a profile to generate summary",
    "全部检验指标": "All Lab Tests", "搜索指标": "Search labs",
    "正常指标": "Normal",
    "项异常": " abnormal",
    "设置": "Settings", "语言 / Language": "Language",
    "AI 智能提取": "AI Extraction",
    "上传报告时，AI 自动提取标题、日期、医院、检验数值等信息。": "AI automatically extracts title, date, hospital, and lab values from uploaded reports.",
    "数据备份": "Data Backup",
    "导出备份（JSON）": "Export Backup (JSON)", "导入备份": "Import Backup",
    "换手机时：导出备份 → 将 JSON 文件发到新手机 → 在新手机导入。": "To transfer: Export → Send JSON to new device → Import on new device.",
    "关于": "About", "版本": "Version", "数据存储": "Storage", "本地设备": "On Device",
    "导出备份": "Export Backup", "全选": "Select All", "选择要导出的档案": "Select profiles to export",
    "取消": "Cancel", "导出": "Export",
    "份报告": " reports", "条病史": " conditions",
    "导出失败": "Export Failed", "导入成功": "Import Success", "导入失败": "Import Failed",
    "文件格式不正确": "Invalid file format",
    "好的": "OK",
    "活跃中": "Active", "观察中": "Monitoring", "已解决": "Resolved",
    "↑ 偏高": "↑ High", "↓ 偏低": "↓ Low", "正常": "Normal",
    "未命名": "Unnamed",
    "收藏指标": "Favorites", "全部指标": "All Labs",
    "AI 分析": "AI Analysis", "AI 健康摘要": "AI Health Summary",
    "生成 AI 健康摘要": "Generate AI Health Summary",
    "AI 分析本报告": "AI Analysis",
    "正在分析…": "Analyzing…",
    "正在生成…": "Generating…",
]

func L(_ zh: String, _ lang: String) -> String {
    if lang == "en", let en = translations[zh] { return en }
    return zh
}

func currentLang() -> String {
    UserDefaults.standard.string(forKey: "summaryLanguage") ?? "zh"
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Type badge color

func typeBadgeColor(_ type: String?) -> Color {
    switch type {
    case "MRI": return Color(hex: "#7C3AED")
    case "CT": return Color(hex: "#D97706")
    case "X光": return Color(hex: "#6B7280")
    case "血检": return Color(hex: "#DC2626")
    case "超声": return Color(hex: "#059669")
    case "骨密度": return Color(hex: "#2563EB")
    case "心电图": return Color(hex: "#DB2777")
    case "病理": return Color(hex: "#92400E")
    default: return Color(hex: "#6B7280")
    }
}

func typeBadgeBg(_ type: String?) -> Color {
    switch type {
    case "MRI": return Color(hex: "#EDE9FE")
    case "CT": return Color(hex: "#FEF3C7")
    case "X光": return Color(hex: "#F3F4F6")
    case "血检": return Color(hex: "#FEE2E2")
    case "超声": return Color(hex: "#D1FAE5")
    case "骨密度": return Color(hex: "#E0F2FE")
    case "心电图": return Color(hex: "#FCE7F3")
    case "病理": return Color(hex: "#FFF7ED")
    default: return Color(hex: "#F3F4F6")
    }
}

// MARK: - Status helpers

func statusColor(_ status: String?) -> Color {
    switch status {
    case "active": return .red
    case "monitoring": return .orange
    case "resolved": return .green
    default: return .gray
    }
}

func statusLabel(_ status: String?, language: String = "zh") -> String {
    let lang = language.isEmpty ? currentLang() : language
    switch status {
    case "active": return lang == "en" ? "Active" : "活跃中"
    case "monitoring": return lang == "en" ? "Monitoring" : "观察中"
    case "resolved": return lang == "en" ? "Resolved" : "已解决"
    default: return status ?? ""
    }
}

func labStatusColor(_ s: String?) -> Color {
    switch s {
    case "high": return .red
    case "low": return .blue
    case "normal": return .green
    default: return .primary
    }
}

func labStatusLabel(_ s: String?, language: String = "zh") -> String {
    let lang = language.isEmpty ? currentLang() : language
    switch s {
    case "high": return lang == "en" ? "↑ High" : "↑ 偏高"
    case "low": return lang == "en" ? "↓ Low" : "↓ 偏低"
    case "normal": return lang == "en" ? "Normal" : "正常"
    default: return ""
    }
}

// MARK: - Date helpers

extension Date {
    var displayString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale(identifier: currentLang() == "en" ? "en_US" : "zh_CN")
        return f.string(from: self)
    }

    var isoString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}

extension String {
    var isoDate: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: self)
    }
}

func ageString(from date: Date?) -> String {
    guard let date else { return "" }
    let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
    return currentLang() == "en" ? "\(years) yrs" : "\(years) 岁"
}

// MARK: - Shared lab data helpers

func parseRefRange(_ s: String?) -> (low: Double?, high: Double?) {
    guard let raw = s?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return (nil, nil) }
    let normalized = raw
        .replacingOccurrences(of: "～", with: "-").replacingOccurrences(of: "~", with: "-")
        .replacingOccurrences(of: "－", with: "-").replacingOccurrences(of: "—", with: "-")
        .replacingOccurrences(of: "≤", with: "<").replacingOccurrences(of: "≥", with: ">")
    let nums = extractNumbers(normalized)
    if normalized.contains("<") { return (nil, nums.first) }
    if normalized.contains(">") { return (nums.first, nil) }
    if nums.count >= 2 { return (Swift.min(nums[0], nums[1]), Swift.max(nums[0], nums[1])) }
    return (nil, nil)
}

func extractNumbers(_ s: String) -> [Double] {
    guard let regex = try? NSRegularExpression(pattern: "\\d+(\\.\\d+)?") else { return [] }
    let range = NSRange(s.startIndex..., in: s)
    return regex.matches(in: s, range: range).compactMap { m in
        guard let r = Range(m.range, in: s) else { return nil }
        return Double(s[r])
    }
}

func trendDirection(_ points: [LabDataPoint]) -> String {
    guard points.count >= 2 else { return "" }
    let last = points[points.count - 1].numericValue
    let prev = points[points.count - 2].numericValue
    let threshold = abs(prev) * 0.05
    if last - prev > threshold { return "↑" }
    if prev - last > threshold { return "↓" }
    return "→"
}

// MARK: - Lab name normalization

private let labNameMap: [(key: String, en: String, zh: String, aliases: [String])] = [
    ("WBC", "WBC", "白细胞", ["WHITE BLOOD CELL COUNT", "WHITE BLOOD CELLS", "WHITE BLOOD CELL"]),
    ("RBC", "RBC", "红细胞", ["RED BLOOD CELL COUNT", "RED BLOOD CELLS", "RED BLOOD CELL"]),
    ("HGB", "Hemoglobin", "血红蛋白", ["HEMOGLOBIN"]),
    ("HCT", "Hematocrit", "红细胞压积", ["HEMATOCRIT"]),
    ("PLT", "Platelets", "血小板", ["PLATELET COUNT", "PLATELET"]),
    ("MCV", "MCV", "平均红细胞体积", ["MEAN CORPUSCULAR VOLUME"]),
    ("MCH", "MCH", "平均血红蛋白量", ["MEAN CORPUSCULAR HEMOGLOBIN"]),
    ("MCHC", "MCHC", "平均血红蛋白浓度", ["MEAN CORPUSCULAR HB CONC"]),
    ("RDW", "RDW", "红细胞分布宽度", ["RED CELL DISTRIBUTION WIDTH"]),
    ("MPV", "MPV", "平均血小板体积", ["MEAN PLATELET VOLUME"]),
    ("NEUTROPHILS", "Neutrophils", "中性粒细胞", ["NEUTROPHIL", "ABSOLUTE NEUTROPHILS", "NEUTROPHILS, ABSOLUTE"]),
    ("LYMPHOCYTES", "Lymphocytes", "淋巴细胞", ["LYMPHOCYTE", "ABSOLUTE LYMPHOCYTES", "LYMPHOCYTES, ABSOLUTE"]),
    ("MONOCYTES", "Monocytes", "单核细胞", ["MONOCYTE", "ABSOLUTE MONOCYTES", "MONOCYTES, ABSOLUTE"]),
    ("EOSINOPHILS", "Eosinophils", "嗜酸性粒细胞", ["EOSINOPHIL", "ABSOLUTE EOSINOPHILS", "EOSINOPHILS, ABSOLUTE"]),
    ("BASOPHILS", "Basophils", "嗜碱性粒细胞", ["BASOPHIL", "ABSOLUTE BASOPHILS", "BASOPHILS, ABSOLUTE"]),
    ("ALT", "ALT", "谷丙转氨酶", ["ALANINE AMINOTRANSFERASE", "SGPT"]),
    ("AST", "AST", "谷草转氨酶", ["ASPARTATE AMINOTRANSFERASE", "SGOT"]),
    ("ALP", "ALP", "碱性磷酸酶", ["ALKALINE PHOSPHATASE"]),
    ("GGT", "GGT", "谷氨酰转肽酶", ["GAMMA-GLUTAMYL TRANSFERASE"]),
    ("ALBUMIN", "Albumin", "白蛋白", []),
    ("GLOBULIN", "Globulin", "球蛋白", []),
    ("TOTAL_PROTEIN", "Total Protein", "总蛋白", ["PROTEIN, TOTAL", "TOTAL PROTEIN"]),
    ("BILIRUBIN_TOTAL", "Total Bilirubin", "总胆红素", ["BILIRUBIN, TOTAL", "TOTAL BILIRUBIN"]),
    ("BILIRUBIN_DIRECT", "Direct Bilirubin", "直接胆红素", ["BILIRUBIN, DIRECT", "DIRECT BILIRUBIN"]),
    ("BUN", "BUN", "尿素氮", ["BLOOD UREA NITROGEN", "UREA NITROGEN"]),
    ("CREATININE", "Creatinine", "肌酐", []),
    ("URIC_ACID", "Uric Acid", "尿酸", ["URIC ACID"]),
    ("GLUCOSE", "Glucose", "血糖", ["FASTING GLUCOSE", "BLOOD GLUCOSE"]),
    ("HBA1C", "HbA1c", "糖化血红蛋白", ["HEMOGLOBIN A1C", "HEMOGLOBIN A1C", "A1C"]),
    ("CHOLESTEROL", "Total Cholesterol", "总胆固醇", ["CHOLESTEROL, TOTAL", "TOTAL CHOLESTEROL"]),
    ("TRIGLYCERIDES", "Triglycerides", "甘油三酯", []),
    ("HDL", "HDL", "高密度脂蛋白", ["HDL CHOLESTEROL", "HDL-CHOLESTEROL"]),
    ("LDL", "LDL", "低密度脂蛋白", ["LDL CHOLESTEROL", "LDL-CHOLESTEROL", "LDL CALCULATED"]),
    ("SODIUM", "Sodium", "钠", []),
    ("POTASSIUM", "Potassium", "钾", []),
    ("CHLORIDE", "Chloride", "氯", []),
    ("CALCIUM", "Calcium", "钙", []),
    ("PHOSPHORUS", "Phosphorus", "磷", ["PHOSPHATE"]),
    ("IRON", "Iron", "铁", []),
    ("FERRITIN", "Ferritin", "铁蛋白", []),
    ("TSH", "TSH", "促甲状腺激素", ["THYROID STIMULATING HORMONE"]),
    ("T3", "T3", "三碘甲状腺原氨酸", []),
    ("T4", "T4", "甲状腺素", []),
    ("FT3", "Free T3", "游离T3", ["FREE T3"]),
    ("FT4", "Free T4", "游离T4", ["FREE T4"]),
    ("CRP", "CRP", "C反应蛋白", ["C-REACTIVE PROTEIN"]),
    ("ESR", "ESR", "血沉", ["SED RATE", "SEDIMENTATION RATE"]),
    ("VITAMIN_D", "Vitamin D", "维生素D", ["25-HYDROXY VITAMIN D", "VITAMIN D, 25-OH"]),
    ("VITAMIN_B12", "Vitamin B12", "维生素B12", []),
    ("FOLATE", "Folate", "叶酸", ["FOLIC ACID"]),
    ("PSA", "PSA", "前列腺特异抗原", ["PROSTATE SPECIFIC ANTIGEN"]),
    ("CEA", "CEA", "癌胚抗原", ["CARCINOEMBRYONIC ANTIGEN"]),
    ("AFP", "AFP", "甲胎蛋白", ["ALPHA-FETOPROTEIN"]),
    ("OCCULT_BLOOD", "Occult Blood", "隐血", []),
    ("PH", "pH", "酸碱度", []),
    ("SPECIFIC_GRAVITY", "Specific Gravity", "比重", []),
    ("PROTEIN_URINE", "Urine Protein", "尿蛋白", []),
    ("SATURATION", "% Saturation", "转铁蛋白饱和度", ["IRON SATURATION", "TRANSFERRIN SATURATION"]),
    ("ALKALINE_PHOSPHATASE", "Alkaline Phosphatase", "碱性磷酸酶", []),
    ("A_G_RATIO", "Albumin/Globulin Ratio", "白球比", ["A/G RATIO"]),
    ("EGFR", "eGFR", "肾小球滤过率", ["ESTIMATED GFR", "GLOMERULAR FILTRATION RATE"]),
    ("CO2", "CO2", "二氧化碳", ["CARBON DIOXIDE"]),
    ("LD", "LD", "乳酸脱氢酶", ["LACTATE DEHYDROGENASE", "LDH"]),
    ("FRUCTOSAMINE", "Fructosamine", "果糖胺", []),
]

func normalizeLabName(_ raw: String) -> String {
    let upper = raw.uppercased()
        .replacingOccurrences(of: "（", with: "(")
        .replacingOccurrences(of: "）", with: ")")
        .trimmingCharacters(in: .whitespaces)

    // Try matching the full string first
    if let key = matchLabName(upper, raw: raw) { return key }

    // Strip parenthetical suffix and try again: "总胆固醇 (CHOL)" → "总胆固醇" + "CHOL"
    if let parenRange = upper.range(of: "\\s*\\([^)]+\\)\\s*$", options: .regularExpression) {
        let base = String(upper[upper.startIndex..<parenRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let inside = String(upper[parenRange]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces)
        if let key = matchLabName(base, raw: base) { return key }
        if let key = matchLabName(inside, raw: inside) { return key }
    }

    // Strip leading parenthetical prefix: "(UA) 尿酸" → "尿酸" + "UA"
    if let parenRange = upper.range(of: "^\\s*\\([^)]+\\)\\s*", options: .regularExpression) {
        let base = String(upper[parenRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        let inside = String(upper[parenRange]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces)
        if let key = matchLabName(base, raw: base) { return key }
        if let key = matchLabName(inside, raw: inside) { return key }
    }

    let cleaned = upper
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "%_", with: "PCT_")
        .replacingOccurrences(of: "ABSOLUTE_", with: "ABS_")
    return cleaned
}

private func matchLabName(_ upper: String, raw: String) -> String? {
    for entry in labNameMap {
        if upper == entry.key
            || upper == entry.en.uppercased()
            || upper == entry.zh
            || raw == entry.zh
            || entry.aliases.contains(where: { upper == $0 })
            || upper.contains(entry.key) && entry.key.count >= 3
            || raw.contains(entry.zh) && entry.zh.count >= 2 {
            return entry.key
        }
    }
    return nil
}

func labDisplayName(_ raw: String, language: String) -> String {
    let key = normalizeLabName(raw)
    let isEN = language == "en"
    if let entry = labNameMap.first(where: { $0.key == key }) {
        return isEN ? entry.en : entry.zh
    }
    return raw
}

// MARK: - Unit conversion for lab values

struct UnitConversion {
    let fromUnit: String
    let toUnit: String
    let factor: Double // multiply fromUnit value by this to get toUnit value
}

private let unitConversions: [String: [UnitConversion]] = [
    "URIC_ACID": [
        UnitConversion(fromUnit: "μmol/L", toUnit: "mg/dL", factor: 1.0 / 59.48),
        UnitConversion(fromUnit: "umol/L", toUnit: "mg/dL", factor: 1.0 / 59.48),
    ],
    "GLUCOSE": [
        UnitConversion(fromUnit: "mmol/L", toUnit: "mg/dL", factor: 18.02),
    ],
    "CHOLESTEROL": [
        UnitConversion(fromUnit: "mmol/L", toUnit: "mg/dL", factor: 38.67),
    ],
    "TRIGLYCERIDES": [
        UnitConversion(fromUnit: "mmol/L", toUnit: "mg/dL", factor: 88.57),
    ],
    "HDL": [
        UnitConversion(fromUnit: "mmol/L", toUnit: "mg/dL", factor: 38.67),
    ],
    "LDL": [
        UnitConversion(fromUnit: "mmol/L", toUnit: "mg/dL", factor: 38.67),
    ],
    "CREATININE": [
        UnitConversion(fromUnit: "μmol/L", toUnit: "mg/dL", factor: 1.0 / 88.4),
        UnitConversion(fromUnit: "umol/L", toUnit: "mg/dL", factor: 1.0 / 88.4),
    ],
    "BUN": [
        UnitConversion(fromUnit: "mmol/L", toUnit: "mg/dL", factor: 2.8),
    ],
    "BILIRUBIN_TOTAL": [
        UnitConversion(fromUnit: "μmol/L", toUnit: "mg/dL", factor: 1.0 / 17.1),
        UnitConversion(fromUnit: "umol/L", toUnit: "mg/dL", factor: 1.0 / 17.1),
    ],
    "BILIRUBIN_DIRECT": [
        UnitConversion(fromUnit: "μmol/L", toUnit: "mg/dL", factor: 1.0 / 17.1),
        UnitConversion(fromUnit: "umol/L", toUnit: "mg/dL", factor: 1.0 / 17.1),
    ],
    "CALCIUM": [
        UnitConversion(fromUnit: "mmol/L", toUnit: "mg/dL", factor: 4.0),
    ],
    "IRON": [
        UnitConversion(fromUnit: "μmol/L", toUnit: "μg/dL", factor: 5.585),
        UnitConversion(fromUnit: "umol/L", toUnit: "μg/dL", factor: 5.585),
    ],
    "HBA1C": [
        UnitConversion(fromUnit: "mmol/mol", toUnit: "%", factor: 0.0915),
    ],
]

func normalizeUnit(_ unit: String) -> String {
    unit.lowercased()
        .replacingOccurrences(of: "μ", with: "u")
        .replacingOccurrences(of: "µ", with: "u")
        .trimmingCharacters(in: .whitespaces)
}

func convertLabValue(_ value: Double, from fromUnit: String, normalizedKey: String, targetUnit: String) -> Double? {
    guard let conversions = unitConversions[normalizedKey] else { return nil }
    let fromNorm = normalizeUnit(fromUnit)
    let toNorm = normalizeUnit(targetUnit)
    if fromNorm == toNorm { return value }
    if let conv = conversions.first(where: { normalizeUnit($0.fromUnit) == fromNorm && normalizeUnit($0.toUnit) == toNorm }) {
        return value * conv.factor
    }
    if let conv = conversions.first(where: { normalizeUnit($0.toUnit) == fromNorm && normalizeUnit($0.fromUnit) == toNorm }) {
        return value / conv.factor
    }
    return nil
}

// MARK: - Avatar view

struct AvatarView: View {
    let letter: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Text(letter).font(.system(size: size * 0.45, weight: .bold)).foregroundColor(.white))
    }
}

// MARK: - Type badge

struct TypeBadge: View {
    let type: String?
    var body: some View {
        Text(type ?? "报告")
            .font(.caption2.weight(.semibold))
            .foregroundColor(typeBadgeColor(type))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(typeBadgeBg(type))
            .cornerRadius(4)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.gray.opacity(0.4))
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Photo picker wrapper (pick a report photo from the photo library)

import PhotosUI

struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }
            // Prefer the original image file (keeps format/quality); fall back to generic image type.
            let typeId = provider.registeredTypeIdentifiers.first {
                UTType($0)?.conforms(to: .image) == true
            } ?? UTType.image.identifier

            provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, _ in
                guard let url else { return }
                let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                let name = provider.suggestedName ?? "报告照片"
                // Unique subfolder so the clean filename can't collide across picks.
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent("\(name).\(ext)")
                try? FileManager.default.copyItem(at: url, to: dest)
                DispatchQueue.main.async { self.onPick(dest) }
            }
        }
    }
}

// MARK: - Document picker wrapper

import UIKit
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}

// MARK: - Activity view controller

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Avatar colors

let avatarColors: [(name: String, hex: String)] = [
    ("蓝", "#2563EB"), ("紫", "#7C3AED"), ("粉", "#DB2777"),
    ("绿", "#059669"), ("橙", "#D97706"), ("红", "#DC2626")
]

