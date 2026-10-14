import SwiftUI
import CubeCore
import CubeSolver
import AppWorkflow

/// M4 integration harness. Full instructional solving and recovery UX follows in M7.
struct ManualSolutionView: View {
    let solution: VerifiedSolution
    let onComplete: () -> Void
    @State private var scene: CubeScene
    @Environment(\.scenePhase) private var scenePhase

    init(solution: VerifiedSolution, onComplete: @escaping () -> Void) {
        self.solution = solution
        self.onComplete = onComplete
        let playback = CubePlayback(solution: solution)
        let scene = CubeScene(playback: playback)
        if let move = playback.nextMove { scene.selectedFace = move.face; scene.amount = move.amount }
        _scene = State(initialValue: scene)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(scene.playback.isSolutionComplete ? "Cube solved" : "Your verified solution")
                    .font(.title2.bold())
                Text(solution.moves.isEmpty ? "Your entry is already solved. No turns needed." : "\(scene.playback.completedMoveCount) of \(solution.moves.count) moves completed")
                    .foregroundStyle(.secondary).accessibilityIdentifier("solutionProgress")
                CubeViewport(scene: scene).frame(height: 300)
                Button("Reset view", systemImage: "viewfinder") { scene.resetView() }
                if let move = scene.playback.activeTurn?.move ?? scene.playback.nextMove {
                    VStack(spacing: 6) {
                        Text("\(scene.playback.isBusy ? "Playing" : "Next"): \(move.notation)").font(.title.bold())
                        Text("\(move.face.title) face · \(direction(move.amount))")
                        Text("Viewed looking straight at that face.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Toggle("Slow motion", isOn: $scene.slow).disabled(scene.playback.isBusy)
                HStack {
                    Button("Replay last", systemImage: "arrow.counterclockwise") { scene.replay() }
                        .disabled(scene.playback.lastTurn == nil || scene.playback.isBusy || scene.isAutoPlaying)
                    Spacer()
                    Button("Restart") { scene.restartSolution() }
                }
                Text("Move sequence").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Text(solution.moves.isEmpty ? "No moves" : MoveNotation.format(solution.moves))
                    .font(.body.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Text("This test flow animates the entered cube. Physical-cube guidance and mistake recovery come in a later update.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            HStack {
                if scene.playback.isBusy || scene.isAutoPlaying {
                    Button("Pause", systemImage: "pause.fill") { scene.cancel() }.buttonStyle(.borderedProminent)
                } else if scene.playback.isSolutionComplete {
                    Label("Verified solved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Next move") { scene.nextStep() }.buttonStyle(.bordered)
                    Button("Play solution", systemImage: "play.fill") { scene.playSolution() }.buttonStyle(.borderedProminent)
                }
            }.padding().frame(maxWidth: .infinity).background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle("Manual solve").navigationBarTitleDisplayMode(.inline)
        .onAppear { if scene.playback.isSolutionComplete { onComplete() } }
        .onChange(of: scene.playback.isSolutionComplete) { _, complete in if complete { onComplete() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scene.cancel() } }
        .onDisappear { scene.cancel() }
    }

    private func direction(_ amount: TurnAmount) -> String {
        switch amount {
        case .clockwise: "clockwise"
        case .counterclockwise: "counterclockwise"
        case .half: "half turn"
        }
    }
}
