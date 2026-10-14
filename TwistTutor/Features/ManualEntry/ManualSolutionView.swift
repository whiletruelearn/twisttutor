import SwiftUI
import CubeCore
import CubeSolver
import AppWorkflow

/// M4 integration harness. Full instructional solving and recovery UX follows in M7.
struct ManualSolutionView: View {
    let solution: VerifiedSolution
    let onComplete: () -> Void
    @ScaledMetric private var stepStripHeight = 72
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

    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text(scene.playback.isSolutionComplete ? "You did it." : "One twist at a time.")
                            .font(.title2.bold()).fontDesign(.rounded)
                        Spacer()
                        Text("\(scene.playback.completedMoveCount) / \(solution.moves.count)")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(CubeStyle.secondary)
                            .accessibilityIdentifier("solutionProgress")
                    }.padding(24)
                    CubeViewport(scene: scene)
                        .frame(height: max(220, geometry.size.height - (textSize.isAccessibilitySize ? 440 : 330)))
                        .overlay(alignment: .topTrailing) {
                            Button { scene.resetView() } label: {
                                Image(systemName: "viewfinder").font(.title3).frame(width: 48, height: 48)
                                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityLabel("Reset cube view").padding(.trailing, 20)
                        }
                    VStack(spacing: 14) {
                        if let move = scene.playback.activeTurn?.move ?? scene.playback.nextMove {
                            HStack(alignment: .top, spacing: 14) {
                                Text(move.notation).font(.largeTitle.bold()).fontDesign(.rounded)
                                    .frame(minWidth: 54)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(stepAction): \(move.face.title.lowercased()) face").font(.headline)
                                    Text("Turn \(direction(move.amount)), looking at that face.")
                                        .font(.subheadline).foregroundStyle(Color(white: 0.35))
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Label("Your cube is solved", systemImage: "checkmark.circle.fill").font(.title2.bold()).foregroundStyle(.green)
                        }
                        if !solution.moves.isEmpty { stepStrip }
                        HStack(spacing: 12) {
                            Button { scene.previousStep() } label: {
                                Image(systemName: "backward.end.fill").frame(width: 48, height: 52)
                            }.disabled(!scene.playback.canGoBack || scene.isAutoPlaying)
                                .accessibilityLabel("Previous step").accessibilityIdentifier("previousStep")
                            if scene.playback.isBusy || scene.isAutoPlaying {
                                Button { scene.cancel() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                                    .buttonStyle(CubePrimaryButton())
                            } else if !scene.playback.isSolutionComplete {
                                Button { scene.nextStep() } label: { Text("Show next move").frame(maxWidth: .infinity) }
                                    .buttonStyle(CubePrimaryButton())
                            } else {
                                Text("All steps completed").frame(maxWidth: .infinity).font(.headline)
                            }
                        }
                    }.cubeDrawer()
                }.frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
        }
        .background(CubeStyle.stage.ignoresSafeArea()).foregroundStyle(.white)
        .navigationTitle("Let’s solve it").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CubeStyle.stage, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Slow motion", isOn: $scene.slow).disabled(scene.playback.isBusy)
                    Button("Replay last move") { scene.replay() }.disabled(scene.playback.lastTurn == nil || scene.playback.isBusy)
                    Button("Play all moves") { scene.playSolution() }.disabled(scene.playback.isBusy || scene.playback.nextMove == nil)
                    Button("Restart solution") { scene.restartSolution() }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Playback options")
            }
        }
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
                                if completed && !current { Image(systemName: "checkmark").font(.caption2) }
                            }
                            .frame(minWidth: 56).padding(8)
                            .background(current ? CubeStyle.action : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
