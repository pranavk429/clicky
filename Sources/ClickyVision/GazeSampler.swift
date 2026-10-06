import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// One coarse gaze estimate from a single camera frame.
public struct GazeSample: Equatable, Sendable {
    /// Coarse gaze offset from the screen center: `x` is right-positive, `y` is
    /// down-positive, each clamped to `-1...1`. Both are 0 when `faceFound` is false.
    public let x: Double
    public let y: Double
    /// True only when the frame contained a face whose both pupils could be
    /// located — the only condition under which `x`/`y` are a usable estimate.
    public let faceFound: Bool
    /// Vision's face-observation confidence in `0...1`; 0 when no face was
    /// found. Detection confidence, not gaze-angle accuracy.
    public let confidence: Float

    public init(x: Double, y: Double, faceFound: Bool, confidence: Float) {
        self.x = x
        self.y = y
        self.faceFound = faceFound
        self.confidence = confidence
    }

    /// Published for frames without a usable face; `x`/`y` carry no information.
    public static let noFace = GazeSample(x: 0, y: 0, faceFound: false, confidence: 0)
}

/// Front-camera gaze sampler — opt-in, on-device, deliberately coarse.
///
/// Privacy discipline (mirrors `FramePolicy`): camera frames exist only as
/// in-memory `CVPixelBuffer`s for the duration of one Vision pass. They are
/// never written to disk, never logged as images, and never leave the process;
/// only the two-double `GazeSample` is published.
///
/// Accuracy: webcam pupil tracking is region-level at best (~2–5° typical, and
/// only with even lighting and a face-on pose). Treat it as a disambiguator for
/// "that thing I am looking at", never as a precise pointer — assistive
/// hardware eye trackers are the precision path.
public final class GazeSampler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Capture format: VGA at ~10 fps — enough for a coarse estimate, small
    /// enough for per-frame Vision on the sampling queue.
    public static let captureWidth = 640
    public static let captureHeight = 480
    public static let captureFramesPerSecond = 10

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    /// Session configuration/start/stop; never the main actor.
    private let sessionQueue = DispatchQueue(label: "com.clicky.gaze.session")
    /// Video-output delegate callbacks and per-frame Vision work.
    private let samplingQueue = DispatchQueue(label: "com.clicky.gaze.sampling")
    private let lock = NSLock()

    private var _latest: GazeSample?
    private var _onSample: (@Sendable (GazeSample) -> Void)?
    private var isConfigured = false
    private var isRunning = false

    /// Most recent sample, readable from any thread; `nil` until the first
    /// processed frame. The callback below is the push form of the same value.
    public var latest: GazeSample? {
        lock.withLock { _latest }
    }

    /// Called on the internal sampling queue after every processed frame (face
    /// found or not). Set it before `start()`; frames themselves never travel here.
    public var onSample: (@Sendable (GazeSample) -> Void)? {
        get { lock.withLock { _onSample } }
        set { lock.withLock { _onSample = newValue } }
    }

    /// Whether this process currently holds Camera permission.
    public static var hasCameraPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// Requests Camera access when the user has not yet decided; resolves to the
    /// current grant state (no prompt when already decided). Safe from any thread.
    public static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    deinit {
        // Defensive: the session also stops when it deallocates, but clearing the
        // delegate first makes the teardown explicit.
        stop()
    }

    /// Starts capture on the internal queues; idempotent and non-blocking.
    /// No-op without Camera permission, without a camera, or when already running.
    public func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            guard Self.hasCameraPermission else { return }
            self.configureIfNeeded()
            guard !self.session.inputs.isEmpty, !self.session.outputs.isEmpty else { return }
            // (Re)attach the delegate: `stop()` detaches it so a stopped sampler
            // never holds or calls back into a delegate.
            self.videoOutput.setSampleBufferDelegate(self, queue: self.samplingQueue)
            self.session.startRunning()
            self.isRunning = self.session.isRunning
        }
    }

    /// Stops capture. Captures the session and output strongly so it also works
    /// from `deinit`, where `self` may already be the last reference.
    public func stop() {
        let session = self.session
        let output = self.videoOutput
        samplingQueue.async {
            output.setSampleBufferDelegate(nil, queue: nil)
        }
        sessionQueue.async { [weak self] in
            if session.isRunning { session.stopRunning() }
            self?.isRunning = false
        }
    }

    // MARK: - Session configuration

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        // The system default camera is the built-in front camera on a Mac.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            if session.canSetSessionPreset(.vga640x480) {
                session.sessionPreset = .vga640x480
            }
            guard session.canAddInput(input) else { return }
            session.addInput(input)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(videoOutput) else { return }
            session.addOutput(videoOutput)
        } catch {
            // No camera input: gaze stays unavailable and callers fall back to
            // the cursor. Setup errors are never surfaced or logged.
            return
        }
        configureFrameRate(on: device)
    }

    /// Clamps the device to ~`captureFramesPerSecond` instead of forcing a rate
    /// the active format may not support.
    private func configureFrameRate(on device: AVCaptureDevice) {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard let minDuration = ranges.map(\.minFrameDuration).min(),
              let maxDuration = ranges.map(\.maxFrameDuration).max() else { return }
        var target = CMTime(value: 1, timescale: CMTimeScale(Self.captureFramesPerSecond))
        if target < minDuration { target = minDuration }
        if target > maxDuration { target = maxDuration }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.activeVideoMinFrameDuration = target
            device.activeVideoMaxFrameDuration = target
        } catch {
            // Keep the device's default rate; sampling stays correct either way.
        }
    }

    // MARK: - Frame processing

    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // In-memory only: the buffer feeds one Vision pass and is released.
        // Nothing here ever encodes, stores, or logs image data.
        let sample = Self.gazeSample(from: pixelBuffer, mirrored: connection.isVideoMirrored)
        lock.lock()
        _latest = sample
        let callback = _onSample
        lock.unlock()
        callback?(sample)
    }

    private static func gazeSample(from pixelBuffer: CVPixelBuffer, mirrored: Bool) -> GazeSample {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .noFace
        }
        guard let faces = request.results, !faces.isEmpty else { return .noFace }
        let largest = faces.max {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }
        guard let face = largest else { return .noFace }
        guard let landmarks = face.landmarks,
              let leftOffset = pupilOffset(eye: landmarks.leftEye, pupil: landmarks.leftPupil),
              let rightOffset = pupilOffset(eye: landmarks.rightEye, pupil: landmarks.rightPupil) else {
            return GazeSample(x: 0, y: 0, faceFound: false, confidence: face.confidence)
        }
        // Average the eyes, then convert image space to screen space:
        //   * Vision's `normalizedPoints` are face-bounding-box relative with the
        //     origin at the lower-left corner (x right-positive, y up-positive);
        //     Apple documents this on `VNFaceLandmarks2D`.
        //   * x: an unmirrored camera is the mirror of what the user sees, so
        //     looking screen-right moves the pupils image-left; a mirrored
        //     connection already matches the user's view. `connection.isVideoMirrored`
        //     is read per frame, so the sign is never guessed.
        //   * y: looking up moves the pupils image-up, which is negative y-down.
        let imageX = (leftOffset.x + rightOffset.x) / 2
        let imageY = (leftOffset.y + rightOffset.y) / 2
        let screenX = (mirrored ? 1 : -1) * imageX
        let screenY = -imageY
        return GazeSample(x: Double(clamped(screenX)), y: Double(clamped(screenY)),
                          faceFound: true, confidence: face.confidence)
    }

    /// Pupil offset within the eye's bounding box, image space (x right-positive,
    /// y up-positive), roughly `-0.5...0.5`. Nil unless the eye region has a
    /// usable box and the pupil region has at least one point.
    private static func pupilOffset(eye: VNFaceLandmarkRegion2D?,
                                    pupil: VNFaceLandmarkRegion2D?) -> CGPoint? {
        guard let eye, let pupil else { return nil }
        let eyePoints = eye.normalizedPoints
        let pupilPoints = pupil.normalizedPoints
        guard !eyePoints.isEmpty, !pupilPoints.isEmpty else { return nil }
        let minX = eyePoints.map(\.x).min() ?? 0
        let maxX = eyePoints.map(\.x).max() ?? 0
        let minY = eyePoints.map(\.y).min() ?? 0
        let maxY = eyePoints.map(\.y).max() ?? 0
        guard maxX - minX > 0, maxY - minY > 0 else { return nil }
        let pupilX = pupilPoints.map(\.x).reduce(0, +) / CGFloat(pupilPoints.count)
        let pupilY = pupilPoints.map(\.y).reduce(0, +) / CGFloat(pupilPoints.count)
        return CGPoint(x: (pupilX - minX) / (maxX - minX) - 0.5,
                       y: (pupilY - minY) / (maxY - minY) - 0.5)
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, -1), 1)
    }

    // MARK: - Screen mapping

    /// Maps a coarse gaze offset to a global screen point (AX/CG space, y-down):
    /// `screenBounds.center + offset * gain * halfExtent`, clamped to the bounds.
    /// Pure and deterministic — the caller supplies the display to map onto
    /// (`CGDisplayBounds(CGMainDisplayID())` gives the same space CGEvent uses).
    public static func screenPoint(for sample: GazeSample, gain: Double, screenBounds: CGRect) -> CGPoint? {
        guard sample.faceFound, screenBounds.width > 0, screenBounds.height > 0,
              gain.isFinite, gain > 0 else { return nil }
        let point = CGPoint(
            x: screenBounds.midX + CGFloat(sample.x * gain) * screenBounds.width / 2,
            y: screenBounds.midY + CGFloat(sample.y * gain) * screenBounds.height / 2)
        return CGPoint(x: min(max(point.x, screenBounds.minX), screenBounds.maxX),
                       y: min(max(point.y, screenBounds.minY), screenBounds.maxY))
    }
}
