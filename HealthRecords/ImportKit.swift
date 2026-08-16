import SwiftUI
import CoreData
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Page merging
//
// A report can arrive as several photos. Rather than adding an attachments
// entity (a Core Data migration on a store holding real medical records), the
// pages are combined into one PDF — which QuickLook already pages through.

/// Combines images and PDFs into a single PDF. Returns the original URL
/// untouched when there is only one file.
func mergeIntoSinglePDF(_ urls: [URL], named baseName: String) -> URL? {
    guard !urls.isEmpty else { return nil }
    if urls.count == 1 { return urls[0] }

    let merged = PDFDocument()
    var pageIndex = 0

    for url in urls {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) {
                    merged.insert(page, at: pageIndex)
                    pageIndex += 1
                }
            }
        } else if let image = UIImage(contentsOfFile: url.path),
                  let page = PDFPage(image: image) {
            merged.insert(page, at: pageIndex)
            pageIndex += 1
        }
    }

    guard pageIndex > 0 else { return urls.first }

    let safeName = baseName.replacingOccurrences(of: "/", with: "-")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = dir.appendingPathComponent("\(safeName).pdf")
    guard merged.write(to: dest) else { return urls.first }
    return dest
}

// MARK: - Diagnoses → conditions
//
// A visit summary that says "seafood allergy" should leave a condition behind,
// not just a paragraph of findings the user has to re-read. Chronic diagnoses
// stay open; time-limited ones carry the date they are expected to have cleared.

struct ConditionImportResult {
    var created: [String] = []
    var skippedExisting: [String] = []
    var isEmpty: Bool { created.isEmpty && skippedExisting.isEmpty }
}

@discardableResult
func importConditions(_ items: [ExtractedCondition],
                      into profile: Profile,
                      ctx: NSManagedObjectContext,
                      reportDate: Date?,
                      hospital: String?,
                      doctor: String?) -> ConditionImportResult {
    var result = ConditionImportResult()
    guard !items.isEmpty else { return result }

    let existing = (profile.conditions as? Set<Condition>) ?? []
    var seenKeys = Set(existing.compactMap { conditionKey($0.name) })

    for item in items {
        let name = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let key = conditionKey(name) else { continue }

        // Re-importing the same visit summary shouldn't duplicate the diagnosis.
        guard !seenKeys.contains(key) else {
            result.skippedExisting.append(name)
            continue
        }
        seenKeys.insert(key)

        let c = Condition(context: ctx)
        c.id = UUID()
        c.createdAt = Date()
        c.profile = profile
        c.name = name
        c.category = item.category?.nilIfBlank
        c.severity = item.severity?.nilIfBlank
        c.restrictions = item.restrictions?.nilIfBlank
        c.hospital = hospital?.nilIfBlank
        c.doctor = doctor?.nilIfBlank
        c.dateOnset = item.date_onset?.isoDate ?? reportDate

        if let end = item.expected_end?.isoDate, !item.isChronic {
            // Time-limited with a stated end: watched until that date.
            c.dateResolved = end
            c.status = end < Date() ? "resolved" : "monitoring"
        } else if item.isChronic {
            // Lifelong: stays open, no end date.
            c.status = "active"
            c.dateResolved = nil
        } else {
            // Called temporary but with no end date the model could name — a
            // vitamin D deficiency shouldn't get a fabricated recovery date.
            // Keep it open and merely watched.
            c.status = "monitoring"
            c.dateResolved = nil
        }

        var noteParts: [String] = []
        if let n = item.notes?.nilIfBlank { noteParts.append(n) }
        noteParts.append(currentLang() == "en" ? "Added from an imported report."
                                               : "由导入的报告自动记录。")
        c.notes = noteParts.joined(separator: "\n")

        result.created.append(name)
    }

    return result
}

private func conditionKey(_ name: String?) -> String? {
    guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !n.isEmpty else { return nil }
    return n.replacingOccurrences(of: " ", with: "")
}

extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Draft produced by an import

/// One report the model found, before the user has agreed to save it.
struct ReportDraft: Identifiable {
    let id = UUID()
    var include: Bool = true
    var extracted: ExtractedReport
    /// The picked files this draft was built from, in upload order.
    var sourceURLs: [URL]

    var displayTitle: String {
        extracted.title?.nilIfBlank ?? (currentLang() == "en" ? "Untitled report" : "未命名报告")
    }
    var labCount: Int { extracted.lab_values?.count ?? 0 }
    var abnormalCount: Int {
        (extracted.lab_values ?? []).filter { ($0.status ?? "") != "normal" && !($0.status ?? "").isEmpty }.count
    }
    var conditions: [ExtractedCondition] { extracted.conditions ?? [] }
    var date: Date? { extracted.report_date?.isoDate }
}

/// Writes a draft into Core Data, merging its pages into one attachment and
/// turning any diagnoses into conditions.
@discardableResult
func saveDraft(_ draft: ReportDraft, to profile: Profile, ctx: NSManagedObjectContext) -> ConditionImportResult {
    let e = draft.extracted

    let r = MedicalReport(context: ctx)
    r.id = UUID()
    r.createdAt = Date()
    r.profile = profile
    r.title = draft.displayTitle
    r.reportDate = e.report_date?.isoDate
    r.reportType = e.report_type?.nilIfBlank
    r.bodyPart = e.body_part?.nilIfBlank
    r.language = e.language?.nilIfBlank ?? "zh"
    r.hospital = e.hospital?.nilIfBlank
    r.doctor = e.doctor?.nilIfBlank
    r.findings = e.findings?.nilIfBlank
    r.conclusion = e.conclusion?.nilIfBlank
    r.recommendations = e.recommendations?.nilIfBlank

    if let source = mergeIntoSinglePDF(draft.sourceURLs, named: draft.displayTitle) {
        let destName = UUID().uuidString + "_" + source.lastPathComponent
        let destURL = PersistenceController.uploadsURL.appendingPathComponent(destName)
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        if (try? FileManager.default.copyItem(at: source, to: destURL)) != nil {
            r.filePath = destName
            r.fileName = source.lastPathComponent
        }
    }

    for lv in e.lab_values ?? [] {
        guard let name = lv.name?.nilIfBlank else { continue }
        let value = LabValue(context: ctx)
        value.id = UUID()
        value.itemName = name
        value.value = lv.value?.nilIfBlank
        value.unit = lv.unit?.nilIfBlank
        value.refRange = lv.ref_range?.nilIfBlank
        value.status = lv.status?.nilIfBlank
        value.report = r
    }

    return importConditions(draft.conditions, into: profile, ctx: ctx,
                            reportDate: r.reportDate, hospital: r.hospital, doctor: r.doctor)
}

// MARK: - Multi-select pickers

struct MultiPhotoPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0          // 0 = unlimited
        config.selection = .ordered        // page order is the order they tapped
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            // Load in parallel but hand back in the order the user selected.
            var loaded = [Int: URL]()
            let group = DispatchGroup()
            let lock = NSLock()

            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                let typeId = provider.registeredTypeIdentifiers.first {
                    UTType($0)?.conforms(to: .image) == true
                } ?? UTType.image.identifier

                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, _ in
                    defer { group.leave() }
                    guard let url else { return }
                    let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                    let name = provider.suggestedName ?? "page\(index + 1)"
                    let dir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let dest = dir.appendingPathComponent("\(name).\(ext)")
                    try? FileManager.default.copyItem(at: url, to: dest)
                    lock.lock(); loaded[index] = dest; lock.unlock()
                }
            }

            group.notify(queue: .main) {
                let ordered = loaded.keys.sorted().compactMap { loaded[$0] }
                self.onPick(ordered)
            }
        }
    }
}

struct MultiDocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
