import SwiftUI

struct ConditionsView: View {
    @Environment(\.managedObjectContext) var ctx
    @EnvironmentObject var pm: ProfileManager
    @AppStorage("summaryLanguage") private var lang = "zh"

    @FetchRequest(sortDescriptors: [SortDescriptor(\.dateOnset, order: .reverse),
                                    SortDescriptor(\.createdAt, order: .reverse)])
    private var allConditions: FetchedResults<Condition>

    @State private var filter = "active"
    @State private var showAdd = false
    @State private var editTarget: Condition?

    private var conditions: [Condition] {
        guard let p = pm.currentProfile else { return [] }
        return allConditions.filter { c in
            c.profile == p && (filter == "all" || c.status == filter)
        }
    }

    var body: some View {
        Group {
            if pm.currentProfile == nil {
                EmptyStateView(icon: "heart", message: lang == "en" ? "Please select a profile" : "请先选择档案")
            } else {
                VStack(spacing: 0) {
                    Picker("", selection: $filter) {
                        Text(lang == "en" ? "Active" : "活跃中").tag("active")
                        Text(lang == "en" ? "Monitoring" : "观察中").tag("monitoring")
                        Text(lang == "en" ? "Resolved" : "已解决").tag("resolved")
                        Text(lang == "en" ? "All" : "全部").tag("all")
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    if conditions.isEmpty {
                        EmptyStateView(icon: "heart", message: lang == "en" ? "No records yet\nTap + to add" : "暂无记录\n点击右上角 + 添加")
                    } else {
                        List {
                            ForEach(conditions, id: \.id) { c in
                                ConditionRowView(condition: c)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editTarget = c }
                            }
                            .onDelete { offsets in
                                for i in offsets { ctx.delete(conditions[i]) }
                                try? ctx.save()
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
        }
        .navigationTitle(L("病史记录", lang))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddConditionView(profile: pm.currentProfile)
        }
        .sheet(item: $editTarget) { c in
            AddConditionView(condition: c)
        }
    }
}

struct ConditionRowView: View {
    let condition: Condition
    @AppStorage("summaryLanguage") private var lang = "zh"

    private var sevLabel: String {
        switch condition.severity {
        case "mild": return lang == "en" ? "Mild" : "轻度"
        case "moderate": return lang == "en" ? "Moderate" : "中度"
        case "severe": return lang == "en" ? "Severe" : "重度"
        default: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Rectangle()
                    .fill(statusColor(condition.status))
                    .frame(width: 4)
                    .cornerRadius(2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(condition.name ?? "").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(statusLabel(condition.status, language: lang))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(statusColor(condition.status))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(statusColor(condition.status).opacity(0.12))
                            .cornerRadius(4)
                    }

                    HStack(spacing: 6) {
                        if let cat = condition.category, !cat.isEmpty {
                            Text(cat)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .cornerRadius(4)
                        }
                        if !sevLabel.isEmpty {
                            Text(sevLabel)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .cornerRadius(4)
                        }
                    }

                    let meta = [
                        condition.dateOnset.map { "\(lang == "en" ? "Onset" : "开始"): \($0.isoString)" },
                        condition.dateResolved.map { "\(lang == "en" ? "Resolved" : "结束"): \($0.isoString)" },
                        condition.hospital,
                        condition.doctor
                    ].compactMap { $0 }.joined(separator: " · ")
                    if !meta.isEmpty {
                        Text(meta).font(.caption).foregroundColor(.secondary)
                    }

                    if let r = condition.restrictions, !r.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(r).font(.caption)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(6)
                    }

                    if let n = condition.notes, !n.isEmpty {
                        Text(n).font(.caption).foregroundColor(.secondary).lineLimit(3)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
