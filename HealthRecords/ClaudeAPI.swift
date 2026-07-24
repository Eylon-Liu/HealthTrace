import Foundation
import UniformTypeIdentifiers
import PDFKit
import SwiftUI

// MARK: - Data models

struct ExtractedReport: Codable {
    var title: String?
    var report_date: String?
    var hospital: String?
    var doctor: String?
    var report_type: String?
    var body_part: String?
    var language: String?
    var findings: String?
    var conclusion: String?
    var recommendations: String?
    var lab_values: [ExtractedLabValue]?
}

struct ExtractedLabValue: Codable {
    var name: String?
    var value: String?
    var unit: String?
    var ref_range: String?
    var status: String?
}

// MARK: - Provider enum

enum AIProvider: String, CaseIterable {
    case gemini = "gemini"
    case deepseek = "deepseek"

    var displayName: String {
        switch self {
        case .gemini: return "Gemini (推荐)"
        case .deepseek: return "DeepSeek"
        }
    }

    var modelName: String {
        switch self {
        case .gemini:
            // Read persisted selection; default to gemini-3.5-flash
            let selected = UserDefaults.standard.string(forKey: "gemini_model") ?? "gemini-3.5-flash"
            return selected
        case .deepseek:
            return "deepseek-chat"
        }
    }

    var supportsVision: Bool {
        switch self {
        case .gemini: return true
        case .deepseek: return false
        }
    }
}

// MARK: - Errors

enum AIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case parseError
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "请先在设置中填写 API Key"
        case .invalidResponse: return "服务器返回无效响应"
        case .apiError(let msg): return msg
        case .parseError: return "无法解析 AI 返回的内容"
        case .unsupportedFormat(let msg): return msg
        }
    }
}

// MARK: - Prompt

private let extractionPrompt = """
你是一个专业医疗报告分析助手。分析这份医疗报告，以JSON格式返回（只返回JSON，不要其他文字）：
{
  "title": "报告标题（如：年度健康体检报告、腰椎MRI）",
  "report_date": "YYYY-MM-DD或null",
  "hospital": "医院/机构名称或null",
  "doctor": "医生姓名或null",
  "report_type": "血检/体检/MRI/CT/X光/超声/骨密度/心电图/病理/其他",
  "body_part": "全身/腰椎/颈椎/胸椎/膝关节/髋关节/肩关节/头颅/胸部/腹部/血液/其他",
  "language": "zh或en",
  "findings": "检查所见/主要发现，完整提取",
  "conclusion": "诊断结论/印象",
  "recommendations": "建议/注意事项或null",
  "lab_values": [
    {"name": "项目名称", "value": "数值", "unit": "单位", "ref_range": "参考范围", "status": "normal/high/low/critical"}
  ]
}

重要：
- 尽量提取所有检验项目到lab_values数组，包括血常规、生化、尿检等
- status字段：在参考范围内为normal，高于为high，低于为low，严重异常为critical
- 影像报告如果没有检验数值，lab_values为空数组[]
- 如果报告包含体检总结和实验室检查，请提取所有数值
"""

// MARK: - Main extraction function

func extractReportFromFile(_ url: URL, provider: AIProvider, apiKey: String) async throws -> ExtractedReport {
    guard !apiKey.isEmpty else { throw AIError.noAPIKey }

    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }

    let ext = url.pathExtension.lowercased()

    switch provider {
    case .gemini:
        return try await extractWithGemini(url: url, ext: ext, apiKey: apiKey)
    case .deepseek:
        return try await extractWithDeepSeek(url: url, ext: ext, apiKey: apiKey)
    }
}

// MARK: - Gemini

