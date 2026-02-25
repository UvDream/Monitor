import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var controller: ScreenGuardController
    @State private var showWhitelistSheet = false
    @State private var showTargetPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Camera Preview
            ZStack {
                CameraPreviewView(session: controller.captureSession)
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

                    // Target App
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
                        Label("设置", systemImage: "gear")
                    }
                }
                .padding()
            }
            .background(.background)
        }
        .frame(minWidth: 440, minHeight: 620)
        .onAppear {
            controller.requestCameraAccess()
        }
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
    }

    private var statusColor: Color {
        if !controller.isMonitoring { return .gray }
        if controller.threatDetected { return .red }
        if !controller.isCalibrated { return .yellow }
        return .green
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

            // App list
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

            Divider()

            // Footer
            HStack {
                Text("\(filteredApps.count) 个应用")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        apps = showRunningOnly ? AppInfo.runningApps() : AppInfo.installedApps()
    }
}
