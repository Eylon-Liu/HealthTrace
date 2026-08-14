import SwiftUI
import AVFoundation
import Photos

@main
struct HealthRecordsApp: App {
    let persistence = PersistenceController.shared
    @StateObject private var pm = ProfileManager()
    @State private var importResult: ImportResult?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("acceptedDisclaimerVersion") private var acceptedDisclaimerVersion = 0

    private var disclaimerAccepted: Bool { acceptedDisclaimerVersion >= MedicalDisclaimer.version }

    var body: some Scene {
        WindowGroup {
            // Onboarding covers the disclaimer for new installs. Existing users who
            // already finished onboarding still have to acknowledge it once, and
            // again if the wording is ever materially revised.
            if hasCompletedOnboarding && !disclaimerAccepted {
                DisclaimerGateView { acceptedDisclaimerVersion = MedicalDisclaimer.version }
            } else if hasCompletedOnboarding {
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
                            dismissButton: .default(Text(L("好的", currentLang()))) {
                                if let profile = result.profile {
                                    pm.select(profile)
                                }
                            }
                        )
                    }
            } else {
                OnboardingView(onComplete: {
                    acceptedDisclaimerVersion = MedicalDisclaimer.version
                    hasCompletedOnboarding = true
                })
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(pm)
            }
        }
    }

    private func handleIncomingFile(_ url: URL) {
        guard url.pathExtension == "healthrecord" || url.pathExtension == "json" else { return }
        let lang = currentLang()
        do {
            let profile = try ProfileExporter.importProfile(
                from: url, context: persistence.container.viewContext)
            let name = profile.name ?? ""
            let reports = profile.reports?.count ?? 0
            let conditions = profile.conditions?.count ?? 0
            importResult = ImportResult(
                title: L("导入成功", lang),
                message: T("已导入「\(name)」的健康档案，包含 \(reports) 份报告和 \(conditions) 条病史记录。",
                           "Imported \(name)'s records: \(reports) report(s) and \(conditions) condition(s).", lang),
                profile: profile
            )
        } catch {
            importResult = ImportResult(
                title: L("导入失败", lang),
                message: T("文件格式无效：\(error.localizedDescription)",
                           "Invalid file: \(error.localizedDescription)", lang)
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

// MARK: - Onboarding

struct OnboardingView: View {
    let onComplete: () -> Void
    @AppStorage("summaryLanguage") private var lang = "zh"
    @State private var currentPage = 0
    @State private var networkReady = false
    @State private var cameraGranted = false
    @State private var photosGranted = false
    @State private var agreedToDisclaimer = false

    private var useEN: Bool { lang == "en" }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                disclaimerPage.tag(1)
                permissionPage.tag(2)
                readyPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    /// The disclaimer is its own step, and the final button stays disabled until
    /// it is acknowledged — swiping past it is not enough to get into the app.
    private var disclaimerPage: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)

            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(MedicalDisclaimer.title(lang))
                .font(.title2.bold())

            ScrollView {
                DisclaimerBody(lang: lang).padding(.horizontal, 28)
            }

            Button {
                agreedToDisclaimer = true
                withAnimation { currentPage = 2 }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: agreedToDisclaimer ? "checkmark.circle.fill" : "circle")
                    Text(useEN ? "I have read and understand" : "我已阅读并理解")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 72))
                .foregroundColor(.blue)
            Text("FamilyVitals")
                .font(.largeTitle.bold())
            Text(useEN
                 ? "Your personal health records manager.\nAll data is stored locally on your device."
                 : "你的个人健康档案管理工具\n所有数据仅保存在本地设备上")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                withAnimation { currentPage = 1 }
            } label: {
                Text(useEN ? "Get Started" : "开始使用")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    private var permissionPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Text(useEN ? "App Permissions" : "应用权限说明")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 16) {
                permissionRow(
                    icon: "network",
                    iconColor: .purple,
                    title: useEN ? "Network Access" : "网络访问",
                    desc: useEN
                        ? "Required for AI-powered report analysis. Your reports are sent to the AI provider (Gemini/DeepSeek) you configure. No data is sent without your API key."
                        : "AI 智能分析报告需要联网。报告内容会发送至你配置的 AI 服务（Gemini/DeepSeek）进行分析，未设置 API Key 时不会发送任何数据。",
                    status: networkReady ? "✓" : nil
                )

                permissionRow(
                    icon: "camera.fill",
                    iconColor: .orange,
                    title: useEN ? "Camera" : "相机",
                    desc: useEN
                        ? "Take photos of medical reports for AI extraction."
                        : "拍摄医疗报告照片，用于 AI 自动提取信息。",
                    status: cameraGranted ? "✓" : nil
                )

                permissionRow(
                    icon: "photo.fill",
                    iconColor: .green,
                    title: useEN ? "Photo Library" : "相册",
                    desc: useEN
                        ? "Select existing report photos from your library."
                        : "从相册选择已有的报告照片。",
                    status: photosGranted ? "✓" : nil
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                requestAllPermissions()
            } label: {
                Text(useEN ? "Allow Permissions" : "授权所有权限")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 32)

            Button {
                withAnimation { currentPage = 3 }
            } label: {
                Text(useEN ? "Skip for now" : "暂时跳过")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)
        }
    }

    private var readyPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)
            Text(useEN ? "You're all set!" : "准备就绪！")
                .font(.title.bold())
            Text(useEN
                 ? "Start by creating a profile and adding your first health report."
                 : "创建你的档案，开始记录你的健康数据吧。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                onComplete()
            } label: {
                Text(useEN ? "Enter App" : "进入应用")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(agreedToDisclaimer ? Color.green : Color.gray.opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .disabled(!agreedToDisclaimer)
            .padding(.horizontal, 32)

            if !agreedToDisclaimer {
                Button {
                    withAnimation { currentPage = 1 }
                } label: {
                    Text(useEN ? "Please review the disclaimer first" : "请先阅读并确认免责声明")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer().frame(height: 40)
        }
    }

    private func permissionRow(icon: String, iconColor: Color, title: String, desc: String, status: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    if let s = status {
                        Text(s).font(.caption).foregroundColor(.green)
                    }
                }
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requestAllPermissions() {
        // Camera
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { cameraGranted = granted }
        }

        // Photos
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { photosGranted = status == .authorized || status == .limited }
        }

        // Network: trigger by making a lightweight request
        triggerNetworkPermission()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { currentPage = 3 }
        }
    }

    private func triggerNetworkPermission() {
        guard let url = URL(string: "https://generativelanguage.googleapis.com") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                networkReady = true
            }
        }.resume()
    }
}
