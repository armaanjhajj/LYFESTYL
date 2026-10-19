//
//  CameraController.swift
//  LYFESTYL
//
//  The app's own camera. Snapping doesn't run a photo capture (which waits on
//  exposure, focus and processing); it takes the very next frame from the live
//  video feed, the way Snapchat does, so the shutter feels instant. The frame
//  is downscaled to what the model needs and kept in memory only. Nothing is
//  ever written to disk or the photo library.
//

import AVFoundation
import CoreImage
import Observation
import Synchronization

@Observable
final class CameraController {

    enum State: Equatable {
        case idle
        case needsPermission
        case denied
        /// No camera (the Simulator) or it failed to configure.
        case unavailable
        case running
    }

    private(set) var state: State = .idle

    @ObservationIgnored let pipeline = CameraPipeline()

    var session: AVCaptureSession { pipeline.session }

    /// Ask for access if needed, configure once, then run.
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            state = .needsPermission
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        case .denied, .restricted:
            state = .denied
            return
        default:
            break
        }
        let running = await pipeline.start()
        state = running ? .running : .unavailable
    }

    func stop() {
        guard state == .running else { return }
        Task { await pipeline.stop() }
        state = .idle
    }

    /// The next frame, upright and downscaled. nil if the camera isn't running.
    func snapshot() async -> CGImage? {
        guard state == .running else { return nil }
        return await pipeline.nextFrame()
    }

    /// Focus and expose at a point in the preview's normalized device space.
    func focus(at devicePoint: CGPoint) {
        pipeline.focus(at: devicePoint)
    }
}

/// The capture graph, owned off the main actor. AVFoundation objects are
/// configured on `sessionQueue` and frames arrive on `videoQueue`; the only
/// state shared between them is the pending snapshot request, behind a Mutex.
nonisolated final class CameraPipeline: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoQueue = DispatchQueue(label: "camera.frames", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let context = CIContext()
    private var device: AVCaptureDevice?
    private var isConfigured = false

    /// Continuations waiting on the next frame, keyed so a timeout can find its own.
    private let pending = Mutex<[UUID: CheckedContinuation<CGImage?, Never>]>([:])

    /// Longest edge handed to the model. Plenty to tell rice from quinoa, small
    /// enough to keep memory and latency down.
    private static let maxDimension: CGFloat = 1280

    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !self.isConfigured { self.isConfigured = self.configure() }
                if self.isConfigured, !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: self.isConfigured)
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if self.session.isRunning { self.session.stopRunning() }
                continuation.resume()
            }
        }
        // Anyone still waiting on a frame gets nothing rather than hanging.
        let waiting = pending.withLock { list in
            defer { list.removeAll() }
            return Array(list.values)
        }
        waiting.forEach { $0.resume(returning: nil) }
    }

    /// The next frame, or nil if none arrives within a second (an interrupted
    /// session, say), so the shutter can never hang.
    func nextFrame() async -> CGImage? {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            pending.withLock { $0[id] = continuation }
            videoQueue.asyncAfter(deadline: .now() + 1) {
                self.pending.withLock { $0.removeValue(forKey: id) }?.resume(returning: nil)
            }
        }
    }

    func focus(at point: CGPoint) {
        sessionQueue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        }
    }

    // MARK: - Setup

    private func configure() -> Bool {
        // Virtual multi-camera devices switch to the ultra wide for close-ups on
        // their own, which is exactly how people photograph a plate.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        guard let device = discovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: device) else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080

        guard session.canAddInput(input) else { return false }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)

        // Portrait frames, so what the model sees matches what the person framed.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        }
        self.device = device
        return true
    }

    // MARK: - Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Cheap check first: almost every frame has no one waiting for it.
        let waiting = pending.withLock { list -> [CheckedContinuation<CGImage?, Never>] in
            defer { list.removeAll() }
            return Array(list.values)
        }
        guard !waiting.isEmpty else { return }

        let image = sampleBuffer.imageBuffer.flatMap(render)
        waiting.forEach { $0.resume(returning: image) }
    }

    private func render(_ buffer: CVPixelBuffer) -> CGImage? {
        var image = CIImage(cvPixelBuffer: buffer)
        let longest = max(image.extent.width, image.extent.height)
        if longest > Self.maxDimension {
            let scale = Self.maxDimension / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return context.createCGImage(image, from: image.extent.integral)
    }
}
