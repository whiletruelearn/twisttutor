import SwiftUI
import CubeCore
import CubeSolver
import AppWorkflow

struct ContentView: View {
    @State private var entry = ManualCubeEntry()
    var body: some View {
        TabView {
            SolveHomeView(entry: entry).cubeTabSurface().tabItem { Label("Solve cube", systemImage: "cube") }
            LearnHomeView(entry: entry).cubeTabSurface().tabItem { Label("Learn", systemImage: "book") }
            SolveTimerView().cubeTabSurface().tabItem { Label("Time solving", systemImage: "stopwatch") }
            CubeSettingsView().cubeTabSurface().tabItem { Label("Settings", systemImage: "gearshape") }
        }.tint(CubeStyle.action)
    }
}

private struct SolveHomeView: View {
    let entry: ManualCubeEntry
    @State private var scene = CubeScene()
    @Environment(\.scenePhase) private var scenePhase


    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your cube.\nLet’s solve it.")
                            .font(.largeTitle.weight(.bold)).fontDesign(.rounded)
                        Text("Your cube. One move at a time.")
                            .font(.body).foregroundStyle(CubeStyle.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    CubeViewport(scene: scene)
                        .frame(maxHeight: .infinity)
                        .accessibilityLabel("Cube preview. Drag to explore.")
                    VStack(spacing: 14) {
                        Text("Match your colors, then follow the moves.")
                            .font(.subheadline).foregroundStyle(Color(white: 0.35))
                        NavigationLink { ManualEntryView(entry: entry) } label: {
                            Text("Let’s solve your cube").frame(maxWidth: .infinity)
                        }.buttonStyle(CubePrimaryButton())
                    }.cubeDrawer()
                }
                .frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .background(CubeStyle.stage.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle("TwistTutor").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CubeStyle.stage, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)

        }.tint(CubeStyle.action)
        .onAppear { scene.showsTurnGuide = false; scene.refreshHighlights() }
        .onChange(of: scene.selectedFace) { _, _ in scene.refreshHighlights() }
        .onChange(of: scene.amount) { _, _ in scene.refreshHighlights() }
        .onChange(of: scene.highlightPiece) { _, _ in scene.refreshHighlights() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scene.cancel() } }
    }

}

#Preview { ContentView() }

// THESIS: Cube first; the object leads and controls stay at the edge.
// OWN-WORLD: Slate navy stage, white working tray, rounded system headings, blue action.
// STORY: Match a physical cube, inspect it, then follow one verified move at a time.
// FIRST VIEWPORT: Native navigation, generous cube stage, compact instruction and bottom action.
// FORM: Full-screen object workspace, approved Cube first direction (abdd855a).
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md

enum CubeStyle {
    static let stageUIColor = UIColor(red: 0.075, green: 0.12, blue: 0.19, alpha: 1)
    static let stage = Color(uiColor: stageUIColor)
    static let action = Color(red: 0.06, green: 0.28, blue: 0.72)
    static let secondary = Color(red: 0.72, green: 0.78, blue: 0.86)
}

struct CubePrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).padding(.horizontal, 20).frame(minHeight: 52)
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .background(enabled ? CubeStyle.action : Color.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension View {
    func cubeTabSurface() -> some View {
        self.toolbarBackground(Color.white, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.light, for: .tabBar)
    }
    func cubeDrawer() -> some View {
        self.padding(20).frame(maxWidth: .infinity)
            .foregroundStyle(Color.primary).background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28))
            .environment(\.colorScheme, .light).tint(CubeStyle.action)
    }
}

