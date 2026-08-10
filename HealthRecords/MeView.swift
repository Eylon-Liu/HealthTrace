import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// The "Me" tab: who the records belong to, everything filed under them, and settings.
/// Replaces a More tab that held only two rows and made Settings a separate toolbar icon.
struct MeView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var lang = "zh"

    @State private var showEditProfile = false
    @State private var showProfiles = false
    @State private var showAddProfile = false
    @State private var labCount = 0
    @State private var abnormalCount = 0

    private var reportCount: Int { (pm.currentProfile?.reports as? Set<MedicalReport>)?.count ?? 0 }
    private var conditionCount: Int { (pm.currentProfile?.conditions as? Set<Condition>)?.count ?? 0 }

    var body: some View {
        List {
            Section { profileHeader.listRowInsets(EdgeInsets()) }

            // The other tabs carry the profile switcher in their navigation bar;
            // here the header card already shows who is selected, so switching
            // gets an explicit row instead of a second chip.
            Section {
                Button { showProfiles = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text(T("切换档案", "Switch Profile", lang)).foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Section(T("健康记录", "Health Records", lang)) {
                row(icon: "heart.fill", color: .red,
                    title: T("病史记录", "Conditions", lang),
                    detail: conditionCount > 0 ? "\(conditionCount)" : nil) { ConditionsView() }

                row(icon: "list.clipboard.fill", color: .blue,
                    title: T("病历摘要", "Medical Summary", lang)) { SummaryView() }

                row(icon: "chart.line.uptrend.xyaxis", color: .green,
                    title: T("全部检验指标", "All Lab Tests", lang),
                    detail: labCount > 0 ? "\(labCount)" : nil) { AllLabItemsView() }

                row(icon: "exclamationmark.triangle.fill", color: .orange,
                    title: T("异常指标", "Abnormal Indicators", lang),
                    detail: abnormalCount > 0 ? "\(abnormalCount)" : nil) { AbnormalDetailView() }
            }

            Section {
                row(icon: "gearshape.fill", color: .gray,
                    title: T("设置", "Settings", lang)) { SettingsView() }
            } footer: {
                HStack {
                    Spacer()
                    Text("HealthTrace \(appVersionString)")
                        .font(.caption2).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 12)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(T("我的", "Me", lang))
        .sheet(isPresented: $showEditProfile) {
            if let p = pm.currentProfile { AddProfileView(profile: p) }
        }
        .sheet(isPresented: $showProfiles) {
            ProfilesView(showAddNew: $showAddProfile)
        }
        .sheet(isPresented: $showAddProfile) {
            AddProfileView()
        }
        .onAppear { loadCounts() }
        .onChange(of: pm.currentProfile) { _ in loadCounts() }
    }

    // MARK: - Header

    private var profileHeader: some View {
        Group {
            if let p = pm.currentProfile {
                Button { showEditProfile = true } label: {
                    VStack(spacing: 14) {
                        HStack(spacing: 14) {
                            AvatarView(letter: String(p.name?.prefix(1) ?? "?"),
                                       color: Color(hex: p.avatarColor ?? "#2563EB"), size: 52)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name ?? "").font(.title3.bold()).foregroundColor(.primary)
                                let meta = [p.birthDate.map { ageString(from: $0) }, p.gender, p.bloodType]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                                Text(meta.isEmpty ? T("点击完善资料", "Tap to complete profile", lang) : meta)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }

                        HStack(spacing: 0) {
                            statPill(reportCount, T("报告", "Reports", lang))
                            Divider().frame(height: 26)
                            statPill(conditionCount, T("病史", "Conditions", lang))
                            Divider().frame(height: 26)
                            statPill(labCount, T("指标", "Labs", lang))
                        }
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)
            } else {
                Text(T("请先选择或创建档案", "Select or create a profile", lang))
                    .font(.subheadline).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(24)
            }
        }
    }

    private func statPill(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row<Destination: View>(icon: String, color: Color, title: String,
                                        detail: String? = nil,
                                        @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                Spacer()
                if let detail {
                    Text(detail).font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
    }

    private func loadCounts() {
        guard let p = pm.currentProfile else { labCount = 0; abnormalCount = 0; return }
        let items = lastTestedLabValues(for: p, in: ctx)
        labCount = items.count
        abnormalCount = items.filter { $0.isAbnormal }.count
    }
}

// MARK: - App version

/// Read from the bundle so the About row can never drift from what was actually shipped.
var appVersionString: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "—"
    let build = info?["CFBundleVersion"] as? String ?? "—"
    return "v\(short) (\(build))"
}

extension UTType {
    static let healthRecord = UTType(exportedAs: "com.personal.healthrecord")
}
