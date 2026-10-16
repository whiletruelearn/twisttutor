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
    @State private var retracing = false
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
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            if teachingPlan != nil, let lesson, !scene.playback.isSolutionComplete {
                                Text("Goal \(lesson.stage.number) of 7 · \(lesson.stage.layer.title)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(CubeStyle.secondary)
                                    .accessibilityIdentifier("solutionProgress")
                            }
                            Text(scene.playback.isSolutionComplete ? "You did it." : lesson.map { $0.stage.headline(coach) } ?? "One twist at a time.")
                                .font(.title2.bold()).fontDesign(.rounded)
                        }
                        Spacer()
                        if teachingPlan == nil {
                            Text("\(scene.playback.completedMoveCount) / \(solution.moves.count)")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(CubeStyle.secondary)
                                .accessibilityIdentifier("solutionProgress")
                        }
                    }.padding(24)
                    CubeViewport(scene: goalScene ?? scene)
                        .id(ObjectIdentifier(goalScene ?? scene))
                        .frame(height: max(teachingPlan == nil ? 260 : 220, geometry.size.height - (textSize.isAccessibilitySize ? 480 : teachingPlan == nil ? 340 : 500)))
                        .overlay(alignment: .topTrailing) {
                            Button { (goalScene ?? scene).resetView() } label: {
                                Image(systemName: "viewfinder").font(.title3).frame(width: 48, height: 48)
                                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityLabel("Reset cube view").padding(.trailing, 20)
                        }
                    VStack(spacing: 14) {
                        if goalScene != nil, let lesson {
                            goalBriefing(lesson.stage)
                        } else if showPiece, let piece = lesson?.piece {
                            pieceExplanation(piece)
                        } else {
                        if let lesson, let move = scene.playback.activeTurn?.move ?? scene.playback.nextMove {
                            teachingStep(lesson, move: move)
                        } else if let move = scene.playback.activeTurn?.move ?? scene.playback.nextMove {
                            HStack(alignment: .center, spacing: 14) {
                                Text(move.notation).font(.largeTitle.bold()).fontDesign(.rounded).frame(minWidth: 54)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(stepAction): \(move.face.title.lowercased()) face").font(.headline)
                                    Text("Turn the \(solution.initialCube.centerColors[move.face.rawValue].rawValue)-center face \(direction(move.amount)), looking at that face.")
                                        .font(.subheadline).foregroundStyle(Color(white: 0.35))
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Label("Your cube is solved", systemImage: "checkmark.circle.fill").font(.title2.bold()).foregroundStyle(.green)
                        }
                        if !solution.moves.isEmpty && teachingPlan == nil { stepStrip }
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
                    if teachingPlan != nil {
                        Toggle("I’ll turn first, then tap", isOn: $withoutAnimation).disabled(scene.playback.isBusy)
                        Button("Show turns as notation") { showMoves = true }
                    }
                    if teachingPlan == nil {
                        Button("Play all moves") { scene.playSolution() }.disabled(scene.playback.isBusy || scene.playback.nextMove == nil)
                    }
                    Button("Restart solution") { showPiece = false; goalScene = nil; checkpoint = nil; scene.restartSolution(); presentGoal() }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Playback options")
            }
        }
        .onAppear { scene.slow = slowMoves; if scene.playback.isSolutionComplete { onComplete() } else { presentGoal() } }
        .onChange(of: scene.playback.completedMoveCount) { old, count in
            guard count > old, let plan = teachingPlan, let completed = plan.lesson(at: count - 1),
                  plan.lesson(at: count)?.stage != completed.stage else { return }
            checkpoint = completed.stage
        }
        .onChange(of: showPiece) { _, inspecting in
            scene.showsTurnGuide = !inspecting
            scene.sourceHighlights = inspecting ? Set(lesson?.piece?.currentIndices(in: scene.playback.cube) ?? []) : []
            scene.destinationHighlights = inspecting ? Set(lesson?.piece?.destinationIndices ?? []) : []
            scene.refreshHighlights()
        }
        .sheet(item: $checkpoint, onDismiss: { if !retracing && !scene.playback.isSolutionComplete { presentGoal() }; retracing = false }) { stage in
            ScrollView { checkpointCard(stage).padding(24) }
                .presentationDetents([.large]).presentationBackground(Color(uiColor: .systemBackground))
        }
        .sheet(isPresented: $showWhy) {
            NavigationStack {
                ScrollView {
                    if let lesson {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(lesson.name).font(.title2.bold())
                            Text(lesson.explanation)
                            if !lesson.isSetupOnly && lesson.stage != .cross {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Say it as you turn").font(.headline)
                                    Text(solution.moves[lesson.patternRange].map(\.shortLabel).joined(separator: "  ·  "))
                                        .font(.body.weight(.semibold))
                                    Text("Saying the pattern out loud is how most people learn it. After a few solves your hands will remember it on their own.")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }.padding(24)
                    }
                }.navigationTitle("How this works").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showWhy = false } } }
            }.presentationDetents([.medium, .large]).presentationBackground(Color(uiColor: .systemBackground))
        }
        .sheet(isPresented: $showMoves) {
            NavigationStack {
                ScrollView { stepStrip.padding(24) }
                    .navigationTitle(teachingPlan == nil ? "Moves in this stage" : "This goal in notation").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showMoves = false } } }
            }.presentationDetents([.medium, .large]).presentationBackground(Color(uiColor: .systemBackground))
        }
        .sheet(isPresented: $showHoldingHelp) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Keep your bearings").font(.title2.bold())
                Text(holdingInstruction(for: solution.initialCube)).font(.headline)
                Text("Every turn I describe — “right side up”, “top layer to the left” — assumes you’re holding it this way. Dragging the model only changes your view, not your cube. Tap the frame button to snap back.")
                Button { showHoldingHelp = false } label: { Text("Got it").frame(maxWidth: .infinity) }.buttonStyle(CubePrimaryButton())
            }.padding(24).presentationDetents([.medium, .large]).presentationBackground(Color(uiColor: .systemBackground))
        }
        .onChange(of: scene.playback.isSolutionComplete) { _, complete in if complete { onComplete() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scene.cancel() } }
        .onDisappear { scene.cancel() }
    }

    @ViewBuilder private var playbackControls: some View {
        if goalScene != nil {
            Button { goalScene = nil } label: { Text(teachingPlan != nil && atStageStart ? "I’m ready — let’s go" : "Back to my cube").frame(maxWidth: .infinity) }
                .buttonStyle(CubePrimaryButton())
        } else if showPiece {
            Button { showPiece = false } label: { Text("Found it — back to the turns").frame(maxWidth: .infinity) }
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
                        Text(withoutAnimation ? "I did it — next turn" : teachingPlan == nil ? "Show next move" : "Show me this turn")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(CubePrimaryButton())
                    if teachingPlan != nil {
                        Button { scene.replay() } label: {
                            Image(systemName: "arrow.counterclockwise").frame(width: 48, height: 52)
                        }.disabled(scene.playback.lastTurn == nil || scene.isAutoPlaying)
                            .accessibilityLabel("Watch the last turn again")
                    }
                } else {
                    Text("All steps completed").frame(maxWidth: .infinity).font(.headline)
                }
            }
        }
    }

    private func pieceExplanation(_ piece: TeachingPiece) -> some View {
        let kind = piece.colors.count == 2 ? "edge" : "corner"
        let home = Set(piece.currentIndices(in: scene.playback.cube)) == Set(piece.destinationIndices)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Find this \(kind)").font(.title2.bold())
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { ForEach(piece.colors, id: \.self) { LearningColorCue(color: $0, caption: "") } }
                VStack(alignment: .leading, spacing: 10) { ForEach(piece.colors, id: \.self) { LearningColorCue(color: $0, caption: "") } }
            }
            Label("White outline: where it is now", systemImage: "viewfinder").font(.subheadline.bold())
                .accessibilityHint("On the \(piece.currentIndices(in: scene.playback.cube).map { CubeFaceID(rawValue: $0 / 9)!.title.lowercased() }.joined(separator: ", ")) faces")
            if home {
                Text("It’s already in its spot, just turned the wrong way. These turns will flip it so each color faces its matching center.").font(.subheadline)
            } else {
                Label("Blue outline: where it’s going", systemImage: "scope").font(.subheadline.bold())
                    .accessibilityHint("Between the \(piece.destinationFaces.map { $0.title.lowercased() }.joined(separator: ", ")) centers")
                Text("Its home is between the \(piece.destinationFaces.map { "\(solution.initialCube.centerColors[$0.rawValue].name)" }.joined(separator: " and ")) centers.")
                    .font(.subheadline)
            }
            Text("Now find the same piece on the cube in your hands. Drag the model if it’s hidden around the back.")
                .font(.subheadline).foregroundStyle(Color(white: 0.35))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coach: CoachColors { CoachColors(cube: solution.initialCube) }
    private var moveIndex: Int { scene.playback.currentStepIndex ?? scene.playback.completedMoveCount }
    private var atStageStart: Bool { moveIndex == visibleMoves.lowerBound }

    private func goalBriefing(_ stage: BeginnerStage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(stage.introduction(coach)).font(.body).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill").foregroundStyle(.orange).accessibilityHidden(true)
                Text(stage.tip(coach)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine).accessibilityLabel("Tip: \(stage.tip(coach))")
            VStack(alignment: .leading, spacing: 4) {
                Text("You’re done when…").font(.subheadline.bold())
                Text(stage.doneWhen(coach)).font(.subheadline).foregroundStyle(Color(white: 0.35)).fixedSize(horizontal: false, vertical: true)
            }
            Label("The model shows your cube after this goal. Drag to look around.", systemImage: "hand.draw")
                .font(.caption).foregroundStyle(Color(white: 0.35))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func teachingStep(_ lesson: BeginnerLesson, move: CubeMove) -> some View {
        let firstTurn = moveIndex == lesson.moveRange.lowerBound && !scene.playback.isBusy
        VStack(alignment: .leading, spacing: 6) {
            Text(lesson.headline(coach)).font(.headline)
            if firstTurn {
                Text(lesson.coaching(coach)).font(.subheadline).foregroundStyle(Color(white: 0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: move.directionSymbol)
                .font(.title.bold()).foregroundStyle(.white).frame(width: 56, height: 56)
                .background(CubeStyle.action, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(scene.playback.activeTurn?.isBackward == true ? "Undoing: \(move.spokenInstruction.lowercased())" : move.spokenInstruction)
                    .font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                Text(move.handHint).font(.caption).foregroundStyle(Color(white: 0.35))
                LearningColorCue(color: solution.initialCube.centerColors[move.face.rawValue], caption: "center \(move.face.whereFromHands)")
                    .scaleEffect(0.85, anchor: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("currentSolutionStep")
        patternChips(lesson)
        HStack {
            if lesson.piece != nil {
                Button("Find the piece", systemImage: "viewfinder") { showPiece = true }
            }
            Spacer()
            Button("See the goal", systemImage: "scope") { presentGoal() }
            Spacer()
            Button("How it works", systemImage: "questionmark.circle") { showWhy = true }
        }.font(.subheadline).labelStyle(.titleOnly).frame(minHeight: 44).disabled(scene.playback.isBusy)
        ProgressView(value: Double(max(0, scene.playback.completedMoveCount - visibleMoves.lowerBound)), total: Double(visibleMoves.count))
            .accessibilityLabel("Progress through this goal")
    }

    /// The lesson's turns at a glance, so the pattern can be learned as a phrase rather than a list.
    private func patternChips(_ lesson: BeginnerLesson) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lesson.phase(of: min(moveIndex, lesson.moveRange.upperBound - 1)))
                .font(.caption.weight(.semibold)).foregroundStyle(Color(white: 0.35))
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(lesson.moveRange, id: \.self) { index in
                            let current = index == moveIndex
                            let done = index < scene.playback.completedMoveCount && !current
                            let setup = index < lesson.patternRange.lowerBound
                            Text(solution.moves[index].shortLabel)
                                .font(.subheadline.weight(current ? .bold : .regular))
                                .padding(.horizontal, 10).frame(minHeight: 34)
                                .background(current ? CubeStyle.action : Color.secondary.opacity(setup ? 0.06 : 0.12), in: Capsule())
                                .overlay { if setup && !current { Capsule().strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3])) } }
                                .foregroundStyle(current ? Color.white : done ? Color.secondary : Color.primary)
                                .id(index)
                        }
                    }
                }
                .onChange(of: moveIndex, initial: true) { _, index in proxy.scrollTo(index, anchor: .center) }
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("Turns for this piece: \(solution.moves[lesson.moveRange].map(\.spokenInstruction).joined(separator: ", "))")
    }

    @ViewBuilder private func checkpointCard(_ stage: BeginnerStage) -> some View {
        let done: BeginnerStage? = scene.playback.isSolutionComplete ? .topEdges : stage
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: scene.playback.isSolutionComplete ? "star.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 44)).foregroundStyle(scene.playback.isSolutionComplete ? .orange : .green)
            if let done {
                Text(scene.playback.isSolutionComplete ? BeginnerStage.topEdges.celebration : done.celebration).font(.title2.bold())
                Text(scene.playback.isSolutionComplete ? BeginnerStage.topEdges.encouragement : done.encouragement)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check the cube in your hands").font(.headline)
                    Text(done.doneWhen(coach)).foregroundStyle(.secondary)
                }
                if !scene.playback.isSolutionComplete, let next = nextStage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Up next · Goal \(next.number)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(next.headline(coach)).font(.headline)
                    }
                }
            }
            Button { checkpoint = nil } label: {
                Text(scene.playback.isSolutionComplete ? "Done" : "Yes, my cube matches").frame(maxWidth: .infinity)
            }.buttonStyle(CubePrimaryButton())
            if !scene.playback.isSolutionComplete {
                Button("Not quite — let me retrace") { retracing = true; checkpoint = nil }.frame(maxWidth: .infinity, minHeight: 44)
                Text("No problem if it doesn’t match. Step back with ◀︎ and redo the last few turns slowly, watching each one first.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nextStage: BeginnerStage? { teachingPlan?.lesson(at: scene.playback.completedMoveCount)?.stage }

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