private struct LearnHomeView: View {
    let entry: ManualCubeEntry
    @State private var scene = CubeScene()
    @State private var plan: BeginnerPlan?
    @State private var showingPlan = false
    @State private var planning: Task<Void, Never>?
    @State private var error: String?
    @State private var confirmExample = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Learn by doing.").font(.largeTitle.bold()).fontDesign(.rounded)
                        Text("Your cube. One small goal at a time.").foregroundStyle(CubeStyle.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
                    CubeViewport(scene: scene).frame(height: 240).accessibilityLabel("Your learning cube. Drag to inspect.")
                    VStack(alignment: .leading, spacing: 16) {
                        Text(entry.canSolve ? "Your colors. Your lesson." : "Start with the cube in your hands.").font(.title2.bold())
                        Text("See the goal. Follow a move. Try it on your cube.")
                            .foregroundStyle(Color(white: 0.35))
                        if planning != nil {
                            ProgressView("Preparing your lesson…")
                            Button("Cancel") { cancelPlanning() }.frame(minHeight: 44)
                        } else if entry.canSolve {
                            Button("Learn with this cube") { prepareLesson() }.frame(maxWidth: .infinity).buttonStyle(CubePrimaryButton())
                        }
                        NavigationLink { ManualEntryView(entry: entry, forLearning: true) } label: {
                            Label(entry.filledCount == 0 ? "Enter my cube’s colors" : "Edit my cube’s colors", systemImage: "paintpalette")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .disabled(planning != nil)
                        if let error { Text(error).font(.callout).foregroundStyle(.red) }
                        Button("Try a practice cube") {
                            if entry.filledCount > 0 { confirmExample = true } else { loadExample() }
                        }.frame(maxWidth: .infinity, minHeight: 44).disabled(planning != nil)
                    }.cubeDrawer()
                }.padding(.top, 16).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .background(CubeStyle.stage.ignoresSafeArea()).foregroundStyle(.white)
            .navigationTitle("Learn").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CubeStyle.stage, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(isPresented: $showingPlan) {
                if let plan { LearningIntroduction(plan: plan) }
            }
            .confirmationDialog("Replace your entered colors with a practice cube?", isPresented: $confirmExample, titleVisibility: .visible) {
                Button("Use practice cube") { loadExample() }
            }
        }
        .onAppear { updatePreview() }
        .onChange(of: entry.stickers) { _, _ in cancelPlanning(); plan = nil; error = nil; updatePreview() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelPlanning() } }
        .onDisappear { cancelPlanning() }
    }
    private func updatePreview() { scene.showsTurnGuide = false; scene.showEntry(entry.stickers.map { $0?.colorID }) }
    private func loadExample() {
        entry.load(try! CubeState.solved().applying(MoveNotation.parse("R U R' U' F2 D L2 B")))
    }
    private func cancelPlanning() { planning?.cancel(); planning = nil }
    private func prepareLesson() {
        guard planning == nil, entry.canSolve, let cube = entry.cube else { return }
        error = nil
        planning = Task { @MainActor in
            do {
                let result = try await BeginnerSolver().plan(for: cube)
                try Task.checkCancellation()
                plan = result; showingPlan = true; planning = nil
            } catch is CancellationError { /* The caller clears its own task. */ }
            catch { if !Task.isCancelled { self.error = "We couldn’t prepare this lesson. Check the colors or try again."; planning = nil } }
        }
    }
}

/// Color and position stay together, including for users who cannot distinguish a swatch.
struct LearningColorCue: View {
    let color: CubeColorID
    let caption: String
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6).fill(Color(uiColor: color.uiColor))
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray, lineWidth: 1))
            Text("\(color.rawValue.capitalized) \(caption)").font(.subheadline.weight(.semibold))
        }.accessibilityElement(children: .combine)
    }
}

private struct LearningIntroduction: View {
    let plan: BeginnerPlan
    @State private var scene: CubeScene
    @State private var selected = 0
    init(plan: BeginnerPlan) {
        self.plan = plan
        let scene = CubeScene(cube: plan.solution.initialCube)
        scene.showsTurnGuide = false
        _scene = State(initialValue: scene)
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    Text(["Hold your cube like this", "Find a two-color edge", "Find a three-color corner"][selected])
                        .font(.title2.bold()).fontDesign(.rounded).padding(.horizontal, 24)
                    CubeViewport(scene: scene).frame(height: max(260, geometry.size.height - 330))
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Explore the pieces", selection: $selected) {
                            Text("Centers").tag(0)
                            Text("Edges").tag(1)
                            Text("Corners").tag(2)
                        }.pickerStyle(.segmented)
                        if selected == 0 {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 20) { holdingColors }
                                VStack(alignment: .leading, spacing: 12) { holdingColors }
                            }
                            Text("Keep these centers here as you follow the moves.")
                                .font(.subheadline).foregroundStyle(Color(white: 0.35))
                        } else {
                            Text(selected == 1 ? "Two colors, one piece. Find the white outline and drag to see both sides." : "Three colors, one piece. Find the white outline and drag to see all three sides.")
                                .font(.subheadline).foregroundStyle(Color(white: 0.35))
                        }
                        if plan.solution.moves.isEmpty {
                            Label("Your cube is already solved", systemImage: "checkmark.circle.fill").font(.headline)
                            Text("Go back and try a mixed cube.").font(.subheadline)
                        } else {
                            NavigationLink {
                                ManualSolutionView(solution: plan.solution, teachingPlan: plan, onComplete: {})
                            } label: { Text("Show my first goal").frame(maxWidth: .infinity) }.buttonStyle(CubePrimaryButton())
                        }
                    }.cubeDrawer()
                }.padding(.top, 20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
        }.background(CubeStyle.stage.ignoresSafeArea()).foregroundStyle(.white)
            .toolbar(.hidden, for: .tabBar)
            .navigationTitle("Meet your cube").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CubeStyle.stage, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { highlightExample() }
            .onChange(of: selected) { _, _ in highlightExample() }
    }
    @ViewBuilder private var holdingColors: some View {
        LearningColorCue(color: plan.solution.initialCube.centerColors[CubeFaceID.front.rawValue], caption: "toward you")
        LearningColorCue(color: plan.solution.initialCube.centerColors[CubeFaceID.up.rawValue], caption: "on top")
    }
    private func highlightExample() {
        scene.resetView()
        if selected == 0 {
            scene.sourceHighlights = [CubeFaceID.front.rawValue * 9 + 4, CubeFaceID.up.rawValue * 9 + 4]
        } else {
            let index = CubeFaceID.front.rawValue * 9 + (selected == 1 ? 1 : 2)
            let position = CubeRenderLayout.facelets[index].position
            scene.sourceHighlights = Set(CubeRenderLayout.facelets.filter { $0.position == position }.map(\.index))
        }
        scene.refreshHighlights()
    }
}

