import SwiftUI
import AVFoundation
import AppWorkflow
import CubeCore

@MainActor @Observable
final class ScanScreenModel {
    let capture = ScanCapture()
    private(set) var status: ScanCamera.Status = .stopped
    @ObservationIgnored let camera = ScanCamera()
    @ObservationIgnored var visible = false
    @ObservationIgnored var portrait = true
    @ObservationIgnored var active = true
    init() {
        camera.onFrame = { [weak self] measurement, time, generation in
            Task { @MainActor [weak self] in
                guard let self, self.visible, self.active, self.portrait, self.status == .running else { return }
                let previous = self.capture.faces.count
                self.capture.receive(measurement, at: time, generation: generation)
                if self.capture.faces.count != previous {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    self.synchronize()
                }
            }
        }
        camera.onStatus = { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.status = status
                if status != .running { self.capture.invalidateFrames() }
                else if self.visible && self.active && self.portrait { self.synchronize() }
                else { self.camera.stop() }
            }
        }
    }
    func resume() {
        guard visible, active, portrait, !capture.complete else { return }
        capture.invalidateFrames()
        camera.start(generation: capture.acceptingFrames ? capture.generation : nil)
    }
    func pause() { capture.invalidateFrames(); camera.stop() }
    func synchronize() {
        if capture.complete { camera.stop() }
        else { camera.setGeneration(capture.acceptingFrames ? capture.generation : nil) }
    }
    func next() { capture.continueScanning(); synchronize() }
    func retake(_ index: Int) { capture.retake(from: index); resume() }
}

struct ScanView: View {
    @State private var model = ScanScreenModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCancel = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    if model.capture.complete { summary }
                    else {
                        Text("Face \(model.capture.faces.count + 1) of 6 · \(model.capture.currentFace.title)")
                            .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        if geometry.size.width > geometry.size.height {
                            ContentUnavailableView("Hold your device upright", systemImage: "iphone", description: Text("Scan in portrait so the cube’s top stays aligned with the guide."))
                        } else if model.status == .unavailable || model.status == .denied {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 56)).foregroundStyle(.secondary)
                                .frame(height: 160).accessibilityHidden(true)
                        } else {
                            CameraPreview(session: model.camera.session)
                                .frame(width: min(max(1, geometry.size.width - 40), 202.5),
                                       height: min(max(1, geometry.size.width - 40), 202.5) * 16 / 9)
                                .overlay { alignmentGrid }
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .accessibilityLabel("Camera preview. Align one whole cube face with the grid.")
                        }
                        if model.status != .running {
                            Text(model.status.message).multilineTextAlignment(.center)
                            if model.status == .denied {
                                Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                            } else if model.status != .requesting && model.status != .unavailable {
                                Button("Resume camera") { model.resume() }.buttonStyle(.bordered)
                            }
                            if model.status == .unavailable || model.status == .denied {
                                NavigationLink("Enter cube manually") { ManualEntryView() }.buttonStyle(.bordered)
                            }
                        } else if model.capture.awaitingNext {
                            if model.capture.guidance == .captured {
                                Label("Face captured", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Text("Check the orientation before continuing.")
                            }
                            Button("I’m ready for \(model.capture.currentFace.title.lowercased())") { model.next() }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Text(model.capture.guidance.rawValue).font(.headline).multilineTextAlignment(.center)
                                .accessibilityIdentifier("scanGuidance")
                            ProgressView(value: model.capture.stability).accessibilityLabel("Holding steady")
                        }
                        if model.status != .unavailable && model.status != .denied { instructions }
                        if !model.capture.faces.isEmpty {
                            Button("Retake previous face") { model.retake(model.capture.faces.count - 1) }
                        }
                    }
                    Text("Your camera stays on your device. No photos are saved.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .onAppear { model.portrait = geometry.size.width <= geometry.size.height; model.visible = true; model.active = scenePhase == .active; model.resume() }
            .onChange(of: geometry.size.width > geometry.size.height) { _, landscape in
                model.portrait = !landscape
                if landscape { model.pause() } else { model.resume() }
            }
        }
        .navigationTitle("Scan your cube").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { model.pause(); confirmCancel = true } } }
        .confirmationDialog("Discard this scan?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Discard scan", role: .destructive) { model.pause(); model.capture.reset(); dismiss() }
        }
        .onDisappear { model.visible = false; model.pause() }
        .onChange(of: scenePhase) { _, phase in
            model.active = phase == .active
            if phase != .active { model.pause() }
            // Resume is explicit after an interruption: never silently capture a new orientation.
        }
    }
    private var alignmentGrid: some View {
        GeometryReader { proxy in
            let side = proxy.size.width * 0.76
            Path { path in
                let x = (proxy.size.width - side) / 2, y = (proxy.size.height - side) / 2
                path.addRect(CGRect(x: x, y: y, width: side, height: side))
                for n in 1...2 {
                    let offset = side * CGFloat(n) / 3
                    path.move(to: CGPoint(x: x + offset, y: y)); path.addLine(to: CGPoint(x: x + offset, y: y + side))
                    path.move(to: CGPoint(x: x, y: y + offset)); path.addLine(to: CGPoint(x: x + side, y: y + offset))
                }
            }.stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [7, 5])).shadow(color: .black, radius: 2)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
    private var instructions: some View {
        VStack(spacing: 8) {
            RotationGuide(face: model.capture.currentFace)
            Text(instruction).font(.subheadline).multilineTextAlignment(.center)
            Text("Rotate the whole cube, not an individual layer.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var instruction: String {
        switch model.capture.currentFace {
        case .front: return "Choose a front face. Remember which face is on top. Keep it upward for all four side faces."
        case .right: return "Keep the original top facing up. Turn the whole cube so its original right face faces the camera."
        case .back: return "Keep the original top facing up. Turn in the same direction to show the back face."
        case .left: return "Keep the original top facing up. Turn in the same direction to show the left face."
        case .up: return "Return to the original front. Tip the top toward the camera. The original BACK edge must be at the top of the image."
        case .down: return "Return to the original front again. Tip the bottom toward the camera. The original FRONT edge must be at the top of the image."
        }
    }
    private var summary: some View {
        VStack(spacing: 16) {
            Label("Six faces captured", systemImage: "checkmark.circle.fill").font(.title2.bold())
            Text("Review the sampled colors below. Solving from camera scans is not available yet.")
                .multilineTextAlignment(.center)
            ForEach(Array(model.capture.faces.enumerated()), id: \.offset) { index, face in
                HStack {
                    VStack(alignment: .leading) {
                        Text(face.face.title).font(.headline)
                        Button("Retake from here") { model.retake(index) }
                            .accessibilityLabel("Retake from \(face.face.title)")
                    }
                    Spacer()
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 3), count: 3), spacing: 3) {
                        ForEach(Array(face.canonicalSamples.enumerated()), id: \.offset) { i, sample in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(red: sample.rgb.red, green: sample.rgb.green, blue: sample.rgb.blue))
                                .frame(width: 24, height: 24)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary, lineWidth: 0.5))
                                .accessibilityLabel("\(face.face.title) sticker \(i + 1), sampled")
                        }
                    }.fixedSize()
                }
            }
            Button("Finish") { model.pause(); dismiss() }.buttonStyle(.borderedProminent)
        }
    }
}

