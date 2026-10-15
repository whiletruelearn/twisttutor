import SwiftUI
import CubeCore
import CubeSolver
import AppWorkflow

/// Shared verified playback for quick solutions and beginner teaching plans.
struct ManualSolutionView: View {
    let solution: VerifiedSolution
    let onComplete: () -> Void
    let teachingPlan: BeginnerPlan?
    @AppStorage("slowMoves") private var slowMoves = true
    @State private var checkpoint: BeginnerStage?
    @State private var showCheckpoint = false
    @State private var showHoldingHelp = false
    @State private var showPiece = false
    @State private var withoutAnimation = false
    @ScaledMetric private var stepStripHeight = 72
    @State private var scene: CubeScene
    @Environment(\.scenePhase) private var scenePhase

    init(solution: VerifiedSolution, teachingPlan: BeginnerPlan? = nil, onComplete: @escaping () -> Void) {
        self.solution = solution
        self.teachingPlan = teachingPlan
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
                        Text(scene.playback.isSolutionComplete ? "You did it." : lesson?.stage.title ?? "One twist at a time.")
                            .font(.title2.bold()).fontDesign(.rounded)
                        Spacer()
                        Text("\(scene.playback.completedMoveCount) / \(solution.moves.count)")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(CubeStyle.secondary)
                            .accessibilityIdentifier("solutionProgress")
                    }.padding(24)
                    CubeViewport(scene: scene)
                        .frame(height: max(220, geometry.size.height - (textSize.isAccessibilitySize ? 500 : teachingPlan == nil ? 260 : 430)))
                        .overlay(alignment: .topTrailing) {
                            Button { scene.resetView() } label: {
                                Image(systemName: "viewfinder").font(.title3).frame(width: 48, height: 48)
                                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityLabel("Reset cube view").padding(.trailing, 20)
                        }
                    VStack(spacing: 14) {
                        if showPiece, let piece = lesson?.piece {
                            pieceExplanation(piece)
                        } else {
                        if let lesson {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Stage \(lesson.stage.rawValue + 1) of 7 · \(lesson.name)").font(.subheadline.bold())
                                Text(lesson.stage.goal).font(.subheadline).foregroundStyle(Color(white: 0.35))
                                if let piece = lesson.piece {
                                    Button { showPiece = true } label: {
                                        Label("Find the \(piece.colors.map(\.rawValue).joined(separator: "–")) \(piece.colors.count == 2 ? "edge" : "corner")", systemImage: "viewfinder")
                                            .font(.subheadline).frame(minHeight: 44)
                                    }.disabled(scene.playback.isBusy)
                                }
                                DisclosureGroup("Why this pattern works") {
                                    Text(lesson.explanation).font(.subheadline).padding(.vertical, 8)
                                    Text(MoveNotation.format(Array(solution.moves[lesson.moveRange])))
                                        .font(.body.monospaced()).textSelection(.enabled)
                                    Text("A finished layer may look mixed during the pattern. It comes back together when the whole pattern finishes.")
                                        .font(.footnote).foregroundStyle(Color(white: 0.35)).padding(.top, 4)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                        if let move = scene.playback.activeTurn?.move ?? scene.playback.nextMove {
                            HStack(alignment: .top, spacing: 14) {
                                Text(move.notation).font(.largeTitle.bold()).fontDesign(.rounded)
                                    .frame(minWidth: 54)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(stepAction): \(move.face.title.lowercased()) face").font(.headline)
                                    Text("Turn the \(solution.initialCube.centerColors[move.face.rawValue].rawValue)-center face \(direction(move.amount)), looking at that face.")
                                        .font(.subheadline).foregroundStyle(Color(white: 0.35))
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Label("Your cube is solved", systemImage: "checkmark.circle.fill").font(.title2.bold()).foregroundStyle(.green)
                        }
                        if !solution.moves.isEmpty { stepStrip }
                        }
                    }.cubeDrawer()
                }.frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
        }
        .background(CubeStyle.stage.ignoresSafeArea()).foregroundStyle(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) { playbackControls.cubeDrawer().frame(maxWidth: 700).background(CubeStyle.stage) }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(teachingPlan == nil ? "Let’s solve it" : "Learn with your cube").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CubeStyle.stage, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("How to hold my cube") { scene.resetView(); showHoldingHelp = true }
                    Toggle("Slow motion", isOn: $scene.slow).disabled(scene.playback.isBusy)
                    Button("Replay last move") { scene.replay() }.disabled(showPiece || scene.playback.lastTurn == nil || scene.playback.isBusy)
                    if teachingPlan != nil { Toggle("Try without animation", isOn: $withoutAnimation).disabled(scene.playback.isBusy) }
                    if teachingPlan == nil {
                        Button("Play all moves") { scene.playSolution() }.disabled(scene.playback.isBusy || scene.playback.nextMove == nil)
                    }
                    Button("Restart solution") { showPiece = false; checkpoint = nil; showCheckpoint = false; scene.restartSolution() }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Playback options")
            }
        }
        .onAppear { scene.slow = slowMoves; if scene.playback.isSolutionComplete { onComplete() } }
        .onChange(of: scene.playback.completedMoveCount) { old, count in
            guard count > old, let plan = teachingPlan, let completed = plan.lesson(at: count - 1),
                  plan.lesson(at: count)?.stage != completed.stage else { return }
            checkpoint = completed.stage; showCheckpoint = true
        }
        .onChange(of: showPiece) { _, inspecting in
            scene.showsTurnGuide = !inspecting
            scene.sourceHighlights = inspecting ? Set(lesson?.piece?.currentIndices(in: scene.playback.cube) ?? []) : []
            scene.destinationHighlights = inspecting ? Set(lesson?.piece?.destinationIndices ?? []) : []
            scene.refreshHighlights()
        }
        .sheet(isPresented: $showCheckpoint) {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text(scene.playback.isSolutionComplete ? "You solved your cube." : "Pause and check your cube.").font(.title2.bold())
                Text(scene.playback.isSolutionComplete ? "All six faces should match their centers." : checkpoint?.goal ?? "Check that your cube matches the model.")
                Text("Compare your physical cube with the model. If they differ, use Previous step to retrace your moves before continuing.")
                    .foregroundStyle(.secondary)
                Button("My cube matches") { showCheckpoint = false }.frame(maxWidth: .infinity).buttonStyle(CubePrimaryButton())
                Button("Let me check the last moves") { showCheckpoint = false }.frame(maxWidth: .infinity, minHeight: 44)
            }.padding(24).presentationDetents([.medium, .large]).environment(\.colorScheme, .light)
        }
        .sheet(isPresented: $showHoldingHelp) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Keep your bearings").font(.title2.bold())
                Text(holdingInstruction(for: solution.initialCube)).font(.headline)
                Text("The letter on each center names that face. Dragging the model only changes your view. Tap Reset view to return to this holding position.")
                Button("Got it") { showHoldingHelp = false }.frame(maxWidth: .infinity).buttonStyle(CubePrimaryButton())
            }.padding(24).presentationDetents([.medium, .large]).environment(\.colorScheme, .light)
        }
        .onChange(of: scene.playback.isSolutionComplete) { _, complete in if complete { onComplete() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scene.cancel() } }
        .onDisappear { scene.cancel() }
    }

    @ViewBuilder private var playbackControls: some View {
        if showPiece {
            Button("Back to the moves") { showPiece = false }
                .frame(maxWidth: .infinity).buttonStyle(CubePrimaryButton())
        } else {
            HStack(spacing: 12) {
                Button { scene.previousStep() } label: {
                    Image(systemName: "backward.end.fill").frame(width: 48, height: 52)
                }.disabled(!scene.playback.canGoBack || scene.isAutoPlaying)
                    .accessibilityLabel("Previous step").accessibilityIdentifier("previousStep")
                if scene.playback.isBusy || scene.isAutoPlaying {
                    Button { scene.cancel() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(CubePrimaryButton())
                } else if !scene.playback.isSolutionComplete {
                    Button {
                        if withoutAnimation { scene.confirmNextWithoutAnimation() } else { scene.nextStep() }
                    } label: {
                        Text(withoutAnimation ? "I did this move" : teachingPlan == nil ? "Show next move" : "Show this move")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(CubePrimaryButton())
                } else {
                    Text("All steps completed").frame(maxWidth: .infinity).font(.headline)
                }
            }
        }
    }

    private func pieceExplanation(_ piece: TeachingPiece) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Find \(piece.colors.map(\.rawValue).joined(separator: " + "))").font(.title2.bold())
            Text("White outline: your piece").font(.headline)
            Text("It’s between the \(piece.currentIndices(in: scene.playback.cube).map { CubeFaceID(rawValue: $0 / 9)!.title.lowercased() }.joined(separator: ", ")) faces. Drag the cube to see it.")
            if Set(piece.currentIndices(in: scene.playback.cube)) == Set(piece.destinationIndices) {
                Text("It’s in its home position. Its colors still need to face the matching centers.")
            } else {
                Text("Blue outline: its home").font(.headline)
                Text("It belongs between the \(piece.destinationFaces.map { $0.title.lowercased() }.joined(separator: ", ")) centers, with each color facing its matching center.")
            }
            Text("This is one piece we’re working toward in this stage. It may take more than one pattern to place it.").font(.footnote).foregroundStyle(Color(white: 0.35))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lesson: BeginnerLesson? {
        teachingPlan?.lesson(at: scene.playback.currentStepIndex ?? scene.playback.completedMoveCount)
    }

    private var stepAction: String {
        if scene.playback.activeTurn?.isBackward == true { return "Undoing" }
        if scene.playback.activeTurn?.isReplay == true { return "Replaying" }
        return scene.playback.isBusy ? "Playing" : "Next"
    }

    private var visibleMoves: Range<Int> { lesson?.moveRange ?? solution.moves.indices }

    private var stepStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scene.playback.currentStepIndex.map {
                teachingPlan == nil ? "\(stepAction) step \($0 + 1) of \(solution.moves.count)" : "\(stepAction) move \($0 - (lesson?.moveRange.lowerBound ?? 0) + 1) of \(lesson?.moveRange.count ?? solution.moves.count) in this pattern"
            } ?? "All \(solution.moves.count) steps completed")
                .font(.subheadline.bold()).accessibilityIdentifier("currentSolutionStep")
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(visibleMoves, id: \.self) { index in
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
