import SwiftUI
import UniformTypeIdentifiers

struct MoreView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var lang = "zh"

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ConditionsView()
                } label: {
                    Label(L("病史记录", lang), systemImage: "heart.fill")
                        .foregroundColor(.red)
                }
                NavigationLink {
                    SummaryView()
                } label: {
                    Label(L("病历摘要", lang), systemImage: "list.clipboard.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("更多", lang))
    }
}

extension UTType {
    static let healthRecord = UTType(exportedAs: "com.personal.healthrecord")
}
