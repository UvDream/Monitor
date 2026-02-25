import SwiftUI
import AVFoundation
import AppKit

/// NSViewRepresentable wrapper for AVCaptureVideoPreviewLayer
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraHostView {
        let view = CameraHostView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: CameraHostView, context: Context) {
        // Session is managed externally; nothing to update here
    }
}

/// Hosts the AVCaptureVideoPreviewLayer inside an NSView
class CameraHostView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(previewLayer)
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
