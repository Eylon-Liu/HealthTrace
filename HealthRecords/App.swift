import SwiftUI

@main
struct HealthRecordsApp: App {
    let persistence = PersistenceController.shared
    @StateObject private var pm = ProfileManager()
    @State private var importResult: ImportResult?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(pm)
                .onOpenURL { url in
                    handleIncomingFile(url)
                }
                .alert(item: $importResult) { result in
                    Alert(
                        title: Text(result.title),
                        message: Text(result.message),
                        dismissButton: .default(Text("好的")) {
                            if let profile = result.profile {
                                pm.select(profile)
                            }
                        }
                    )
                }
        }
    }

    private func handleIncomingFile(_ url: URL) {
        guard url.pathExtension == "healthrecord" || url.pathExtension == "json" else { return }
        do {
            let profile = try ProfileExporter.importProfile(
                from: url, context: persistence.container.viewContext)
            importResult = ImportResult(
                title: "导入成功",
                message: "已导入「\(profile.name ?? "")」的健康档案，包含 \(profile.reports?.count ?? 0) 份报告和 \(profile.conditions?.count ?? 0) 条病史记录。",
                profile: profile
            )
        } catch {
            importResult = ImportResult(
                title: "导入失败",
                message: "文件格式无效：\(error.localizedDescription)"
            )
        }
    }
}

struct ImportResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var profile: Profile?
}