private func extractWithGemini(url: URL, ext: String, apiKey: String) async throws -> ExtractedReport {
    let fileData = try Data(contentsOf: url)
    let base64 = fileData.base64EncodedString()

    let mimeType: String
    if ext == "pdf" {
        mimeType = "application/pdf"
    } else {
        switch ext {
        case "png": mimeType = "image/png"
        case "gif": mimeType = "image/gif"
        case "webp": mimeType = "image/webp"
        default: mimeType = "image/jpeg"
        }
    }

    let body: [String: Any] = [
        "contents": [[
            "parts": [
                ["inlineData": ["mimeType": mimeType, "data": base64]],
                ["text": extractionPrompt]
            ]
        ]]
    ]

    let model = AIProvider.gemini.modelName
    let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
    var req = URLRequest(url: URL(string: endpoint)!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }

    if http.statusCode != 200 {
        let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errMsg = (errJson?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
        throw AIError.apiError("Gemini: \(errMsg)")
    }

    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let candidates = json["candidates"] as? [[String: Any]],
        let content = candidates.first?["content"] as? [String: Any],
        let parts = content["parts"] as? [[String: Any]],
        let text = parts.first?["text"] as? String
    else { throw AIError.parseError }

    return try parseAIResponse(text)
}

// MARK: - DeepSeek

private func extractWithDeepSeek(url: URL, ext: String, apiKey: String) async throws -> ExtractedReport {
    let textContent: String

    if ext == "pdf" {
        guard let pdfDoc = PDFDocument(url: url) else {
            throw AIError.unsupportedFormat("无法读取 PDF 文件")
        }
        var pages: [String] = []
        for i in 0..<pdfDoc.pageCount {
            if let page = pdfDoc.page(at: i), let pageText = page.string, !pageText.isEmpty {
                pages.append(pageText)
            }
        }
        textContent = pages.joined(separator: "\n---\n")
        if textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIError.unsupportedFormat("PDF 是扫描件，无法提取文字。请切换到 Gemini（支持图片识别）。")
        }
    } else {
        throw AIError.unsupportedFormat("DeepSeek 不支持图片识别。请切换到 Gemini 或上传 PDF 文件。")
    }

    let prompt = extractionPrompt + "\n\n以下是报告内容：\n\n" + textContent

    let body: [String: Any] = [
        "model": "deepseek-chat",
        "messages": [["role": "user", "content": prompt]],
        "max_tokens": 4096
    ]

    var req = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
    req.httpMethod = "POST"
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }

    if http.statusCode != 200 {
        let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errMsg = (errJson?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
        throw AIError.apiError("DeepSeek: \(errMsg)")
    }

    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let choices = json["choices"] as? [[String: Any]],
        let message = choices.first?["message"] as? [String: Any],
        let text = message["content"] as? String
    else { throw AIError.parseError }

    return try parseAIResponse(text)
}

// MARK: - Parse AI response

