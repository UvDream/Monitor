import Foundation
import AVFoundation
import Vision
import AppKit
import CoreMedia
import Combine

/// Core controller: manages camera capture, face detection, and automatic app switching.
///
/// Detection logic:
///   1. **Calibration** – On start, records the user's face size over 30 frames (≈1.5 s at 200 ms intervals).
///   2. **Monitoring** – After calibration, continuously detects faces in camera frames.
///      - The *owner* is identified as the largest face (closest to camera).
///      - Any additional face whose yaw is roughly facing the camera (|yaw| < 0.5 rad) is considered
///        a potential threat (someone looking at the screen).
///      - If a threat persists for `detectionDelay` seconds, VS Code is activated.
///   3. **Cooldown** – After switching, detection pauses for `cooldownDuration` seconds.
class ScreenGuardController: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isMonitoring = false
    @Published var faceCount = 0
    @Published var threatDetected = false
    @Published var isCalibrated = false
    @Published var statusMessage = "就绪"
    @Published var detectionDelay: Double = 1.0      // seconds a threat must persist before triggering
    @Published var cooldownDuration: Double = 10.0    // seconds to pause after switching

    // MARK: - Whitelist & Target App

    /// Apps in the whitelist are "safe" — no auto-switching when one of them is the active foreground app.
    @Published var whitelistedApps: [AppInfo] = [] {
        didSet { saveWhitelist() }
    }

    /// The app to switch to when a threat is detected. Defaults to VS Code.
    @Published var targetApp: AppInfo = AppInfo(bundleId: "com.microsoft.VSCode", name: "Visual Studio Code") {
        didSet { saveTargetApp() }
    }

    // MARK: - Camera

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.monitor.facedetection", qos: .userInitiated)

    // MARK: - Detection internals

    /// Only process one frame every `processInterval` seconds to save CPU.
    private var lastProcessTime = Date.distantPast
    private let processInterval: TimeInterval = 0.2

    /// Timestamp when a threat was first detected continuously.
    private var threatStartTime: Date?

    /// Cooldown end timestamp.
    private var cooldownUntil: Date?

    // MARK: - Calibration

    private var ownerFaceArea: CGFloat = 0
    private var calibrationSamples: [CGFloat] = []
    private let calibrationSampleCount = 30

    // MARK: - Persistence Keys
    private let whitelistKey = "monitor.whitelistedApps"
    private let targetAppKey = "monitor.targetApp"

    // MARK: - Init

    override init() {
        super.init()
        loadWhitelist()
        loadTargetApp()
    }

    // MARK: - Camera Access

    func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.statusMessage = "❌ 摄像头权限被拒绝"
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.statusMessage = "❌ 请在系统设置中允许摄像头权限"
            }
        }
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        // Prefer the default video device (built-in FaceTime camera on most Macs)
        guard let device = AVCaptureDevice.default(for: .video) else {
            DispatchQueue.main.async { self.statusMessage = "❌ 未找到摄像头" }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)

            captureSession.beginConfiguration()
            captureSession.sessionPreset = .medium   // lower resolution for performance

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)

            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }

            captureSession.commitConfiguration()

            DispatchQueue.main.async { self.statusMessage = "摄像头就绪 - 点击「开始监控」" }
        } catch {
            DispatchQueue.main.async { self.statusMessage = "❌ 摄像头初始化失败: \(error.localizedDescription)" }
        }
    }

    // MARK: - Start / Stop

    func startMonitoring() {
        // Reset calibration state
        isCalibrated = false
        calibrationSamples.removeAll()
        ownerFaceArea = 0
        threatStartTime = nil
        cooldownUntil = nil
        threatDetected = false

        processingQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }

        DispatchQueue.main.async {
            self.isMonitoring = true
            self.statusMessage = "校准中 - 请正对摄像头，确保只有你…"
        }
    }

    func stopMonitoring() {
        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }

        DispatchQueue.main.async {
            self.isMonitoring = false
            self.threatDetected = false
            self.isCalibrated = false
            self.statusMessage = "已停止"
        }
    }

    // MARK: - Face Processing

    private func processFaces(_ faces: [VNFaceObservation]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.faceCount = faces.count

            if !self.isCalibrated {
                self.calibrate(with: faces)
                return
            }

            // During cooldown, skip detection
            if let cd = self.cooldownUntil {
                if Date() < cd {
                    let remaining = Int(cd.timeIntervalSinceNow) + 1
                    self.statusMessage = "⏳ 冷却中 (\(remaining)s)…"
                    return
                } else {
                    self.cooldownUntil = nil
                }
            }

            self.detectThreat(in: faces)
        }
    }

    // MARK: - Calibration

    private func calibrate(with faces: [VNFaceObservation]) {
        // Require exactly one face during calibration
        guard faces.count == 1 else {
            calibrationSamples.removeAll()
            statusMessage = "校准中 - 请确保只有你在画面中…"
            return
        }

        let face = faces[0]
        let area = face.boundingBox.width * face.boundingBox.height
        calibrationSamples.append(area)

        let remaining = calibrationSampleCount - calibrationSamples.count
        statusMessage = "校准中… 还需 \(remaining) 帧"

        if calibrationSamples.count >= calibrationSampleCount {
            ownerFaceArea = calibrationSamples.reduce(0, +) / CGFloat(calibrationSamples.count)
            isCalibrated = true
            statusMessage = "✅ 监控中"
        }
    }

    // MARK: - Threat Detection

    private func detectThreat(in faces: [VNFaceObservation]) {
        guard faces.count > 1 else {
            // 0 or 1 face → safe
            clearThreat()
            if isCalibrated && !threatDetected {
                statusMessage = "✅ 监控中"
            }
            return
        }

        // Sort faces by area descending; the largest ≈ the owner (closest)
        let sorted = faces.sorted { ($0.boundingBox.width * $0.boundingBox.height) > ($1.boundingBox.width * $1.boundingBox.height) }

        // Every face except the largest is a potential "other person"
        let others = Array(sorted.dropFirst())

        // Check if any of the other faces are roughly facing the camera
        let lookingAtScreen = others.filter { face in
            let yaw = face.yaw?.doubleValue ?? 0  // nil → assume facing camera
            return abs(yaw) < 0.5
        }

        if !lookingAtScreen.isEmpty {
            if threatStartTime == nil {
                threatStartTime = Date()
            }

            if let start = threatStartTime, Date().timeIntervalSince(start) >= detectionDelay {
                triggerSwitch()
            } else {
                statusMessage = "⚠️ 检测到有人注视屏幕…"
            }
        } else {
            clearThreat()
            statusMessage = "✅ 监控中"
        }
    }

    private func clearThreat() {
        threatStartTime = nil
        if threatDetected {
            threatDetected = false
        }
    }

    // MARK: - App Switching

    private func triggerSwitch() {
        guard !threatDetected else { return }   // avoid re-triggering during cooldown

        // Check if the current foreground app is in the whitelist
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let frontBundleId = frontApp.bundleIdentifier {
            let isWhitelisted = whitelistedApps.contains { $0.bundleId == frontBundleId }
            if isWhitelisted {
                // Current app is safe, don't switch
                statusMessage = "✅ 白名单应用，已跳过"
                threatStartTime = nil
                return
            }
        }

        threatDetected = true
        statusMessage = "🚨 已切换到 \(targetApp.name)！"

        switchToTargetApp()

        // Start cooldown
        cooldownUntil = Date().addingTimeInterval(cooldownDuration)

        DispatchQueue.main.asyncAfter(deadline: .now() + cooldownDuration) { [weak self] in
            guard let self = self else { return }
            self.threatDetected = false
            self.threatStartTime = nil
            self.cooldownUntil = nil
            if self.isMonitoring {
                self.statusMessage = "✅ 监控中"
            }
        }
    }

    private func switchToTargetApp() {
        let bundleId = targetApp.bundleId

        // Try to activate an already-running instance
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if let app = runningApps.first {
            app.activate(options: [.activateAllWindows])
            return
        }

        // Fallback: launch the app if installed but not running
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }

    // MARK: - Whitelist Management

    func addToWhitelist(_ app: AppInfo) {
        guard !whitelistedApps.contains(where: { $0.bundleId == app.bundleId }) else { return }
        whitelistedApps.append(app)
    }

    func removeFromWhitelist(_ app: AppInfo) {
        whitelistedApps.removeAll { $0.bundleId == app.bundleId }
    }

    func isInWhitelist(_ bundleId: String) -> Bool {
        whitelistedApps.contains { $0.bundleId == bundleId }
    }

    // MARK: - Persistence

    private func saveWhitelist() {
        if let data = try? JSONEncoder().encode(whitelistedApps) {
            UserDefaults.standard.set(data, forKey: whitelistKey)
        }
    }

    private func loadWhitelist() {
        if let data = UserDefaults.standard.data(forKey: whitelistKey),
           let apps = try? JSONDecoder().decode([AppInfo].self, from: data) {
            whitelistedApps = apps
        }
    }

    private func saveTargetApp() {
        if let data = try? JSONEncoder().encode(targetApp) {
            UserDefaults.standard.set(data, forKey: targetAppKey)
        }
    }

    private func loadTargetApp() {
        if let data = UserDefaults.standard.data(forKey: targetAppKey),
           let app = try? JSONDecoder().decode(AppInfo.self, from: data) {
            targetApp = app
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ScreenGuardController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Throttle: process only one frame every `processInterval` seconds
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) >= processInterval else { return }
        lastProcessTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            guard let results = request.results as? [VNFaceObservation] else { return }
            self?.processFaces(results)
        }

        // Use latest revision for yaw support
        request.revision = VNDetectFaceRectanglesRequestRevision3

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }
}
