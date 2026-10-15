import SwiftUI
import RealityKit
import Combine
import CubeCore
import AppWorkflow

/// Reusable, non-AR cube viewport. Camera and highlights never mutate CubeState.
@MainActor @Observable
final class CubeScene {
    let playback: CubePlayback
    var selectedIndex: Int?
    var allowsOrbit = true
    var showsTurnGuide = true
    var sourceHighlights: Set<Int> = []
    var destinationHighlights: Set<Int> = []
    var entryColors: [CubeColorID?]?
    @ObservationIgnored var onPaint: ((Int) -> Void)?
    @ObservationIgnored private var focusedFace: CubeFaceID?

    func showEntry(_ colors: [CubeColorID?]) {
        guard colors.count == 54 else { return }
        entryColors = colors
        rebuild(playback.cube)
    }

    func focus(on face: CubeFaceID) {
        selectedFace = face
        focusedFace = face
        updateCamera()
        rebuild(playback.cube)
    }

    var selectedFace: CubeFaceID = .front
    var highlightPiece = false
    private(set) var isAutoPlaying = false
    var slow = false
    var amount: TurnAmount = .clockwise
    private(set) var viewRevision = 0
    @ObservationIgnored private weak var view: ARView?
    @ObservationIgnored private let anchor = AnchorEntity(world: .zero)
    @ObservationIgnored private let cubeRoot = Entity()
    @ObservationIgnored private let camera = PerspectiveCamera()
    @ObservationIgnored private var cubies: [Entity] = []
    @ObservationIgnored private var cameraUpdates: (any Cancellable)?
    @ObservationIgnored private var animation: Task<Void, Never>?
    @ObservationIgnored private var yaw: Float = .pi / 4
    @ObservationIgnored private var pitch: Float = .pi / 6

    init(cube: CubeState = try! .solved()) { playback = CubePlayback(cube: cube) }
    init(playback: CubePlayback) { self.playback = playback }

    func nextStep() {
        guard let turn = playback.beginNext() else { isAutoPlaying = false; return }
        selectedFace = turn.move.face
        amount = turn.move.amount
        animate(turn)
    }

    func confirmNextWithoutAnimation() {
        guard let turn = playback.beginNext() else { return }
        _ = playback.complete(turn.id)
        if let next = playback.nextMove { selectedFace = next.face; amount = next.amount }
        rebuild(playback.cube)
    }

    func previousStep() {
        guard !isAutoPlaying, let turn = playback.beginPrevious() else { return }
        selectedFace = turn.move.face
        amount = turn.move.amount
        animate(turn)
    }

    func playSolution() {
        guard !playback.isBusy, playback.nextMove != nil else { return }
        isAutoPlaying = true
        nextStep()
    }

    func restartSolution() {
        cancel()
        playback.restartSolution()
        if let next = playback.nextMove { selectedFace = next.face; amount = next.amount }
        rebuild(playback.cube)
    }

