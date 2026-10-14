import SwiftUI
import CubeCore

struct ContentView: View {
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
                        NavigationLink { ManualEntryView() } label: {
                            Text("Let’s solve your cube").frame(maxWidth: .infinity)
                        }.buttonStyle(CubePrimaryButton())
                        NavigationLink("Just explore") { CubeExplorerView() }
                            .frame(minHeight: 44)
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
    func cubeDrawer() -> some View {
        self.padding(20).frame(maxWidth: .infinity)
            .foregroundStyle(Color.primary).background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28))
            .environment(\.colorScheme, .light).tint(CubeStyle.action)
    }
}

private struct CubeExplorerView: View {
    @State private var scene = CubeScene()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 0) {
            CubeViewport(scene: scene).frame(height: 260)
            ScrollView {
                VStack(spacing: 20) { controls; turnControls }.cubeDrawer()
            }
        }.frame(maxWidth: 700).frame(maxWidth: .infinity).background(CubeStyle.stage.ignoresSafeArea())
            .navigationTitle("Explore moves").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CubeStyle.stage, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                Menu {
                    Button("Reset view") { scene.resetView() }
                    Button("Solved cube") { scene.loadExample(scrambled: false) }
                    Button("Mixed cube") { scene.loadExample(scrambled: true) }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Cube options")
            }
            .onChange(of: scene.selectedFace) { _, _ in scene.refreshHighlights() }
            .onChange(of: scene.amount) { _, _ in scene.refreshHighlights() }
            .onChange(of: scene.highlightPiece) { _, _ in scene.refreshHighlights() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { scene.cancel() } }
            .onDisappear { scene.cancel() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(scene.playback.cube.isSolved ? "Solved cube" : "Mixed cube").font(.headline)
                Spacer()
                if let index = scene.selectedIndex {
                    Text("\(scene.playback.cube.stickers[index].colorID.rawValue.capitalized) · \(CubeFaceID(rawValue: index / 9)!.title) \(index % 9 + 1)")
                        .font(.caption).foregroundStyle(Color(white: 0.35))
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                ForEach(CubeFaceID.allCases, id: \.self) { face in
                    Button { scene.selectedFace = face; scene.selectedIndex = nil; scene.highlightPiece = false; scene.refreshHighlights() } label: {
                        Text(face.notation).font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(scene.selectedFace == face ? .accentColor : .secondary)
                    .accessibilityLabel("\(face.title) face")
                    .accessibilityAddTraits(scene.selectedFace == face ? .isSelected : [])
                }
            }
            .disabled(scene.playback.isBusy)
            Picker("Turn direction", selection: $scene.amount) {
                Text("Clockwise").tag(TurnAmount.clockwise)
                Text("Counterclockwise").tag(TurnAmount.counterclockwise)
                Text("Half turn").tag(TurnAmount.half)
            }.pickerStyle(.menu).disabled(scene.playback.isBusy)

            Text("Directions are viewed looking straight at the selected face.")
                .font(.footnote).foregroundStyle(Color(white: 0.35))
            HStack {
                Toggle("Slow motion", isOn: $scene.slow).disabled(scene.playback.isBusy)
                Spacer(minLength: 24)
                Button { scene.replay() } label: { Label("Replay", systemImage: "arrow.counterclockwise") }
                    .disabled(scene.playback.lastTurn == nil || scene.playback.isBusy)
            }
            Toggle("Highlight selected piece", isOn: $scene.highlightPiece)
                .disabled(scene.selectedIndex == nil || scene.playback.isBusy)
        }
    }

    private var turnControls: some View {
        VStack(spacing: 6) {
            Button { scene.turn() } label: {
                Label("Turn \(CubeMove(scene.selectedFace, scene.amount).notation)",
                      systemImage: scene.amount == .counterclockwise ? "arrow.counterclockwise" : "arrow.clockwise")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(CubePrimaryButton()).disabled(scene.playback.isBusy)
            .accessibilityHint("Turns the \(scene.selectedFace.title.lowercased()) face. Replay shows the last turn again without changing the result.")
            Text(scene.playback.activeTurn.map { "Playing \($0.move.notation)…" } ?? scene.playback.lastTurn.map { "Last turn: \($0.move.notation)" } ?? "Choose a face, then try a turn.")
                .font(.footnote).foregroundStyle(Color(white: 0.35)).frame(maxWidth: .infinity)
                .accessibilityIdentifier("playbackStatus")
        }
    }
}
