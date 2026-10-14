import AVFoundation
import CoreImage
import AppWorkflow

/// All session configuration, frame analysis and lifecycle changes run on one serial queue.
final class ScanCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Status: Equatable, Sendable {
        case stopped, requesting, running, denied, unavailable, interrupted, failed
        var message: String {
            switch self {
            case .stopped: return "Camera paused."
            case .requesting: return "Requesting camera access…"
            case .running: return ""
            case .denied: return "Allow camera access in Settings to scan your cube."
            case .unavailable: return "A rear camera is needed. You can still enter your cube manually."
            case .interrupted: return "Camera interrupted. Resume when you’re ready."
            case .failed: return "The camera could not start. Try resuming the scan."
            }
        }
    }
    let session = AVCaptureSession()
    var onFrame: (@Sendable (FaceMeasurement?, Double, UUID) -> Void)?
    var onStatus: (@Sendable (Status) -> Void)?
    private let queue = DispatchQueue(label: "com.serendipitylabs.twisttutor.camera", qos: .userInitiated)
    private let analyzer = FaceImageAnalyzer()
    private var token: UUID?
    private var requested = false
    private var configured = false
    private var lastAnalysis = -Double.infinity
    #if DEBUG
    private var lastDiagnostic = -Double.infinity
    #endif
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] note in
                let status: Status = note.name == AVCaptureSession.wasInterruptedNotification ? .interrupted : .failed
                self?.queue.async { [weak self] in
                    guard let self, self.requested else { return }
                    self.token = nil; self.requested = false
                    self.session.stopRunning(); self.onStatus?(status)
                }
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start(generation: UUID?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.requested = true; self.token = generation
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: self.configureAndStart()
            case .notDetermined:
                self.onStatus?(.requesting)
                AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                    guard let self else { return }
                    self.queue.async {
                        if !allowed { self.requested = false; self.token = nil; self.onStatus?(.denied); return }
                        guard self.requested else { return }
                        self.configureAndStart()
                    }
                }
            default: self.requested = false; self.token = nil; self.onStatus?(.denied)
            }
        }
    }
    func setGeneration(_ generation: UUID?) {
        queue.async { [weak self] in self?.token = generation; self?.lastAnalysis = -Double.infinity }
    }
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.requested = false; self.token = nil
            self.session.stopRunning(); self.onStatus?(.stopped)
        }
    }
    private func configureAndStart() {
        guard requested else { return }
        #if targetEnvironment(simulator)
        requested = false; token = nil
        onStatus?(.unavailable)
        return
        #else
        if !configured {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else { onStatus?(.unavailable); return }
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: queue)
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            guard session.canAddInput(input) else { session.commitConfiguration(); onStatus?(.failed); return }
            session.addInput(input)
            guard session.canAddOutput(output) else {
                session.removeInput(input); session.commitConfiguration(); onStatus?(.failed); return
            }
            session.addOutput(output)
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            session.commitConfiguration(); configured = true
        }
        session.startRunning()
        onStatus?(session.isRunning ? .running : .failed)
        #endif
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard requested, let token, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time - lastAnalysis >= 0.12 else { return }
        lastAnalysis = time
        #if DEBUG
        let started = CFAbsoluteTimeGetCurrent()
        #endif
        let result = try? analyzer.analyze(CIImage(cvPixelBuffer: pixelBuffer))
        #if DEBUG
        if time - lastDiagnostic >= 2 {
            lastDiagnostic = time
            let milliseconds = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            if let result {
                print(String(format: "[CubeScan] analysis=%dms area=%.3f grid=%.3f sharpness=%.5f dark=%.3f glare=%.3f spread=%.3f",
                             milliseconds, result.quad.area, result.gridEvidence, result.sharpness,
                             result.darkFraction, result.clippedFraction, result.samples.map(\.spread).max() ?? 0))
            } else {
                print("[CubeScan] analysis=\(milliseconds)ms; no complete face detected")
            }
        }
        #endif
        onFrame?(result, time, token)
    }
}