    func attach(_ view: ARView) {
        self.view = view
        view.environment.background = .color(CubeStyle.stageUIColor)
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain]
        view.scene.addAnchor(anchor)
        anchor.addChild(cubeRoot)
        anchor.addChild(camera)
        camera.camera.fieldOfViewInDegrees = 42
        updateCamera()
        // A navigation destination can attach before its world anchor is active.
        // Derive the camera pose during scene updates as well as gesture changes.
        cameraUpdates?.cancel()
        cameraUpdates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            self?.updateCamera()
        }
        rebuild(playback.cube)
    }

    func detach() {
        cameraUpdates?.cancel(); cameraUpdates = nil
        cancel()
        anchor.removeFromParent()
        view = nil
    }

    func orbit(x: Float, y: Float) {
        guard allowsOrbit else { return }
        if let face = focusedFace {
            let axis = CubeRenderLayout.axis(for: face)
            yaw = atan2(axis.x, axis.z)
            pitch = asin(axis.y * 0.98)
            focusedFace = nil
        }
        yaw -= x * 0.008
        pitch = min(1.45, max(-1.45, pitch + y * 0.008))
        updateCamera()
    }

    func resetView() {
        focusedFace = nil
        yaw = .pi / 4; pitch = .pi / 6
        updateCamera()
        viewRevision += 1
    }

    func updateCamera() {
        if let face = focusedFace {
            let location = CubeRenderLayout.facelets[face.rawValue * 9 + 4]
            let context: Float = face == .up || face == .down ? 2.2 : 0.8
            camera.look(at: .zero, from: location.normal * 6.6 + location.right * context - location.down * context, upVector: -location.down, relativeTo: anchor)
            return
        }
        let radius: Float = 8
        camera.look(at: .zero, from: [radius * cos(pitch) * sin(yaw), radius * sin(pitch), radius * cos(pitch) * cos(yaw)], relativeTo: anchor)
    }

    func select(at point: CGPoint) {
        guard !playback.isBusy, let entity = view?.entity(at: point),
              entity.name.hasPrefix("sticker-"), let index = Int(entity.name.dropFirst(8)) else { return }
        if let onPaint {
            // Guided entry paints only the named face, even after orbiting.
            guard index / 9 == selectedFace.rawValue else { return }
            onPaint(index)
            return
        }
        guard entryColors == nil else { return }
        selectedIndex = index
        selectedFace = CubeFaceID(rawValue: index / 9)!
        rebuild(playback.cube)
    }

    func refreshHighlights() {
        guard !playback.isBusy else { return }
        rebuild(playback.cube)
    }

    func loadExample(scrambled: Bool) {
        cancel()
        let solved = try! CubeState.solved()
        let moves = try! MoveNotation.parse("R U R' U' F2 D L2 B")
        playback.replace(with: scrambled ? solved.applying(moves) : solved)
        selectedIndex = nil
        rebuild(playback.cube)
    }

    func turn() {
        guard let turn = playback.begin(CubeMove(selectedFace, amount)) else { return }
        animate(turn)
    }

    func replay() {
        guard let turn = playback.replay() else { return }
        selectedFace = turn.move.face
        amount = turn.move.amount
        animate(turn)
    }

    func cancel() {
        isAutoPlaying = false
        animation?.cancel(); animation = nil
        playback.cancel()
        rebuild(playback.cube)
    }

    private func animate(_ turn: CubePlayback.Turn) {
        selectedIndex = nil
        rebuild(turn.source)
        let pivot = Entity()
        cubeRoot.addChild(pivot)
        let axis = CubeRenderLayout.axis(for: turn.move.face)
        for cubie in cubies where simd_dot(cubie.position, axis) > 0.5 {
            pivot.addChild(cubie, preservingWorldTransform: true)
        }
        let duration = slow ? 1.0 : 0.42
        // Sample the full angle instead of quaternion interpolation, which can choose the
        // wrong direction at 180 degrees. Rebuild from canonical state at every endpoint.
        animation = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            while !Task.isCancelled {
                let elapsed = start.duration(to: clock.now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let progress = min(1, seconds / duration)
                let eased = Float(progress * progress * (3 - 2 * progress))
                pivot.orientation = simd_quatf(angle: CubeRenderLayout.angle(for: turn.move) * eased, axis: axis)
                if progress >= 1 { break }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
            guard !Task.isCancelled, let self, self.playback.complete(turn.id) else { return }
            if let next = self.playback.nextMove { self.selectedFace = next.face; self.amount = next.amount }
            self.rebuild(self.playback.cube)
            self.animation = nil
            if self.isAutoPlaying { self.nextStep() }
        }
    }

    private func rebuild(_ state: CubeState) {
        cubeRoot.children.removeAll()
        cubies.removeAll()
        let positions = Set(CubeRenderLayout.facelets.map(\.position))
        let selectedPosition = selectedIndex.map { CubeRenderLayout.facelets[$0].position }
        for position in positions {
            let cubie = Entity()
            cubie.position = position
            let body = ModelEntity(mesh: .generateBox(size: 0.97, cornerRadius: 0.07), materials: [UnlitMaterial(color: UIColor(white: 0.12, alpha: 1))])
            body.generateCollisionShapes(recursive: false)
            cubie.addChild(body)
            cubeRoot.addChild(cubie)
            cubies.append(cubie)
            for location in CubeRenderLayout.facelets where location.position == position {
                let isHighlighted = highlightPiece && selectedPosition != nil
                    ? selectedPosition == position : location.index / 9 == selectedFace.rawValue
                let border: UIColor = sourceHighlights.contains(location.index) ? .white
                    : destinationHighlights.contains(location.index) ? UIColor(red: 0.15, green: 0.7, blue: 1, alpha: 1)
                    : entryColors == nil && showsTurnGuide && isHighlighted ? .white : UIColor(white: 0.08, alpha: 1)
                let backing = ModelEntity(mesh: .generateBox(width: 0.88, height: 0.88, depth: 0.015, cornerRadius: 0.055), materials: [UnlitMaterial(color: border)])
                backing.position = location.normal * 0.489
                backing.orientation = simd_quatf(from: SIMD3<Float>(0,0,1), to: location.normal)
                cubie.addChild(backing)
                let sticker = ModelEntity(mesh: .generateBox(width: 0.79, height: 0.79, depth: 0.02, cornerRadius: 0.045), materials: [UnlitMaterial(color: entryColors.map { $0[location.index]?.uiColor ?? UIColor(white: 0.72, alpha: 1) } ?? state.stickers[location.index].colorID.uiColor)])
                sticker.position = location.normal * 0.505
                sticker.orientation = backing.orientation
                sticker.name = "sticker-\(location.index)"
                sticker.generateCollisionShapes(recursive: false)
                cubie.addChild(sticker)
                if location.index % 9 == 4 {
                    let mesh = MeshResource.generateText(CubeFaceID(rawValue: location.index / 9)!.notation,
                        extrusionDepth: 0.001, font: .systemFont(ofSize: 0.23, weight: .bold))
                    let label = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .black)])
                    let basis = simd_float3x3(columns: (location.right, -location.down, location.normal))
                    label.orientation = simd_quatf(basis)
                    let bounds = mesh.bounds
                    label.position = location.normal * 0.522 - basis * SIMD3(bounds.center.x, bounds.center.y, 0)
                    cubie.addChild(label)
                }
            }
        }
        if entryColors == nil && showsTurnGuide { addDirectionArrow() }
    }

    private func addDirectionArrow() {
        let move = playback.activeTurn?.move ?? CubeMove(selectedFace, amount)
        let face = CubeRenderLayout.facelets[move.face.rawValue * 9 + 4]
        let sign: Float = move.amount == .counterclockwise ? -1 : 1
        let material = UnlitMaterial(color: UIColor(red: 0.15, green: 0.45, blue: 0.82, alpha: 1))
        func point(_ angle: Float) -> SIMD3<Float> {
            face.normal * 1.55 + (face.right * cos(angle) + face.down * sin(angle)) * 1.65
        }
        let steps = 24
        for step in 0..<steps {
            let start = point(sign * Float(step) / Float(steps) * .pi * 0.8 - .pi * 0.9)
            let end = point(sign * Float(step + 1) / Float(steps) * .pi * 0.8 - .pi * 0.9)
            let segment = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.04, simd_distance(start, end) + 0.015, 0.04)), materials: [material])
            segment.position = (start + end) / 2
            segment.orientation = simd_quatf(from: SIMD3(0,1,0), to: simd_normalize(end - start))
            cubeRoot.addChild(segment)
        }
        let angle = sign * .pi * 0.8 - .pi * 0.9
        let tangent = sign * (-face.right * sin(angle) + face.down * cos(angle))
        let tip = point(angle) + tangent * 0.08
        let radial = face.right * cos(angle) + face.down * sin(angle)
        for side: Float in [-1, 1] {
            let end = tip - tangent * 0.24 + radial * side * 0.13
            let wing = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.05, simd_distance(tip, end), 0.05)), materials: [material])
            wing.position = (tip + end) / 2
            wing.orientation = simd_quatf(from: SIMD3(0,1,0), to: simd_normalize(end - tip))
            cubeRoot.addChild(wing)
        }
    }
}

