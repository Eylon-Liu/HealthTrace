import SwiftUI

struct AddConditionView: View {
    @Environment(\.managedObjectContext) var ctx
    @Environment(\.dismiss) var dismiss

    var profile: Profile?
    var condition: Condition?

    @State private var name = ""
    @State private var category = "诊断"
    @State private var hasOnset = false
    @State private var dateOnset = Date()
    @State private var hasResolved = false
    @State private var dateResolved = Date()
    @State private var status = "active"
    @State private var severity = ""
    @State private var hospital = ""
    @State private var doctor = ""
    @State private var restrictions = ""
    @State private var notes = ""

    var body: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    LabeledTextField("名称 *", text: $name, placeholder: "例：腰椎间盘突出L4-L5")

                    Picker("类别", selection: $category) {
                        ForEach(["诊断","手术","过敏","慢性病","限制/注意事项","其他"], id: \.self) { Text($0).tag($0) }
                    }

                    Picker("状态", selection: $status) {
                        Text("活跃中").tag("active")
                        Text("观察中").tag("monitoring")
                        Text("已解决").tag("resolved")
                    }

                    Picker("严重程度", selection: $severity) {
                        Text("不填").tag("")
                        Text("轻度").tag("mild")
                        Text("中度").tag("moderate")
                        Text("重度").tag("severe")
                    }
                }

                Section("时间") {
                    Toggle("填写开始时间", isOn: $hasOnset)
                    if hasOnset {
                        DatePicker("开始时间", selection: $dateOnset, displayedComponents: .date)
                    }
                    Toggle("填写结束/痊愈时间", isOn: $hasResolved)
                    if hasResolved {
                        DatePicker("结束时间", selection: $dateResolved, displayedComponents: .date)
                    }
                }

                Section("就医信息") {
                    LabeledTextField("医院", text: $hospital, placeholder: "就诊医院")
                    LabeledTextField("医生", text: $doctor, placeholder: "主治医生")
                }

                Section("注意事项 / 活动限制") {
                    TextEditor(text: $restrictions)
                        .frame(minHeight: 80)
                        .overlay(
                            restrictions.isEmpty
                            ? Text("例：禁止负重超过5kg、避免久坐、禁止弯腰搬重物")
                                .font(.body).foregroundColor(.gray.opacity(0.5))
                                .padding(.top, 8).padding(.leading, 4)
                            : nil,
                            alignment: .topLeading
                        )
                }

                Section("详细描述") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .overlay(
                            notes.isEmpty
                            ? Text("详细病情描述、治疗过程等")
                                .font(.body).foregroundColor(.gray.opacity(0.5))
                                .padding(.top, 8).padding(.leading, 4)
                            : nil,
                            alignment: .topLeading
                        )
                }
            }
            .navigationTitle(condition == nil ? "添加病史记录" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        guard let c = condition else { return }
        name = c.name ?? ""
        category = c.category ?? "诊断"
        status = c.status ?? "active"
        severity = c.severity ?? ""
        hospital = c.hospital ?? ""
        doctor = c.doctor ?? ""
        restrictions = c.restrictions ?? ""
        notes = c.notes ?? ""
        if let d = c.dateOnset { dateOnset = d; hasOnset = true }
        if let d = c.dateResolved { dateResolved = d; hasResolved = true }
    }

    private func save() {
        let c = condition ?? Condition(context: ctx)
        if condition == nil {
            c.id = UUID()
            c.createdAt = Date()
            c.profile = profile
        }
        c.name = name
        c.category = category
        c.status = status
        c.severity = severity.isEmpty ? nil : severity
        c.hospital = hospital.isEmpty ? nil : hospital
        c.doctor = doctor.isEmpty ? nil : doctor
        c.restrictions = restrictions.isEmpty ? nil : restrictions
        c.notes = notes.isEmpty ? nil : notes
        c.dateOnset = hasOnset ? dateOnset : nil
        c.dateResolved = hasResolved ? dateResolved : nil
        try? ctx.save()
        dismiss()
    }
}
