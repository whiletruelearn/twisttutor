import SwiftUI
import CubeCore
import CubeSolver
import AppWorkflow

/// M4 integration harness. Full instructional solving and recovery UX follows in M7.
struct ManualSolutionView: View {
    let solution: VerifiedSolution
    let onComplete: () -> Void
    @ScaledMetric private var stepStripHeight = 88
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
                        Text("\(stepAction): \(move.notation)").font(.title.bold())
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
                Text("This test flow animates the entered cube. Physical-cube guidance and mistake recovery come in a later update.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if !solution.moves.isEmpty { stepStrip }
                HStack {
                    Button("Previous step", systemImage: "backward.end.fill") { scene.previousStep() }
                        .disabled(!scene.playback.canGoBack || scene.isAutoPlaying)
                        .accessibilityIdentifier("previousStep")
                    if scene.playback.isBusy || scene.isAutoPlaying {
                        Button("Pause", systemImage: "pause.fill") { scene.cancel() }.buttonStyle(.borderedProminent)
                    } else if scene.playback.isSolutionComplete {
                        Label("Verified solved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Next move") { scene.nextStep() }.buttonStyle(.bordered)
                        Button("Play solution", systemImage: "play.fill") { scene.playSolution() }.buttonStyle(.borderedProminent)
                    }
                }
            }.padding().frame(maxWidth: .infinity).background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle("Manual solve").navigationBarTitleDisplayMode(.inline)
        .onAppear { if scene.playback.isSolutionComplete { onComplete() } }
        .onChange(of: scene.playback.isSolutionComplete) { _, complete in if complete { onComplete() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scene.cancel() } }
        .onDisappear { scene.cancel() }
    }

    private var stepAction: String {
        if scene.playback.activeTurn?.isBackward == true { return "Undoing" }
        if scene.playback.activeTurn?.isReplay == true { return "Replaying" }
        return scene.playback.isBusy ? "Playing" : "Next"
    }

    private var stepStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scene.playback.currentStepIndex.map {
                "\(stepAction) step \($0 + 1) of \(solution.moves.count)"
            } ?? "All \(solution.moves.count) steps completed")
                .font(.subheadline.bold()).accessibilityIdentifier("currentSolutionStep")
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(solution.moves.indices, id: \.self) { index in
                            let current = scene.playback.currentStepIndex == index
                            let completed = index < scene.playback.completedMoveCount
                            VStack(spacing: 4) {
                                Text("\(index + 1)").font(.caption)
                                Text(solution.moves[index].notation).font(.body.monospaced().bold())
                                Text(current ? "Current" : completed ? "Done" : "Later").font(.caption2)
                            }
                            .frame(minWidth: 56).padding(8)
                            .background(current ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(current ? Color.white : Color.primary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Step \(index + 1), \(solution.moves[index].notation), \(current ? "current" : completed ? "completed" : "upcoming")")
                            .id(index)
                        }
                    }
                }
                .frame(height: stepStripHeight)
                .onChange(of: scene.playback.currentStepIndex, initial: true) { _, index in
                    proxy.scrollTo(index ?? solution.moves.count - 1, anchor: .center)
                }
            }
        }
    }

    private func direction(_ amount: TurnAmount) -> String {
        switch amount {
        case .clockwise: "clockwise"
        case .counterclockwise: "counterclockwise"
        case .half: "half turn"
        }
    }
}
