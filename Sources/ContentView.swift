import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var controller: ScreenGuardController
    @State private var showWhitelistSheet = false
    @State private var showTargetPicker = false
    @State private var showDirectoryPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Camera Preview
            ZStack {
                CameraPreviewView(session: controller.session)
                    .frame(minHeight: 260)

                // Threat border overlay
                if controller.threatDetected {
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color.red, lineWidth: 6)
                        .animation(.easeInOut(duration: 0.3), value: controller.threatDetected)
                }

                // Face count badge
                VStack {
                    HStack {
                        Spacer()
                        Label("\(controller.faceCount)", systemImage: "person.fill")
                            .font(.system(.caption, design: .rounded).bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                }
                .padding(8)
            }

            Divider()

            // Controls Panel - scrollable
            ScrollView {
                VStack(spacing: 14) {
                    // Status
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                            .shadow(color: statusColor.opacity(0.6), radius: 4)

                        Text(controller.statusMessage)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)

                        Spacer()
                    }

                    // Main control button
                    Button(action: {
                        if controller.isMonitoring {
                            controller.stopMonitoring()
                        } else {
                            controller.startMonitoring()
                        }
                    }) {
                        Label(
                            controller.isMonitoring ? "停止监控" : "开始监控",
                            systemImage: controller.isMonitoring ? "stop.circle.fill" : "play.circle.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(controller.isMonitoring ? .red : .accentColor)

                    // Calibration Status
                    CalibrationStatusView()

                    GroupBox {
                        HStack {
                            Image(nsImage: controller.targetApp.icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text(controller.targetApp.name)
                                .font(.subheadline)
                            Spacer()
                            Button("更换") {
                                showTargetPicker = true
                            }
                            .controlSize(.small)
                        }
                        Text("检测到有人时自动切换到此应用")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("切换目标", systemImage: "arrow.right.circle.fill")
                    }

                    // Whitelist
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            if controller.whitelistedApps.isEmpty {
                                Text("暂无白名单应用")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(controller.whitelistedApps) { app in
                                    HStack(spacing: 8) {
                                        Image(nsImage: app.icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                        Text(app.name)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Spacer()
                                        Button(action: {
                                            withAnimation {
                                                controller.removeFromWhitelist(app)
                                            }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            Button(action: { showWhitelistSheet = true }) {
                                Label("添加应用", systemImage: "plus.circle")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                        }
                        Text("白名单中的应用在前台时不会触发切换")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("白名单 (\(controller.whitelistedApps.count))", systemImage: "shield.checkered")
                    }

                    // Settings
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("检测灵敏度")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(String(format: "%.1f", controller.detectionDelay))s")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $controller.detectionDelay, in: 0.3...3.0, step: 0.1)
                            Text("有人注视屏幕超过该时间后触发切换")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Divider()

                            HStack {
                                Text("切换冷却时间")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(String(format: "%.0f", controller.cooldownDuration))s")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $controller.cooldownDuration, in: 3...30, step: 1)
                            Text("切换应用后的等待冷却时间")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } label: {
                        Label("检测设置", systemImage: "gear")
                    }

                    // ── Snapshot Feature ──────────────────────────────────────
                    SnapshotSettingsView(showDirectoryPicker: $showDirectoryPicker)
                }
                .padding()
            }
            .background(.background)
        }
        .frame(minWidth: 440, minHeight: 620)
        .sheet(isPresented: $showWhitelistSheet) {
            AppPickerView(title: "添加白名单应用", subtitle: "选择不需要保护的应用") { app in
                controller.addToWhitelist(app)
            }
        }
        .sheet(isPresented: $showTargetPicker) {
            AppPickerView(title: "选择切换目标", subtitle: "检测到有人时自动切换到此应用") { app in
                controller.targetApp = app
            }
        }
        // Directory picker — uses the system folder-selection panel
        .fileImporter(
            isPresented: $showDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                // On macOS, fileImporter may return a security-scoped URL.
                // Start accessing it so we can verify the path is reachable.
                _ = url.startAccessingSecurityScopedResource()
                controller.snapshotDirectory = url
            case .failure:
                break
            }
        }
    }

    private var statusColor: Color {
        if !controller.isMonitoring { return .gray }
        if controller.threatDetected { return .red }
        if !controller.isCalibrated { return .yellow }
        return .green
    }
}

// MARK: - Calibration Status View

private struct CalibrationStatusView: View {
    @EnvironmentObject var controller: ScreenGuardController
    @State private var showResetConfirm = false

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: controller.hasStoredCalibration
                      ? "person.crop.circle.badge.checkmark"
                      : "person.crop.circle.badge.questionmark")
                    .font(.title2)
                    .foregroundColor(controller.hasStoredCalibration ? .green : .orange)

                // Status text
                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.hasStoredCalibration ? "校准数据已保存" : "尚未校准")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(controller.hasStoredCalibration
                         ? "启动监控时将直接跳过校准阶段"
                         : "首次启动监控时将自动校准（约 6 秒）")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Reset button (only shown when calibration data exists)
                if controller.hasStoredCalibration {
                    Button("重新校准") {
                        showResetConfirm = true
                    }
                    .controlSize(.small)
                    .foregroundColor(.orange)
                    .confirmationDialog(
                        "确认重置校准？",
                        isPresented: $showResetConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("重置", role: .destructive) {
                            controller.resetCalibration()
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("已保存的人脸校准数据将被清除，下次启动监控时需要重新校准（约 6 秒）。")
                    }
                }
            }
        } label: {
            Label("人脸校准", systemImage: "person.crop.rectangle.stack.fill")
        }
    }
}

