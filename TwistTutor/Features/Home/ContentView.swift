import SwiftUI
import CubeCore

struct ContentView: View {
    @State private var scene = CubeScene()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text("Explore your cube").font(.title2.bold())
                            Text("Drag to look around. Tap a sticker to inspect.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        CubeViewport(scene: scene)
                            .frame(height: min(300, max(220, geometry.size.height * 0.34)))
                            .overlay(alignment: .bottomTrailing) {
                                Button { scene.resetView() } label: {
                                    Label("Reset view", systemImage: "viewfinder")
                                        .font(.subheadline)
                                }.buttonStyle(.bordered).padding(8)
                            }
                        NavigationLink { ScanView() } label: {
                            Label("Scan your cube", systemImage: "camera")
                        }.buttonStyle(.borderedProminent)
                        NavigationLink { ManualEntryView() } label: {
                            Label("Enter cube manually", systemImage: "square.grid.3x3")
                        }.buttonStyle(.bordered)
                        controls
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .safeAreaInset(edge: .bottom) {
                turnControls.padding(.horizontal, 20).padding(.vertical, 10)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
                    .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("TwistTutor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Solved cube") { scene.loadExample(scrambled: false) }
                        Button("Mixed cube") { scene.loadExample(scrambled: true) }
                    } label: { Label("Examples", systemImage: "cube") }
                    .disabled(scene.playback.isBusy)
                }
            }
        }
        .onChange(of: scene.selectedFace) { _, _ in scene.refreshHighlights() }
        .onChange(of: scene.amount) { _, _ in scene.refreshHighlights() }
        .onChange(of: scene.highlightPiece) { _, _ in scene.refreshHighlights() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scene.cancel() } }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(scene.playback.cube.isSolved ? "Solved cube" : "Mixed cube").font(.headline)
                Spacer()
                if let index = scene.selectedIndex {
                    Text("\(scene.playback.cube.stickers[index].colorID.rawValue.capitalized) · \(CubeFaceID(rawValue: index / 9)!.title) \(index % 9 + 1)")
                        .font(.caption).foregroundStyle(.secondary)
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
                .font(.footnote).foregroundStyle(.secondary)
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
            .buttonStyle(.borderedProminent).disabled(scene.playback.isBusy)
            .accessibilityHint("Turns the \(scene.selectedFace.title.lowercased()) face. Replay shows the last turn again without changing the result.")
            Text(scene.playback.activeTurn.map { "Playing \($0.move.notation)…" } ?? scene.playback.lastTurn.map { "Last turn: \($0.move.notation)" } ?? "Choose a face, then try a turn.")
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                .accessibilityIdentifier("playbackStatus")
        }
    }
}

#Preview { ContentView() }