private final class CubeRenderView: ARView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0 && bounds.height > 0 { onLayout?() }
    }
}

struct CubeViewport: UIViewRepresentable {
    let scene: CubeScene

    func makeUIView(context: Context) -> ARView {
        let view = CubeRenderView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.onLayout = { [weak scene = scene] in scene?.updateCamera() }
        scene.attach(view)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        view.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Interactive cube. Drag to orbit. Tap a sticker to inspect it."
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Rotate view left", target: context.coordinator, selector: #selector(Coordinator.rotateLeft)),
            UIAccessibilityCustomAction(name: "Rotate view right", target: context.coordinator, selector: #selector(Coordinator.rotateRight)),
            UIAccessibilityCustomAction(name: "Rotate view up", target: context.coordinator, selector: #selector(Coordinator.rotateUp)),
            UIAccessibilityCustomAction(name: "Rotate view down", target: context.coordinator, selector: #selector(Coordinator.rotateDown))
        ]
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        view.environment.background = .color(CubeStyle.stageUIColor)
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) { coordinator.scene.detach() }
    func makeCoordinator() -> Coordinator { Coordinator(scene: scene) }

    @MainActor final class Coordinator: NSObject {
        let scene: CubeScene
        init(scene: CubeScene) { self.scene = scene }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let delta = gesture.translation(in: gesture.view)
            scene.orbit(x: Float(delta.x), y: Float(delta.y))
            gesture.setTranslation(.zero, in: gesture.view)
        }
        @objc func rotateLeft() -> Bool { scene.orbit(x: 100, y: 0); return true }
        @objc func rotateRight() -> Bool { scene.orbit(x: -100, y: 0); return true }
        @objc func rotateUp() -> Bool { scene.orbit(x: 0, y: 80); return true }
        @objc func rotateDown() -> Bool { scene.orbit(x: 0, y: -80); return true }
        @objc func tap(_ gesture: UITapGestureRecognizer) { scene.select(at: gesture.location(in: gesture.view)) }
    }
}

extension CubeColorID {
    var uiColor: UIColor {
        switch self {
        case .white: UIColor(white: 0.95, alpha: 1)
        case .red: UIColor(red: 0.85, green: 0.12, blue: 0.14, alpha: 1)
        case .green: UIColor(red: 0.06, green: 0.61, blue: 0.32, alpha: 1)
        case .yellow: UIColor(red: 1, green: 0.82, blue: 0.06, alpha: 1)
        case .orange: UIColor(red: 1, green: 0.39, blue: 0.04, alpha: 1)
        case .blue: UIColor(red: 0.06, green: 0.34, blue: 0.89, alpha: 1)
        }
    }
}

extension CubeFaceID {
    var title: String { ["Up", "Right", "Front", "Down", "Left", "Back"][rawValue] }
}
