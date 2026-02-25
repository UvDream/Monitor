import Foundation
import AVFoundation
import Vision
import AppKit
import CoreMedia
import Combine

/// Core controller: manages camera capture, face detection, and automatic app switching.
///
/// Detection logic:
///   1. **Calibration** – On start, records the user's face size over 30 frames (≈6 s at 200 ms intervals).
///   2. **Monitoring** – After calibration, continuously detects faces in camera frames.
///      - The *owner* is identified as the face whose area is **closest** to the calibrated reference area
///        (not simply the largest face, which could be a snooper who leans in).
///      - Any other face whose yaw roughly faces the camera (|yaw| < 0.5 rad) is a potential threat.
///      - If a threat persists for `detectionDelay` seconds, the target app is activated.
///   3. **Cooldown** – After switching, detection pauses for `cooldownDuration` seconds.
///      The cooldown timer uses a cancellable `DispatchWorkItem` so stopping monitoring
///      always cancels any pending callback (fixes the previous race condition).
///   4. **Snapshot** – When a threat triggers, the latest camera frame is saved as a JPEG
///      to a user-specified directory (if the feature is enabled).
class ScreenGuardController: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isMonitoring = false
    @Published var faceCount = 0
    @Published var threatDetected = false
    @Published var isCalibrated = false
    @Published var statusMessage = "就绪"

    /// Whether a valid calibration has been saved from a previous session.
    /// When `true`, the next `startMonitoring()` will skip the calibration phase entirely.
    @Published var hasStoredCalibration: Bool = false

    /// Seconds a threat must persist before triggering — persisted across launches.
    @Published var detectionDelay: Double {
        didSet { UserDefaults.standard.set(detectionDelay, forKey: detectionDelayKey) }
    }

    /// Seconds to pause detection after switching — persisted across launches.
    @Published var cooldownDuration: Double {
        didSet { UserDefaults.standard.set(cooldownDuration, forKey: cooldownDurationKey) }
    }

    // MARK: - Whitelist & Target App

    /// Apps in the whitelist are "safe" — no auto-switching when one is in the foreground.
    @Published var whitelistedApps: [AppInfo] = [] {
        didSet { saveWhitelist() }
    }

    /// The app to switch to when a threat is detected. Defaults to VS Code.
    @Published var targetApp: AppInfo = AppInfo(bundleId: "com.microsoft.VSCode", name: "Visual Studio Code") {
        didSet { saveTargetApp() }
    }

    // MARK: - Snapshot Feature

    /// Whether to save a camera snapshot when an intruder is detected.
    @Published var snapshotEnabled: Bool {
        didSet { UserDefaults.standard.set(snapshotEnabled, forKey: snapshotEnabledKey) }
    }

    /// Directory where intruder snapshots are saved.
    @Published var snapshotDirectory: URL? {
        didSet { UserDefaults.standard.set(snapshotDirectory?.path, forKey: snapshotDirectoryKey) }
    }

    /// Number of snapshots saved in the current monitoring session.
    @Published var sessionSnapshotCount: Int = 0

    // MARK: - Camera (private session with read-only accessor)

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.monitor.facedetection", qos: .userInitiated)

    /// Read-only accessor for the preview layer (CameraPreviewView).
    var session: AVCaptureSession { captureSession }

    // MARK: - Detection internals

    /// Only process one frame every `processInterval` seconds to save CPU.
    private var lastProcessTime = Date.distantPast
    private let processInterval: TimeInterval = 0.2

    /// Calibrated reference face area (main thread).
    private var ownerFaceArea: CGFloat = 0
    private var calibrationSamples: [CGFloat] = []
    private let calibrationSampleCount = 30

    /// Timestamp when a threat was first detected continuously (main thread).
    private var threatStartTime: Date?

    /// Cooldown end timestamp (main thread).
    private var cooldownUntil: Date?

    /// Cancellable cooldown timer — prevents the old `asyncAfter` from firing after stopMonitoring().
    private var cooldownWorkItem: DispatchWorkItem?

    // MARK: - Snapshot internals

    /// Protects cross-thread access to `_latestPixelBuffer`.
    private let bufferLock = NSLock()

    /// Latest camera frame received from the capture session.
    /// Written on `processingQueue`, read on `snapshotQueue`.
    private var _latestPixelBuffer: CVPixelBuffer?

    /// Background queue for image rendering and file I/O (avoids stalling the camera feed).
    private let snapshotQueue = DispatchQueue(label: "com.monitor.snapshot", qos: .utility)

    /// Reusable CIContext — creating one per frame is expensive.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Persistence Keys

    private let whitelistKey         = "monitor.whitelistedApps"
    private let targetAppKey         = "monitor.targetApp"
    private let detectionDelayKey    = "monitor.detectionDelay"
    private let cooldownDurationKey  = "monitor.cooldownDuration"
    private let snapshotEnabledKey   = "monitor.snapshotEnabled"
    private let snapshotDirectoryKey = "monitor.snapshotDirectory"
    private let ownerFaceAreaKey     = "monitor.ownerFaceArea"

    // MARK: - Init

    override init() {
        // Restore persisted settings (fall back to sensible defaults if never saved).
        // Note: these assignments run before super.init(), so `didSet` observers are NOT triggered.
        let savedDelay    = UserDefaults.standard.double(forKey: "monitor.detectionDelay")
        detectionDelay    = savedDelay > 0 ? savedDelay : 1.0

        let savedCooldown = UserDefaults.standard.double(forKey: "monitor.cooldownDuration")
        cooldownDuration  = savedCooldown > 0 ? savedCooldown : 10.0

        snapshotEnabled   = UserDefaults.standard.bool(forKey: "monitor.snapshotEnabled")

        if let savedPath = UserDefaults.standard.string(forKey: "monitor.snapshotDirectory"),
           !savedPath.isEmpty {
            let url = URL(fileURLWithPath: savedPath)
            snapshotDirectory = FileManager.default.fileExists(atPath: url.path) ? url : nil
        } else {
            snapshotDirectory = nil
        }

        // Restore saved calibration — if ownerFaceArea > 0 we can skip calibration on next start.
        let savedArea = UserDefaults.standard.double(forKey: "monitor.ownerFaceArea")
        ownerFaceArea        = CGFloat(savedArea)
        hasStoredCalibration = savedArea > 0

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
        // Reset detection state — but preserve ownerFaceArea if already calibrated from a prior session
        calibrationSamples.removeAll()
        threatStartTime = nil
        cooldownUntil = nil
        threatDetected = false
        sessionSnapshotCount = 0
        cancelCooldownTimer()

        // Skip calibration if we already have a stored face-area reference
        let skipCalibration = ownerFaceArea > 0
        isCalibrated = skipCalibration

        processingQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }

        DispatchQueue.main.async {
            self.isMonitoring = true
            self.statusMessage = skipCalibration
                ? "✅ 监控中（使用已保存的校准数据）"
                : "校准中 - 请正对摄像头，确保只有你…"
        }
    }

    /// Clears the stored calibration so the next `startMonitoring()` will recalibrate from scratch.
    /// If monitoring is currently active it is stopped first.
    func resetCalibration() {
        if isMonitoring { stopMonitoring() }
        ownerFaceArea = 0
        calibrationSamples.removeAll()
        hasStoredCalibration = false
        isCalibrated = false
        UserDefaults.standard.removeObject(forKey: ownerFaceAreaKey)
        statusMessage = "校准已重置 — 下次启动将重新校准（约 6 秒）"
    }

    func stopMonitoring() {
        cancelCooldownTimer()   // ← guarantees the asyncAfter block never fires after this

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

    /// Cancels any pending cooldown DispatchWorkItem.
    private func cancelCooldownTimer() {
        cooldownWorkItem?.cancel()
        cooldownWorkItem = nil
    }

    // MARK: - Face Processing

    /// Called on `processingQueue` from the sample buffer delegate.
    /// Performs lightweight pre-computation here, then dispatches only state
    /// mutations and UI updates to the main thread (keeps main thread free).
    private func processFaces(_ faces: [VNFaceObservation]) {
        // --- Pre-computation on processingQueue (pure, no shared state) ---
        let count = faces.count

        // Extract areas and yaws into plain value arrays — cheap, avoids bridging costs on main thread
        let areas: [CGFloat] = faces.map { $0.boundingBox.width * $0.boundingBox.height }
        let yaws:  [Double]  = faces.map { $0.yaw?.doubleValue ?? 0 }

        // --- State mutations and UI updates on main thread ---
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.faceCount = count

            if !self.isCalibrated {
                self.calibrate(areas: areas)
                return
            }

            // During cooldown, just show countdown and skip detection
            if let cd = self.cooldownUntil {
                if Date() < cd {
                    let remaining = Int(cd.timeIntervalSinceNow) + 1
                    self.statusMessage = "⏳ 冷却中 (\(remaining)s)…"
                    return
                } else {
                    self.cooldownUntil = nil
                }
            }

            self.detectThreat(areas: areas, yaws: yaws)
        }
    }

    // MARK: - Calibration (main thread)

    private func calibrate(areas: [CGFloat]) {
        guard areas.count == 1 else {
            calibrationSamples.removeAll()
            statusMessage = "校准中 - 请确保只有你在画面中…"
            return
        }

        calibrationSamples.append(areas[0])
        let remaining = calibrationSampleCount - calibrationSamples.count
        statusMessage = "校准中… 还需 \(remaining) 帧"

        if calibrationSamples.count >= calibrationSampleCount {
            ownerFaceArea = calibrationSamples.reduce(0, +) / CGFloat(calibrationSamples.count)
            isCalibrated = true
            hasStoredCalibration = true
            // Persist so future launches skip calibration
            UserDefaults.standard.set(Double(ownerFaceArea), forKey: ownerFaceAreaKey)
            statusMessage = "✅ 校准完成，监控中（数据已保存）"
        }
    }

    // MARK: - Threat Detection (main thread)

    private func detectThreat(areas: [CGFloat], yaws: [Double]) {
        guard areas.count > 1 else {
            clearThreat()
            if isCalibrated && !threatDetected { statusMessage = "✅ 监控中" }
            return
        }

        // Identify the owner as the face whose area is *closest* to the calibrated reference.
        // The original code naively picked the largest face, which fails when a snooper leans in
        // close enough to become the biggest face in frame.
        let ownerIndex = areas.enumerated().min(by: {
            abs($0.element - ownerFaceArea) < abs($1.element - ownerFaceArea)
        })?.offset ?? 0

        // All other faces are potential snoopers
        let snoopers = areas.indices.filter { $0 != ownerIndex }

        // A snooper is a threat if their yaw is roughly facing the camera
        let lookingAtScreen = snoopers.filter { abs(yaws[$0]) < 0.5 }

        if !lookingAtScreen.isEmpty {
            if threatStartTime == nil { threatStartTime = Date() }

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
        if threatDetected { threatDetected = false }
    }

    // MARK: - App Switching (main thread)

    private func triggerSwitch() {
        guard !threatDetected else { return }   // avoid re-triggering during cooldown

        // Whitelist check: if the current foreground app is safe, skip switching
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let frontBundleId = frontApp.bundleIdentifier {
            if whitelistedApps.contains(where: { $0.bundleId == frontBundleId }) {
                statusMessage = "✅ 白名单应用，已跳过"
                threatStartTime = nil
                return
            }
        }

        threatDetected = true
        statusMessage = "🚨 已切换到 \(targetApp.name)！"
        switchToTargetApp()

        // --- Snapshot capture ---
        // Grab the latest pixel buffer reference (thread-safe via lock) and dispatch
        // image rendering + file I/O to the background snapshotQueue.
        if snapshotEnabled, let dir = snapshotDirectory {
            bufferLock.lock()
            let buffer = _latestPixelBuffer
            bufferLock.unlock()

            if let buffer = buffer {
                snapshotQueue.async { [weak self] in
                    self?.captureAndSaveSnapshot(from: buffer, to: dir)
                }
            }
        }

        let duration = cooldownDuration
        cooldownUntil = Date().addingTimeInterval(duration)

        // Use DispatchWorkItem so stopMonitoring() can cancel it before it fires.
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.threatDetected = false
            self.threatStartTime = nil
            self.cooldownUntil = nil
            self.cooldownWorkItem = nil
            if self.isMonitoring { self.statusMessage = "✅ 监控中" }
        }
        cooldownWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func switchToTargetApp() {
        let bundleId = targetApp.bundleId

        // Activate an already-running instance first
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
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

    // MARK: - Snapshot Capture (snapshotQueue)

    /// Renders the given pixel buffer to a JPEG and writes it to `directory`.
    /// Runs entirely on `snapshotQueue` to avoid blocking the camera pipeline or the UI.
    private func captureAndSaveSnapshot(from pixelBuffer: CVPixelBuffer, to directory: URL) {
        // 1. Convert CVPixelBuffer → CIImage → CGImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        // 2. Convert CGImage → JPEG data
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        guard let tiffData  = nsImage.tiffRepresentation,
              let bitmap    = NSBitmapImageRep(data: tiffData),
              let jpegData  = bitmap.representation(using: .jpeg,
                                                    properties: [.compressionFactor: 0.9])
        else { return }

        // 3. Build filename: intruder_2026-02-25_15-30-00.123.jpg
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss.SSS"
        let timestamp = formatter.string(from: Date())
        let fileURL = directory.appendingPathComponent("intruder_\(timestamp).jpg")

        // 4. Write to disk
        do {
            try jpegData.write(to: fileURL, options: .atomic)
            DispatchQueue.main.async { [weak self] in
                self?.sessionSnapshotCount += 1
            }
        } catch {
            // Silently fail — a snapshot error must never disrupt monitoring
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

        // Store the latest frame for snapshot capture.
        // We hold a strong reference here — CVPixelBuffer is reference-counted,
        // so keeping it prevents the buffer pool from reusing it prematurely.
        bufferLock.lock()
        _latestPixelBuffer = pixelBuffer
        bufferLock.unlock()

        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            guard let results = request.results as? [VNFaceObservation] else { return }
            self?.processFaces(results)
        }

        // Use latest revision for yaw (roll/pitch) support
        request.revision = VNDetectFaceRectanglesRequestRevision3

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }
}