func holdingInstruction(for cube: CubeState) -> String {
    "Hold the \(cube.centerColors[CubeFaceID.front.rawValue].rawValue) center toward you and the \(cube.centerColors[CubeFaceID.up.rawValue].rawValue) center on top."
}

private struct SolveTimerView: View {
    @State private var started: ContinuousClock.Instant?
    @State private var lastTime: TimeInterval = 0
    @State private var interrupted = false
    @AppStorage("solveTimes") private var storedTimes = "[]"
    @AppStorage("bestSolveTime") private var bestTime = 0.0
    @Environment(\.scenePhase) private var scenePhase
    private var times: [Double] { (try? JSONDecoder().decode([Double].self, from: Data(storedTimes.utf8))) ?? [] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Image(systemName: "stopwatch").font(.largeTitle).foregroundStyle(CubeStyle.secondary)
                        Text(started == nil ? "Your pace. Your progress." : "You’ve got this.").font(.title2.bold()).fontDesign(.rounded)
                        Text(started == nil ? "Mix your cube. Start when you’re ready." : "Tap Stop when all six faces match.")
                            .foregroundStyle(CubeStyle.secondary).multilineTextAlignment(.center)
                    }.padding(.top, 40)
                    TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                        Text(Self.format(started.map { elapsed(since: $0) } ?? lastTime))
                            .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 130)
                            .accessibilityLabel("Elapsed time")
                    }
                    VStack(spacing: 16) {
                        Button(started == nil ? "Start solving" : "Stop timer") { toggleTimer() }
                            .frame(maxWidth: .infinity).buttonStyle(CubePrimaryButton())
                        if started != nil {
                            Button("Discard this attempt") { started = nil; lastTime = 0 }.frame(minHeight: 44)
                        } else if interrupted {
                            Text("Timing was interrupted. This attempt wasn’t saved.").font(.footnote).foregroundStyle(Color(white: 0.35))
                        }
                        if bestTime > 0 {
                            HStack { Text("Personal best"); Spacer(); Text(Self.format(bestTime)).monospacedDigit().bold() }
                        }
                    }.cubeDrawer()
                    if !times.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Recent solves").font(.headline)
                            ForEach(Array(times.prefix(10).enumerated()), id: \.offset) { index, time in
                                HStack { Text(index == 0 ? "Latest" : "\(index + 1) solves ago"); Spacer(); Text(Self.format(time)).monospacedDigit() }
                                    .foregroundStyle(CubeStyle.secondary)
                            }
                        }.padding(.horizontal, 24)
                    }
                }.padding(.bottom, 24).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.background(CubeStyle.stage.ignoresSafeArea()).foregroundStyle(.white)
                .navigationTitle("Time solving").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(CubeStyle.stage, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { interrupt() } }
        .onDisappear { interrupt() }
        .onChange(of: started) { _, start in UIApplication.shared.isIdleTimerDisabled = start != nil }
        .onAppear { if bestTime == 0, let best = times.min() { bestTime = best } }
    }
    private func elapsed(since start: ContinuousClock.Instant) -> Double {
        let parts = start.duration(to: .now).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
    private func interrupt() { if started != nil { started = nil; lastTime = 0; interrupted = true } }
    private func toggleTimer() {
        if let start = started {
            lastTime = elapsed(since: start); started = nil
            bestTime = bestTime == 0 ? lastTime : min(bestTime, lastTime)
            let updated = Array(([lastTime] + times).prefix(100))
            if let data = try? JSONEncoder().encode(updated), let json = String(data: data, encoding: .utf8) { storedTimes = json }
        } else { interrupted = false; started = .now }
    }
    static func format(_ time: Double) -> String {
        String(format: "%02d:%05.2f", Int(time) / 60, time.truncatingRemainder(dividingBy: 60))
    }
}

private struct CubeSettingsView: View {
    @AppStorage("slowMoves") private var slowMoves = true
    @AppStorage("solveTimes") private var storedTimes = "[]"
    @AppStorage("bestSolveTime") private var bestTime = 0.0
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Play moves slowly", isOn: $slowMoves)
                } header: { Text("Guidance") } footer: {
                    Text("Use slower animations in Solve and Learn. You can also change speed from the move screen.")
                }
                Section("Your data") {
                    Text("Cube colors and lessons are processed on this device. No account or internet connection is needed.")
                    Button("Clear saved solve times", role: .destructive) { confirmClear = true }
                }
                Section("About") {
                    LabeledContent("TwistTutor", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("Made for standard 3 × 3 cubes. Learn at your own pace, one move at a time.")
                }
            }.navigationTitle("Settings")
                .confirmationDialog("Clear all saved solve times?", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Clear times", role: .destructive) { storedTimes = "[]"; bestTime = 0 }
                }
        }
    }
}
