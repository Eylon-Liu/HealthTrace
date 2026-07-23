import Foundation
import CoreData
import SwiftUI

struct ProfileExportData: Codable {
    var version: Int = 1
    var exportDate: Date
    var profile: ProfileData
    var conditions: [ConditionData]
    var reports: [ReportData]
    var favoriteLabItems: [String]
}

struct ProfileData: Codable {
    var name: String
    var birthDate: Date?
    var gender: String?
    var bloodType: String?
    var avatarColor: String?
    var allergies: String?
    var notes: String?
}

struct ConditionData: Codable {
    var name: String
    var status: String?
    var category: String?
    var severity: String?
    var dateOnset: Date?
    var dateResolved: Date?
    var hospital: String?
    var doctor: String?
    var notes: String?
    var restrictions: String?
}

struct ReportData: Codable {
    var title: String?
    var reportType: String?
    var bodyPart: String?
    var reportDate: Date?
    var hospital: String?
    var doctor: String?
    var language: String?
    var findings: String?
    var conclusion: String?
    var recommendations: String?
    var notes: String?
    var aiSummary: String?
    var labValues: [LabValueData]
}

struct LabValueData: Codable {
    var itemName: String
    var value: String?
    var unit: String?
    var status: String?
    var refRange: String?
}

enum ProfileExporter {

    static func export(profile: Profile) throws -> Data {
        let data = ProfileExportData(
            exportDate: Date(),
            profile: ProfileData(
                name: profile.name ?? "",
                birthDate: profile.birthDate,
                gender: profile.gender,
                bloodType: profile.bloodType,
                avatarColor: profile.avatarColor,
                allergies: profile.allergies,
                notes: profile.notes
            ),
            conditions: ((profile.conditions as? Set<Condition>) ?? []).map { c in
                ConditionData(
                    name: c.name ?? "",
                    status: c.status,
                    category: c.category,
                    severity: c.severity,
                    dateOnset: c.dateOnset,
                    dateResolved: c.dateResolved,
                    hospital: c.hospital,
                    doctor: c.doctor,
                    notes: c.notes,
                    restrictions: c.restrictions
                )
            },
            reports: ((profile.reports as? Set<MedicalReport>) ?? [])
                .sorted { ($0.reportDate ?? .distantPast) > ($1.reportDate ?? .distantPast) }
                .map { r in
                    let lvs = ((r.labValues as? Set<LabValue>) ?? []).map { lv in
                        LabValueData(
                            itemName: lv.itemName ?? "",
                            value: lv.value,
                            unit: lv.unit,
                            status: lv.status,
                            refRange: lv.refRange
                        )
                    }
                    return ReportData(
                        title: r.title,
                        reportType: r.reportType,
                        bodyPart: r.bodyPart,
                        reportDate: r.reportDate,
                        hospital: r.hospital,
                        doctor: r.doctor,
                        language: r.language,
                        findings: r.findings,
                        conclusion: r.conclusion,
                        recommendations: r.recommendations,
                        notes: r.notes,
                        aiSummary: r.aiSummary,
                        labValues: lvs
                    )
                },
            favoriteLabItems: ((profile.favoriteLabItems as? Set<FavoriteLabItem>) ?? []).compactMap { $0.itemName }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }

    static func exportToFile(profile: Profile) throws -> URL {
        let data = try export(profile: profile)
        let name = (profile.name ?? "档案").replacingOccurrences(of: " ", with: "_")
        let fileName = "\(name)_健康档案.healthrecord"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url)
        return url
    }

    @discardableResult
    static func importProfile(from url: URL, context: NSManagedObjectContext) throws -> Profile {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(ProfileExportData.self, from: data)

        let profile = Profile(context: context)
        profile.id = UUID()
        profile.name = export.profile.name
        profile.birthDate = export.profile.birthDate
        profile.gender = export.profile.gender
        profile.bloodType = export.profile.bloodType
        profile.avatarColor = export.profile.avatarColor
        profile.allergies = export.profile.allergies
        profile.notes = export.profile.notes
        profile.createdAt = Date()

        for c in export.conditions {
            let cond = Condition(context: context)
            cond.id = UUID()
            cond.name = c.name
            cond.status = c.status
            cond.category = c.category
            cond.severity = c.severity
            cond.dateOnset = c.dateOnset
            cond.dateResolved = c.dateResolved
            cond.hospital = c.hospital
            cond.doctor = c.doctor
            cond.notes = c.notes
            cond.restrictions = c.restrictions
            cond.createdAt = Date()
            cond.profile = profile
        }

        for r in export.reports {
            let report = MedicalReport(context: context)
            report.id = UUID()
            report.title = r.title
            report.reportType = r.reportType
            report.bodyPart = r.bodyPart
            report.reportDate = r.reportDate
            report.hospital = r.hospital
            report.doctor = r.doctor
            report.language = r.language
            report.findings = r.findings
            report.conclusion = r.conclusion
            report.recommendations = r.recommendations
            report.notes = r.notes
            report.aiSummary = r.aiSummary
            report.createdAt = Date()
            report.profile = profile

            for lv in r.labValues {
                let labValue = LabValue(context: context)
                labValue.id = UUID()
                labValue.itemName = lv.itemName
                labValue.value = lv.value
                labValue.unit = lv.unit
                labValue.status = lv.status
                labValue.refRange = lv.refRange
                labValue.report = report
            }
        }

        for itemName in export.favoriteLabItems {
            let fav = FavoriteLabItem(context: context)
            fav.id = UUID()
            fav.itemName = itemName
            fav.createdAt = Date()
            fav.profile = profile
        }

        try context.save()
        return profile
    }
}