private func parseAIResponse(_ raw: String) throws -> ExtractedReport {
    var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.hasPrefix("```") {
        cleaned = cleaned.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard let jsonData = cleaned.data(using: .utf8),
          let result = try? JSONDecoder().decode(ExtractedReport.self, from: jsonData)
    else { throw AIError.parseError }

    return result
}

// MARK: - AI Summary generation

func generateReportSummary(report: MedicalReport, language: String, provider: AIProvider, apiKey: String, conditions: [String] = []) async throws -> String {
    guard !apiKey.isEmpty else { throw AIError.noAPIKey }

    let isEN = language == "en"
    let labValues = (report.labValues as? Set<LabValue>) ?? []
    var labText = ""
    for lv in labValues.sorted(by: { ($0.itemName ?? "") < ($1.itemName ?? "") }) {
        labText += "- \(lv.itemName ?? ""): \(lv.value ?? "") \(lv.unit ?? "") (ref:\(lv.refRange ?? "")) status:\(lv.status ?? "unknown")\n"
    }

    let condText = conditions.isEmpty ? "" : conditions.joined(separator: ", ")

    let prompt: String
    if isEN {
        prompt = """
        You are a professional medical consultant. Analyze the following medical report and provide a concise analysis. Do not introduce yourself or have any opening pleasantries — start directly with the analysis. ALL output must be in English, even if the source report is in another language. Translate any non-English content.
        \(condText.isEmpty ? "" : "\nIMPORTANT: The patient has these known conditions: \(condText). Pay special attention to any lab values or findings related to these conditions.\n")
        Report: \(report.title ?? "")
        Date: \(report.reportDate?.isoString ?? "Unknown")
        Type: \(report.reportType ?? "")
        Findings: \(report.findings ?? "None")
        Conclusion: \(report.conclusion ?? "None")
        Recommendations: \(report.recommendations ?? "None")

        Lab Values:
        \(labText.isEmpty ? "No lab values" : labText)

        Output in plain text (no markdown) using these sections:

        [Abnormal Indicators]
        List all abnormal (high/low/critical) indicators with brief clinical significance

        [Condition-Related Items]
        Highlight any lab values or findings relevant to the patient's known conditions\(condText.isEmpty ? " (none reported)" : "")

        [Items to Monitor]
        Which indicators need regular monitoring or further examination

        [Recommendations]
        Specific advice on lifestyle, diet, follow-up visits
        """
    } else {
        prompt = """
        你是专业医疗顾问。请分析以下检查报告，给出简明扼要的分析。不要有开场白或自我介绍，直接开始分析。所有输出必须用中文，即使原始报告是英文或其他语言，也请翻译为中文输出。
        \(condText.isEmpty ? "" : "\n重要：患者有以下已知病史：\(condText)。请特别注意与这些病史相关的检验指标和发现。\n")
        报告：\(report.title ?? "")
        日期：\(report.reportDate?.isoString ?? "未知")
        类型：\(report.reportType ?? "")
        检查发现：\(report.findings ?? "无")
        结论：\(report.conclusion ?? "无")
        建议：\(report.recommendations ?? "无")

        检验数值：
        \(labText.isEmpty ? "无检验数值" : labText)

        请按以下格式输出（纯文本，不要markdown）：

        【异常指标】
        列出所有异常（偏高/偏低/危险）的指标，简要说明临床意义

        【病史相关】
        标出与患者已知病史相关的检验指标\(condText.isEmpty ? "（无已知病史）" : "")，分析其临床意义

        【需要关注】
        哪些指标需要定期监测或进一步检查

        【建议】
        生活方式、饮食、随访等具体建议
        """
    }

    return try await callGeminiText(prompt: prompt, provider: provider, apiKey: apiKey)
}

func generateGlobalSummary(profile: Profile, reports: [MedicalReport], conditions: [Condition], language: String, provider: AIProvider, apiKey: String) async throws -> String {
    guard !apiKey.isEmpty else { throw AIError.noAPIKey }

    let isEN = language == "en"
    let sorted = reports.sorted { ($0.reportDate ?? .distantPast) > ($1.reportDate ?? .distantPast) }

    var reportsSummary = ""
    for (i, r) in sorted.prefix(5).enumerated() {
        reportsSummary += "\n[\(r.title ?? "")] \(r.reportDate?.isoString ?? "") \(r.reportType ?? "")"
        if i < 2, let c = r.conclusion, !c.isEmpty { reportsSummary += " | \(c)" }
        reportsSummary += "\n"
        let labValues = (r.labValues as? Set<LabValue>) ?? []
        let abnormal = labValues.filter { $0.status != "normal" && $0.status != nil }
            .sorted { ($0.status == "critical" ? 0 : 1) < ($1.status == "critical" ? 0 : 1) }
        let shown = abnormal.prefix(5)
        for lv in shown {
            reportsSummary += "  ⚠ \(lv.itemName ?? ""): \(lv.value ?? "") \(lv.unit ?? "") (\(lv.status ?? ""))\n"
        }
        if abnormal.count > 5 { reportsSummary += "  ... +\(abnormal.count - 5) more\n" }
    }

    let condText = conditions.map { "- \($0.name ?? "") [\($0.status ?? "")]" }.joined(separator: "\n")

    let prompt: String
    if isEN {
        prompt = """
        You are a health advisor. Analyze these health records and write a friendly, easy-to-understand summary. Do not introduce yourself or have any opening pleasantries — start directly with the summary. Explain medical terms in plain language. English output only.

        Patient: \(profile.name ?? ""), \(profile.gender ?? "Unknown"), Allergies: \(profile.allergies ?? "None")
        Conditions: \(condText.isEmpty ? "None" : condText)
        Reports (newest first):
        \(reportsSummary.isEmpty ? "None" : reportsSummary)

        Plain text output (no markdown). Write complete sentences, do not cut off mid-thought:

        [Overall Health Assessment]
        How is the patient doing overall? Summarize in 2-3 sentences a non-medical person can understand.

        [What Needs Attention]
        Which abnormal results matter most? Explain what each means for the patient's health in plain language.

        [Changes Over Time]
        Are things getting better or worse? Which numbers are trending in the wrong direction?

        [What You Can Do]
        Practical lifestyle advice: specific foods to eat/avoid, exercise suggestions, when to see a doctor next.
        """
    } else {
        prompt = """
        你是健康顾问，为患者撰写通俗易懂的健康摘要。不要有开场白或自我介绍，直接开始分析。用口语化中文，解释医学术语。

        患者：\(profile.name ?? "")，\(profile.gender ?? "未知")，过敏：\(profile.allergies ?? "无")
        病史：\(condText.isEmpty ? "无" : condText)
        报告（时间倒序）：
        \(reportsSummary.isEmpty ? "无" : reportsSummary)

        纯文本输出（不要markdown），写完整句子，不要中途截断：

        【整体健康评估】
        用2-3句话概括整体健康状况，让没有医学背景的人也能看懂。

        【需要关注的问题】
        哪些异常指标最重要？用通俗的语言解释每个异常对健康意味着什么。

        【变化趋势】
        哪些指标在好转？哪些在恶化？和上次比有什么变化？

        【生活建议】
        具体的饮食建议（吃什么、忌什么）、运动建议、下次复查时间。
        """
    }

    return try await callGeminiText(prompt: prompt, provider: provider, apiKey: apiKey)
}

func generateDoctorSummary(profile: Profile, reports: [MedicalReport], conditions: [Condition], language: String, provider: AIProvider, apiKey: String) async throws -> String {
    guard !apiKey.isEmpty else { throw AIError.noAPIKey }

    let isEN = language == "en"
    let sorted = reports.sorted { ($0.reportDate ?? .distantPast) > ($1.reportDate ?? .distantPast) }

    // Build comprehensive lab data for doctor: include ALL abnormals + key normals relevant to conditions
    var labDigest = ""
    for r in sorted.prefix(3) {
        let labValues = (r.labValues as? Set<LabValue>) ?? []
        let abnormal = labValues.filter { $0.status != "normal" && $0.status != nil }
        if abnormal.isEmpty && (r.conclusion ?? "").isEmpty { continue }
        labDigest += "\n\(r.reportDate?.isoString ?? "") [\(r.reportType ?? "")]"
        if let c = r.conclusion, !c.isEmpty { labDigest += " \(c)" }
        labDigest += "\n"
        for lv in abnormal.sorted(by: { ($0.itemName ?? "") < ($1.itemName ?? "") }) {
            labDigest += "  \(lv.itemName ?? ""): \(lv.value ?? "") \(lv.unit ?? "") (ref:\(lv.refRange ?? "")) [\(lv.status ?? "")]\n"
        }
    }

    let condList = conditions.map {
        var s = "• \($0.name ?? "") [\($0.status ?? "")]"
        if let sev = $0.severity, !sev.isEmpty { s += ", severity: \(sev)" }
        if let onset = $0.dateOnset { s += ", onset: \(onset.isoString)" }
        if let r = $0.restrictions, !r.isEmpty { s += ", restrictions: \(r)" }
        if let n = $0.notes, !n.isEmpty { s += ", notes: \(n)" }
        return s
    }.joined(separator: "\n")

    let ageStr: String
    if let bd = profile.birthDate {
        let years = Calendar.current.dateComponents([.year], from: bd, to: Date()).year ?? 0
        ageStr = "\(years)"
    } else { ageStr = isEN ? "Unknown" : "未知" }

    let prompt: String
    if isEN {
        prompt = """
        Generate a clinical summary in SOAP-note style for physician handoff. Use medical terminology. English only. Write complete thoughts.

        Demographics: \(profile.name ?? ""), \(ageStr)y/o \(profile.gender ?? ""), Allergies: \(profile.allergies ?? "None reported")
        PMH: \(condList.isEmpty ? "None documented" : condList)
        Recent investigations:
        \(labDigest.isEmpty ? "No recent labs" : labDigest)

        Plain text output (no markdown):

        [Chief Complaint / Reason for Summary]
        One-line summary of why this patient needs attention based on active conditions and recent findings.

        [Active Problem List]
        For EACH active condition:
        - Condition name, duration, current status
        - Relevant lab values with reference ranges and trend (improving/stable/worsening)
        - Current management gaps if any

        [Significant Lab Abnormalities]
        Table-style listing: Test | Value | Reference | Clinical significance
        Flag any values requiring urgent attention.

        [Clinical Assessment]
        Synthesize findings across conditions. Note interactions between conditions (e.g., uric acid impact on kidney function).

        [Recommended Actions]
        - Specific tests to order and timeline
        - Specialist referrals if indicated
        - Medication considerations
        - Follow-up interval recommendation

        Footer: "AI-generated clinical summary — not a substitute for clinical evaluation."
        """
    } else {
        prompt = """
        生成SOAP格式的临床摘要，供医生交接参考。使用专业医学术语。中文输出。写完整句子。

        基本信息：\(profile.name ?? "")，\(ageStr)岁，\(profile.gender ?? "")，过敏史：\(profile.allergies ?? "无")
        既往史：\(condList.isEmpty ? "无记录" : condList)
        近期检查：
        \(labDigest.isEmpty ? "无近期化验" : labDigest)

        纯文本输出（不要markdown）：

        【主诉/摘要原因】
        一句话概括该患者需要关注的核心问题。

        【活动问题清单】
        逐条列出每个活动病症：
        - 诊断名称、病程、当前状态
        - 相关化验值（含参考范围）及趋势（好转/稳定/恶化）
        - 当前管理中的不足

        【重要异常化验】
        逐项列出：检验项目 | 数值 | 参考范围 | 临床意义
        标注需要紧急处理的数值。

        【临床评估】
        综合分析各病症间的关联（如高尿酸对肾功能的影响），评估整体风险。

        【建议处置】
        - 需要开具的检查及时间安排
        - 是否需要专科转诊
        - 用药方面的考虑
        - 建议复诊间隔

        末尾注明："本摘要由 AI 自动生成，仅供临床参考，不替代医生诊断。"
        """
    }

    return try await callGeminiText(prompt: prompt, provider: provider, apiKey: apiKey)
}

func callGeminiText(prompt: String, provider: AIProvider, apiKey: String) async throws -> String {
    if provider == .gemini {
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]]
        ]
        let model = AIProvider.gemini.modelName
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        if http.statusCode != 200 {
            let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errMsg = (errJson?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw AIError.apiError("Gemini: \(errMsg)")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else { throw AIError.parseError }
        return text
    } else {
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 4096
        ]
        var req = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        if http.statusCode != 200 {
            let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errMsg = (errJson?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw AIError.apiError("DeepSeek: \(errMsg)")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let text = message["content"] as? String
        else { throw AIError.parseError }
        return text
    }
}

