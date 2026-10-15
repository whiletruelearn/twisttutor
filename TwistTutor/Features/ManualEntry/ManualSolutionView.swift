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
    @State private var goalScene: CubeScene?
    @State private var showWhy = false
    @State private var showMoves = false
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
                        Text(goalScene != nil ? "Your goal" : scene.playback.isSolutionComplete ? "You did it." : lesson?.stage.title ?? "One twist at a time.")
                            .font(.title2.bold()).fontDesign(.rounded)
                        Spacer()
                        Text(teachingPlan == nil ? "\(scene.playback.completedMoveCount) / \(solution.moves.count)" : scene.playback.isSolutionComplete ? "Complete" : "Stage \((lesson?.stage.rawValue ?? 6) + 1) of 7")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(CubeStyle.secondary)
                            .accessibilityIdentifier("solutionProgress")
                    }.padding(24)
                    CubeViewport(scene: goalScene ?? scene)
                        .id(ObjectIdentifier(goalScene ?? scene))
                        .frame(height: max(260, geometry.size.height - (textSize.isAccessibilitySize ? 480 : 340)))
                        .overlay(alignment: .topTrailing) {
                            Button { (goalScene ?? scene).resetView() } label: {
                                Image(systemName: "viewfinder").font(.title3).frame(width: 48, height: 48)
                                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityLabel("Reset cube view").padding(.trailing, 20)
                        }
                    VStack(spacing: 14) {
                        if goalScene != nil, let lesson {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(lesson.stage.title).font(.title2.bold()).fontDesign(.rounded)
                                Text("Your cube after this stage").font(.subheadline.bold())
                                Text(lesson.stage.goal).font(.subheadline).foregroundStyle(Color(white: 0.35))
                                Label("Preview only · drag to look around", systemImage: "hand.draw")
                                    .font(.caption).foregroundStyle(Color(white: 0.35))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        } else if showPiece, let piece = lesson?.piece {
                            pieceExplanation(piece)
                        } else {
                        if let lesson {
                            HStack {
                                Button("See goal", systemImage: "scope") { presentGoal() }
                                Spacer()
                                if lesson.piece != nil {
                                    Button("Find piece", systemImage: "viewfinder") { showPiece = true }
                                }
                                Spacer()
                                Button("Why?", systemImage: "questionmark.circle") { showWhy = true }
                            }.font(.subheadline).frame(minHeight: 44).disabled(scene.playback.isBusy)
                        }
                        if let move = scene.playback.activeTurn?.move ?? scene.playback.nextMove {
                            HStack(alignment: .center, spacing: 14) {
                                if teachingPlan == nil {
                                    Text(move.notation).font(.largeTitle.bold()).fontDesign(.rounded).frame(minWidth: 54)
                                } else {
                                    Image(systemName: move.amount == .counterclockwise ? "arrow.counterclockwise" : "arrow.clockwise")
                                        .font(.largeTitle).foregroundStyle(CubeStyle.action).frame(minWidth: 54)
                                        .accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    if teachingPlan != nil {
                                        LearningColorCue(color: solution.initialCube.centerColors[move.face.rawValue], caption: "center · \(move.face.title.lowercased())")
                                        Text(move.amount == .half ? "Half turn" : "Quarter turn \(direction(move.amount))").font(.headline)
                                        Text("Look directly at this face to turn it.").font(.caption).foregroundStyle(Color(white: 0.35))
                                    } else {
                                        Text("\(stepAction): \(move.face.title.lowercased()) face").font(.headline)
                                        Text("Turn the \(solution.initialCube.centerColors[move.face.rawValue].rawValue)-center face \(direction(move.amount)), looking at that face.")
                                            .font(.subheadline).foregroundStyle(Color(white: 0.35))
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Label("Your cube is solved", systemImage: "checkmark.circle.fill").font(.title2.bold()).foregroundStyle(.green)
                        }
                        if !solution.moves.isEmpty {
                            if teachingPlan == nil { stepStrip }
                            else if lesson != nil {
                                HStack {
                                    Text("\(stepAction) move \(min(visibleMoves.count, max(1, (scene.playback.currentStepIndex ?? scene.playback.completedMoveCount) - visibleMoves.lowerBound + 1))) of \(visibleMoves.count)")
                                        .font(.subheadline.bold()).accessibilityIdentifier("currentSolutionStep")
                                    Spacer()
                                    Button("All moves") { showMoves = true }.font(.subheadline).frame(minHeight: 44)
                                }
                                ProgressView(value: Double(max(0, scene.playback.completedMoveCount - visibleMoves.lowerBound)), total: Double(visibleMoves.count))
                                    .accessibilityLabel("Progress through this stage")
                            }
                        }
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
                    Button("Replay last move") { scene.replay() }.disabled(goalScene != nil || showPiece || scene.playback.lastTurn == nil || scene.playback.isBusy)
                    if teachingPlan != nil { Toggle("Try without animation", isOn: $withoutAnimation).disabled(scene.playback.isBusy) }
                    if teachingPlan == nil {
                        Button("Play all moves") { scene.playSolution() }.disabled(scene.playback.isBusy || scene.playback.nextMove == nil)
                    }
                    Button("Restart solution") { showPiece = false; goalScene = nil; checkpoint = nil; showCheckpoint = false; scene.restartSolution(); presentGoal() }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Playback options")
            }
        }
        .onAppear { scene.slow = slowMoves; if scene.playback.isSolutionComplete { onComplete() } else { presentGoal() } }
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
        .sheet(isPresented: $showCheckpoint, onDismiss: { if checkpoint != nil && !scene.playback.isSolutionComplete { presentGoal() }; checkpoint = nil }) {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text(scene.playback.isSolutionComplete ? "You solved your cube." : "Pause and check your cube.").font(.title2.bold())
                Text(scene.playback.isSolutionComplete ? "All six faces should match their centers." : checkpoint?.goal ?? "Check that your cube matches the model.")
                Text("Does your cube match? If not, go back through the last moves.")
                    .foregroundStyle(.secondary)
                Button("My cube matches") { showCheckpoint = false }.frame(maxWidth: .infinity).buttonStyle(CubePrimaryButton())
                Button("Let me check the last moves") { checkpoint = nil; showCheckpoint = false }.frame(maxWidth: .infinity, minHeight: 44)
            }.padding(24).presentationDetents([.medium, .large]).environment(\.colorScheme, .light)
        }
        .sheet(isPresented: $showWhy) {
            NavigationStack {
                ScrollView {
                    if let lesson {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(lesson.name).font(.title2.bold())
                            Text(lesson.explanation)
                            Text("Finish the whole pattern. Earlier layers may look mixed partway through.").foregroundStyle(.secondary)
                        }.padding(24)
                    }
                }.navigationTitle("Why this works").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showWhy = false } } }
            }.presentationDetents([.medium, .large]).environment(\.colorScheme, .light)
        }
        .sheet(isPresented: $showMoves) {
            NavigationStack {
                ScrollView { stepStrip.padding(24) }
                    .navigationTitle("Moves in this stage").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showMoves = false } } }
            }.presentationDetents([.medium, .large]).environment(\.colorScheme, .light)
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
        if goalScene != nil {
            Button { goalScene = nil } label: { Text("Back to my cube").frame(maxWidth: .infinity) }
                .buttonStyle(CubePrimaryButton())
        } else if showPiece {
            Button { showPiece = false } label: { Text("Back to the moves").frame(maxWidth: .infinity) }
                .buttonStyle(CubePrimaryButton())
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
            Text("Find this \(piece.colors.count == 2 ? "edge" : "corner")").font(.title2.bold())
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { ForEach(piece.colors, id: \.self) { LearningColorCue(color: $0, caption: "") } }
                VStack(alignment: .leading, spacing: 10) { ForEach(piece.colors, id: \.self) { LearningColorCue(color: $0, caption: "") } }
            }
            Label("White outline: the piece", systemImage: "viewfinder").font(.subheadline.bold())
                .accessibilityHint("On the \(piece.currentIndices(in: scene.playback.cube).map { CubeFaceID(rawValue: $0 / 9)!.title.lowercased() }.joined(separator: ", ")) faces")
            if Set(piece.currentIndices(in: scene.playback.cube)) == Set(piece.destinationIndices) {
                Text("It’s home. Now its colors need to face the matching centers.").font(.subheadline)
            } else {
                Label("Blue outline: where it belongs", systemImage: "scope").font(.subheadline.bold())
                    .accessibilityHint("Between the \(piece.destinationFaces.map { $0.title.lowercased() }.joined(separator: ", ")) centers")
            }
            Text("Drag to find it. Match each color to its center.").font(.subheadline).foregroundStyle(Color(white: 0.35))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presentGoal() {
        guard let plan = teachingPlan, let lesson, !scene.playback.isBusy,
              let end = plan.lessons.last(where: { $0.stage == lesson.stage })?.moveRange.upperBound else { return }
        showPiece = false
        let preview = CubeScene(cube: solution.initialCube.applying(Array(solution.moves.prefix(end))))
        preview.showsTurnGuide = false
        switch lesson.stage {
        case .cross, .firstCorners: preview.focus(on: .down)
        case .middleEdges: preview.resetView()
        default: preview.focus(on: .up)
        }
        goalScene = preview
    }

    private var lesson: BeginnerLesson? {
        teachingPlan?.lesson(at: scene.playback.currentStepIndex ?? scene.playback.completedMoveCount)
    }

    private var stepAction: String {
        if scene.playback.activeTurn?.isBackward == true { return "Undoing" }
        if scene.playback.activeTurn?.isReplay == true { return "Replaying" }
        return scene.playback.isBusy ? "Playing" : "Next"
    }

    private var visibleMoves: Range<Int> {
        guard let lesson, let plan = teachingPlan,
              let first = plan.lessons.first(where: { $0.stage == lesson.stage }),
              let last = plan.lessons.last(where: { $0.stage == lesson.stage }) else { return solution.moves.indices }
        return first.moveRange.lowerBound..<last.moveRange.upperBound
    }

    private var stepStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scene.playback.currentStepIndex.map {
                teachingPlan == nil ? "\(stepAction) step \($0 + 1) of \(solution.moves.count)" : "\(stepAction) move \($0 - visibleMoves.lowerBound + 1) of \(visibleMoves.count) in this stage"
            } ?? "All \(solution.moves.count) steps completed")
                .font(.subheadline.bold()).accessibilityIdentifier("currentSolutionStep")
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(visibleMoves, id: \.self) { index in
                            let current = scene.playback.currentStepIndex == index
                            let completed = index < scene.playback.completedMoveCount
                            VStack(spacing: 4) {
                                Text("\(index - visibleMoves.lowerBound + 1)").font(.caption)
                                Text(solution.moves[index].notation).font(.body.monospaced().bold())
                                if completed && !current { Image(systemName: "checkmark").font(.caption2) }
                            }
                            .frame(minWidth: 56).padding(8)
                            .background(current ? CubeStyle.action : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(current ? Color.white : Color.primary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Step \(index - visibleMoves.lowerBound + 1), \(solution.moves[index].notation), \(current ? "current" : completed ? "completed" : "upcoming")")
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