// MARK: - Snapshot Settings Panel

private struct SnapshotSettingsView: View {
    @EnvironmentObject var controller: ScreenGuardController
    @Binding var showDirectoryPicker: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Toggle row
                Toggle(isOn: $controller.snapshotEnabled) {
                    Text("触发时自动截图偷窥者")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)

                if controller.snapshotEnabled {
                    Divider()

                    // Directory picker row
                    HStack(spacing: 8) {
                        Image(systemName: controller.snapshotDirectory != nil
                              ? "folder.fill"
                              : "folder.badge.questionmark")
                            .foregroundColor(controller.snapshotDirectory != nil ? .accentColor : .secondary)
                            .frame(width: 16)

                        if let dir = controller.snapshotDirectory {
                            Text(dir.path)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundColor(.primary)
                        } else {
                            Text("未选择保存目录")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }

                        Spacer()

                        Button(controller.snapshotDirectory != nil ? "更改" : "选择") {
                            showDirectoryPicker = true
                        }
                        .controlSize(.small)

                        if controller.snapshotDirectory != nil {
                            Button {
                                openSnapshotDirectory()
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                            .help("在 Finder 中打开")
                        }
                    }

                    // Session counter (only shown after at least one snapshot)
                    if controller.sessionSnapshotCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.stack.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("本次已保存 \(controller.sessionSnapshotCount) 张截图")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 2)
                    }

                    // Warning if enabled but no directory chosen
                    if controller.snapshotDirectory == nil {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                            Text("请先选择保存目录，否则截图功能不会生效")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }

                    Text("检测到偷窥者时，将从摄像头截取一张照片保存到指定目录")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        } label: {
            Label("截图保护", systemImage: "camera.on.rectangle.fill")
        }
    }

    private func openSnapshotDirectory() {
        guard let dir = controller.snapshotDirectory else { return }
        NSWorkspace.shared.open(dir)
    }
}

// MARK: - App Picker Sheet

struct AppPickerView: View {
    let title: String
    let subtitle: String
    let onSelect: (AppInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var apps: [AppInfo] = []
    @State private var showRunningOnly = false
    @State private var isLoading = false

    var filteredApps: [AppInfo] {
        if searchText.isEmpty { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Search + filter
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索应用…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

                Picker("", selection: $showRunningOnly) {
                    Text("全部").tag(false)
                    Text("运行中").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .onChange(of: showRunningOnly) { _ in
                    refreshApps()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // App list — shows a spinner while scanning the filesystem
            ZStack {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                        Text("正在读取应用列表…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredApps) { app in
                        Button(action: {
                            onSelect(app)
                            dismiss()
                        }) {
                            HStack(spacing: 10) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                        .font(.subheadline)
                                    Text(app.bundleId)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                }
            }

            Divider()

            // Footer
            HStack {
                if isLoading {
                    Text("加载中…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(filteredApps.count) 个应用")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 400, height: 480)
        .onAppear { refreshApps() }
    }

    private func refreshApps() {
        isLoading = true
        apps = []
        let runningOnly = showRunningOnly
        Task.detached(priority: .userInitiated) {
            let result = runningOnly ? AppInfo.runningApps() : AppInfo.installedApps()
            await MainActor.run {
                apps = result
                isLoading = false
            }
        }
    }
}
