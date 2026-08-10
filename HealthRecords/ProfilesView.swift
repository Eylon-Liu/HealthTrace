import SwiftUI
import CoreData

struct ProfilesView: View {
    @Environment(\.managedObjectContext) var ctx
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var pm: ProfileManager

    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) var profiles: FetchedResults<Profile>
    @Binding var showAddNew: Bool
    @State private var editTarget: Profile?
    @AppStorage("summaryLanguage") private var lang = "zh"

    var body: some View {
        NavigationView {
            List {
                // Edit and delete live in swipe actions. The pencil used to be a
                // Button nested inside the row's Button, so tapping it could switch
                // profiles instead of opening the editor.
                ForEach(profiles, id: \.objectID) { p in
                    HStack(spacing: 14) {
                        AvatarView(letter: String(p.name?.prefix(1) ?? "?"),
                                   color: Color(hex: p.avatarColor ?? "#2563EB"),
                                   size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name ?? "").font(.subheadline.weight(.semibold))
                            let info = [p.birthDate.map { ageString(from: $0) }, p.gender, p.bloodType]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                            if !info.isEmpty {
                                Text(info).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if pm.currentProfile?.objectID == p.objectID {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { pm.select(p); dismiss() }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(p) } label: {
                            Label(T("删除", "Delete", lang), systemImage: "trash")
                        }
                        Button { editTarget = p } label: {
                            Label(T("编辑", "Edit", lang), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }

                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showAddNew = true }
                } label: {
                    Label(T("添加家庭成员", "Add family member", lang), systemImage: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(T("切换档案", "Switch Profile", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(T("关闭", "Close", lang)) { dismiss() }
                }
            }
            .sheet(item: $editTarget) { p in AddProfileView(profile: p) }
        }
    }

    /// Also removes the profile's attachments and cached AI text, which used to
    /// stay on disk forever after the records they described were gone.
    private func delete(_ p: Profile) {
        for r in (p.reports as? Set<MedicalReport>) ?? [] {
            guard let path = r.filePath else { continue }
            try? FileManager.default.removeItem(
                at: PersistenceController.uploadsURL.appendingPathComponent(path))
        }
        if let id = p.id?.uuidString {
            AICache.clear("aiGlobalSummary_\(id)")
            AICache.clear("aiDoctorSummary_\(id)")
            AICache.clear("aiAbnormalExplanation_\(id)")
        }
        if pm.currentProfile?.objectID == p.objectID { pm.currentProfile = nil }
        ctx.delete(p)
        try? ctx.save()
    }
}

struct AddProfileView: View {
    @Environment(\.managedObjectContext) var ctx
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var pm: ProfileManager

    var profile: Profile?

    @AppStorage("summaryLanguage") private var lang = "zh"
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
                Section(T("基本信息", "Basic Information", lang)) {
                    LabeledTextField(T("姓名 *", "Name *", lang), text: $name,
                                     placeholder: T("例：我自己、妈妈、老公", "e.g. Me, Mom, Partner", lang))

                    Toggle(T("填写出生日期", "Add date of birth", lang), isOn: $hasDate)
                    if hasDate {
                        DatePicker(T("出生日期", "Date of birth", lang),
                                   selection: $birthDate, in: ...Date(),
                                   displayedComponents: .date)
                    }

                    Picker(T("性别", "Gender", lang), selection: $gender) {
                        Text(T("不填", "Not set", lang)).tag("")
                        Text(T("女", "Female", lang)).tag("女")
                        Text(T("男", "Male", lang)).tag("男")
                    }

                    Picker(T("血型", "Blood type", lang), selection: $bloodType) {
                        Text(T("不填", "Not set", lang)).tag("")
                        ForEach(["A+","A-","B+","B-","AB+","AB-","O+","O-"], id: \.self) { Text($0).tag($0) }
                    }
                }

                Section(T("其他", "Other", lang)) {
                    LabeledTextField(T("过敏史", "Allergies", lang), text: $allergies,
                                     placeholder: T("例：青霉素、海鲜", "e.g. Penicillin, shellfish", lang))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(T("备注", "Notes", lang)).font(.caption).foregroundColor(.secondary)
                        TextEditor(text: $notes).frame(minHeight: 60)
                    }
                }
            }
            .navigationTitle(profile == nil
                             ? T("添加家庭成员", "Add Family Member", lang)
                             : T("编辑档案", "Edit Profile", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(T("取消", "Cancel", lang)) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(T("保存", "Save", lang)) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
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
        p.name = name.trimmingCharacters(in: .whitespaces)
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
