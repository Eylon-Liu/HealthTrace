import SwiftUI
import CoreData

struct ProfilesView: View {
    @Environment(\.managedObjectContext) var ctx
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var pm: ProfileManager

    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) var profiles: FetchedResults<Profile>
    @Binding var showAddNew: Bool
    @State private var editTarget: Profile?

    var body: some View {
        NavigationView {
            List {
                ForEach(profiles, id: \.id) { p in
                    Button {
                        pm.select(p)
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            AvatarView(letter: String(p.name?.prefix(1) ?? "?"),
                                       color: Color(hex: p.avatarColor ?? "#2563EB"),
                                       size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name ?? "").font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                                let info = [
                                    p.birthDate.map { ageString(from: $0) },
                                    p.gender,
                                    p.bloodType
                                ].compactMap { $0 }.joined(separator: " · ")
                                if !info.isEmpty {
                                    Text(info).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if pm.currentProfile?.id == p.id {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                            }
                            Button { editTarget = p } label: {
                                Image(systemName: "pencil").foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { offsets in
                    for i in offsets {
                        let p = profiles[i]
                        if pm.currentProfile?.id == p.id { pm.currentProfile = nil }
                        ctx.delete(p)
                    }
                    try? ctx.save()
                }

                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showAddNew = true }
                } label: {
                    Label("添加家庭成员", systemImage: "plus.circle.fill").foregroundColor(.blue)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("切换档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() } } }
            .sheet(item: $editTarget) { p in AddProfileView(profile: p) }
        }
    }
}

struct AddProfileView: View {
    @Environment(\.managedObjectContext) var ctx
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var pm: ProfileManager

    var profile: Profile?

    @State private var name = ""
    @State private var hasDate = false
    @State private var birthDate = Date()
    @State private var gender = ""
    @State private var bloodType = ""
    @State private var allergies = ""
    @State private var notes = ""

    var body: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    LabeledTextField("姓名 *", text: $name, placeholder: "例：我自己、妈妈、老公")

                    Toggle("填写出生日期", isOn: $hasDate)
                    if hasDate {
                        DatePicker("出生日期", selection: $birthDate, displayedComponents: .date)
                    }

                    Picker("性别", selection: $gender) {
                        Text("不填").tag("")
                        Text("女").tag("女")
                        Text("男").tag("男")
                    }

                    Picker("血型", selection: $bloodType) {
                        Text("不填").tag("")
                        ForEach(["A+","A-","B+","B-","AB+","AB-","O+","O-"], id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("其他") {
                    LabeledTextField("过敏史", text: $allergies, placeholder: "例：青霉素、海鲜")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("备注").font(.caption).foregroundColor(.secondary)
                        TextEditor(text: $notes).frame(minHeight: 60)
                    }
                }
            }
            .navigationTitle(profile == nil ? "添加家庭成员" : "编辑档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }.disabled(name.isEmpty).fontWeight(.semibold)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        guard let p = profile else { return }
        name = p.name ?? ""
        gender = p.gender ?? ""
        bloodType = p.bloodType ?? ""
        allergies = p.allergies ?? ""
        notes = p.notes ?? ""
        if let bd = p.birthDate { birthDate = bd; hasDate = true }
    }

    private func save() {
        let p = profile ?? Profile(context: ctx)
        if profile == nil {
            p.id = UUID()
            p.createdAt = Date()
            // Auto-assign an avatar color that rotates through the palette so family members differ.
            let count = (try? ctx.count(for: NSFetchRequest<Profile>(entityName: "Profile"))) ?? 0
            p.avatarColor = avatarColors[count % avatarColors.count].hex
        }
        p.name = name
        p.gender = gender.isEmpty ? nil : gender
        p.bloodType = bloodType.isEmpty ? nil : bloodType
        p.allergies = allergies.isEmpty ? nil : allergies
        p.notes = notes.isEmpty ? nil : notes
        p.birthDate = hasDate ? birthDate : nil
        try? ctx.save()
        if profile == nil { pm.select(p) }
        dismiss()
    }
}