private struct RotationGuide: View {
    let face: CubeFaceID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    var body: some View {
        VStack(spacing: 4) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let elapsed = max(0, timeline.date.timeIntervalSince(started)).truncatingRemainder(dividingBy: 3)
                let progress = reduceMotion ? 1 : min(1, elapsed / 1.5)
                Canvas { context, size in
                    draw(context: &context, size: size, progress: progress)
                }
            }.frame(height: 112).accessibilityHidden(true)
            Text(face == .up ? "Back edge at top" : face == .down ? "Front edge at top" : "Original top stays up")
                .font(.caption.bold())
        }.onChange(of: face) { _, _ in started = Date() }
    }
    private func draw(context: inout GraphicsContext, size: CGSize, progress: Double) {
        let angle = rotation(progress: progress)
        func rotate(_ p: SIMD3<Float>) -> SIMD3<Double> {
            let x = Double(p.x), y = Double(p.y), z = Double(p.z)
            let c = cos(angle), s = sin(angle)
            if face == .up || face == .down { return SIMD3(x, c * y - s * z, s * y + c * z) }
            return SIMD3(c * x + s * z, y, -s * x + c * z)
        }
        func project(_ p: SIMD3<Double>) -> CGPoint {
            let scale = 32 / (1 - p.z / 6)
            return CGPoint(x: size.width / 2 + p.x * scale, y: size.height / 2 - p.y * scale)
        }
        for side in CubeFaceID.allCases {
            let f = CubeRenderLayout.facelets[side.rawValue * 9 + 4]
            guard rotate(f.normal).z > 0.01 else { continue }
            let corners: [SIMD3<Float>] = [f.position - f.right - f.down, f.position + f.right - f.down,
                           f.position + f.right + f.down, f.position - f.right + f.down]
            var path = Path()
            path.move(to: project(rotate(corners[0])))
            for corner in corners.dropFirst() { path.addLine(to: project(rotate(corner))) }
            path.closeSubpath()
            let fill: Color = side == face ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12)
            context.fill(path, with: .color(fill))
            context.stroke(path, with: .color(.primary), lineWidth: 1.5)
            context.draw(Text(side.notation).font(.headline), at: project(rotate(f.position)))
        }
    }
    private func rotation(progress: Double) -> Double {
        switch face {
        case .front: return 0
        case .right: return -progress * .pi / 2
        case .back: return -(1 + progress) * .pi / 2
        case .left: return -(2 + progress) * .pi / 2
        case .up: return progress * .pi / 2
        case .down: return -progress * .pi / 2
        }
    }
}

private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(); view.backgroundColor = .black
        view.previewLayer.session = session; view.previewLayer.videoGravity = .resizeAspect
        return view
    }
    func updateUIView(_ view: CameraPreviewView, context: Context) { view.setNeedsLayout() }
    static func dismantleUIView(_ view: CameraPreviewView, coordinator: ()) { view.previewLayer.session = nil }
}
