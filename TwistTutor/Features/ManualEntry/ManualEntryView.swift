import SwiftUI
import CubeCore
import AppWorkflow

struct ManualEntryView: View {
    @State private var entry: ManualCubeEntry
    let forLearning: Bool
    @Environment(\.dismiss) private var dismiss

    @MainActor init() { self.init(entry: ManualCubeEntry()) }

    init(entry: ManualCubeEntry, forLearning: Bool = false) {
        _entry = State(initialValue: entry)
        self.forLearning = forLearning
    }
    @State private var scene = CubeScene()
    @State private var reviewing = false
    @State private var inspecting = false
    @State private var showDetails = false
    @Environment(\.dynamicTypeSize) private var textSize
    private var faceIndex: Int { ManualCubeEntry.faceOrder.firstIndex(of: face)! }
    @State private var face: CubeFaceID = .front
    @State private var paint: CubeColorID? = .white
    @State private var showSolution = false
    @State private var confirmClear = false
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    faceProgress.padding(.horizontal, 20).padding(.top, 8)
                    ZStack(alignment: .topTrailing) {
                        CubeViewport(scene: scene)
                            .accessibilityLabel(reviewing || inspecting ? "Cube preview. Drag to inspect." : "\(face.title) face. Painting view is fixed. Sticker buttons are available in Help.")
                        VStack(spacing: 12) {
                            stageButton("Undo", icon: "arrow.uturn.backward", disabled: !entry.canUndo) { entry.undo(); syncScene() }
                            stageButton(inspecting || reviewing ? "Reset" : "Inspect", icon: inspecting || reviewing ? "viewfinder" : "cube.transparent") {
                                if reviewing || inspecting { scene.resetView() }
                                else { inspecting = true; syncScene(); scene.resetView() }
                            }
                        }.padding(.top, 16).padding(.trailing, 16)
                    }
                    .frame(height: max(240, geometry.size.height - (textSize.isAccessibilitySize ? 480 : inspecting && !reviewing ? 220 : face == .up || face == .down ? 440 : 360)))
                    if !reviewing && !inspecting && (face == .up || face == .down) {
                        neighboringColors.padding(.horizontal, 24).padding(.bottom, 12)
                    }
                    VStack(spacing: 6) {
                        Text(reviewing ? "Ready for the first move?" : inspecting ? "Take a look around" : "Match the \(face.title.lowercased()) face")
                            .font(.title2.bold()).fontDesign(.rounded)
                        Text(reviewing ? "Check all six sides. Tap a face above to edit." : inspecting ? "Drag to rotate. Your colors stay unchanged." : "Use Inspect to see how to hold and paint your cube.")
                            .font(.subheadline).foregroundStyle(CubeStyle.secondary).multilineTextAlignment(.center)
                    }.padding(.horizontal, 24).padding(.bottom, 20)
                    entryDrawer
                }.frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
        }
        .background(CubeStyle.stage.ignoresSafeArea()).foregroundStyle(.white)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(reviewing ? "Review your cube" : "Your cube").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CubeStyle.stage, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Help & sticker buttons", systemImage: "questionmark.circle") { showDetails = true }
                    Button("Load solved example") { loadExample(scrambled: false) }
                    Button("Load mixed example") { loadExample(scrambled: true) }
                    Button("Clear all stickers", role: .destructive) { confirmClear = true }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel("Entry options")
            }
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Keep your bearings").font(.title2.bold())
                        Text("Choose a front and top face on your real cube. Keep those names fixed. Rotate the whole cube to match the face shown here; don’t turn individual layers yet.")
                        Text("\(face.title) sticker buttons").font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(0..<9, id: \.self) { sticker(at: face.rawValue * 9 + $0) }
                        }.frame(maxWidth: 300).frame(maxWidth: .infinity)
                        palette
                        validationFeedback
                    }.padding(24)
                }.navigationTitle("Entry help").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { showDetails = false } }
            }.foregroundStyle(.primary).environment(\.colorScheme, .light)
        }
        .confirmationDialog("Clear all 54 stickers?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear stickers", role: .destructive) { entry.clear(); errorMessage = nil; selectFace(.front) }
        }
        .navigationDestination(isPresented: $showSolution) {
            if let solution = entry.session.solution {
                ManualSolutionView(solution: solution) {
                    if entry.session.phase == .solving { try? entry.session.complete() }
                }
            }
        }
        .onChange(of: showSolution) { _, presented in if !presented { entry.session.leave() } }
        .onChange(of: entry.session.solution) { _, solution in showSolution = solution != nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { entry.session.cancelSolutionCalculation() } }
        .onAppear { syncScene(); if reviewing || inspecting { scene.resetView() } else { scene.focus(on: face) } }
        .onDisappear { entry.session.cancelSolutionCalculation(); scene.onPaint = nil }
    }

    private var neighboringColors: some View {
        VStack(spacing: 8) {
            Text("Colors beside this face").font(.caption).foregroundStyle(CubeStyle.secondary)
            HStack(spacing: 14) {
                ForEach([CubeFaceID.front, .right, .back, .left], id: \.self) { neighbor in
                    VStack(spacing: 4) {
                        Text(neighbor.title).font(.caption2)
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { column in
                                let index = neighbor.rawValue * 9 + (face == .up ? 0 : 6) + column
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(entry.stickers[index].map { Color(uiColor: $0.colorID.uiColor) } ?? Color.gray)
                                    .frame(maxWidth: .infinity).frame(height: 16)
                                    .accessibilityLabel("\(neighbor.title) adjacent sticker \(column + 1), \(entry.stickers[index]?.colorID.rawValue ?? "empty")")
                            }
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var faceProgress: some View {
        HStack(spacing: 4) {
            ForEach(ManualCubeEntry.faceOrder, id: \.self) { item in
                Button { selectFace(item) } label: {
                    VStack(spacing: 7) {
                        Text(item.title).font(.caption.weight(face == item && !reviewing ? .bold : .regular))
                        Capsule().fill(entry.filledCount(on: item) == 9 ? Color.green : face == item && !reviewing ? Color.white : Color.white.opacity(0.18)).frame(height: 3)
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain)
                    .foregroundStyle(face == item && !reviewing ? Color.white : CubeStyle.secondary)
                    .accessibilityLabel("\(item.title), \(entry.filledCount(on: item)) of 9 stickers")
                    .accessibilityAddTraits(face == item && !reviewing ? .isSelected : [])
            }
        }
    }

    private func stageButton(_ title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2)
            }.frame(width: 58, height: 58)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.35 : 1)
    }

    private var entryDrawer: some View {
        VStack(spacing: 14) {
            if inspecting && !reviewing {
                Button { inspecting = false; syncScene(); scene.focus(on: face) } label: {
                    Text("Back to painting").frame(maxWidth: .infinity)
                }.buttonStyle(CubePrimaryButton())
            } else {
                if !reviewing { palette }
                if entry.session.phase == .calculatingSolution {
                    ProgressView("Finding your solution…")
                    Button("Cancel") { entry.session.cancelSolutionCalculation() }
                } else if reviewing {
                    validationFeedback
                    Button { if forLearning { dismiss() } else { solve() } } label: { Text(forLearning ? "Use this cube to learn" : "Show me the moves").frame(maxWidth: .infinity) }
                        .buttonStyle(CubePrimaryButton()).disabled(!entry.canSolve)
                } else {
                    HStack(spacing: 12) {
                        Button { selectFace(ManualCubeEntry.faceOrder[faceIndex - 1]) } label: {
                            Image(systemName: "arrow.left").frame(width: 48, height: 52)
                        }.disabled(faceIndex == 0).accessibilityLabel("Previous face")
                        Button {
                            if entry.filledCount == 54 || faceIndex == 5 { review() }
                            else { selectFace(ManualCubeEntry.faceOrder[faceIndex + 1]) }
                        } label: {
                            Text(entry.filledCount == 54 || faceIndex == 5 ? "Review cube" : "Continue").frame(maxWidth: .infinity)
                        }.buttonStyle(CubePrimaryButton()).disabled(entry.filledCount(on: face) != 9)
                    }
                    if entry.filledCount(on: face) != 9 {
                        Text("\(9 - entry.filledCount(on: face)) stickers left on this face").font(.caption).foregroundStyle(Color(white: 0.35))
                    }
                    if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                }
            }
        }.cubeDrawer()
    }

    private var palette: some View {
        VStack(spacing: 8) {
            HStack {
                Text(paint.map { "Painting \($0.rawValue)" } ?? "Erasing stickers").font(.subheadline.bold())
                Spacer()
                Button("Erase", systemImage: "eraser") { paint = nil }
                    .accessibilityAddTraits(paint == nil ? .isSelected : [])
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: textSize.isAccessibilitySize ? 3 : 6), spacing: 8) {
                ForEach(CubeColorID.allCases, id: \.self) { color in
                    Button { paint = color } label: {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: color.uiColor)).frame(height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.15), lineWidth: 1))
                                .overlay { if paint == color { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.black, .white) } }
                            Text(color.rawValue.capitalized).font(.caption2)
                            Text(entry.count(color) > 9 ? "\(entry.count(color) - 9) extra" : "\(9 - entry.count(color)) left")
                                .font(.caption2.monospacedDigit())
                        }.frame(maxWidth: .infinity, minHeight: 64)
                            .padding(.vertical, 4)
                            .background(paint == color ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Paint \(color.rawValue), \(entry.count(color)) of 9 entered")
                    .accessibilityAddTraits(paint == color ? .isSelected : [])
                }
            }
        }
    }

    private func selectFace(_ selected: CubeFaceID) {
        inspecting = false
        reviewing = false
        face = selected
        syncScene()
        scene.focus(on: selected)
    }

    private func review() {
        reviewing = true
        syncScene()
        scene.resetView()
    }

    private func syncScene() {
        scene.showEntry(entry.stickers.map { $0?.colorID })
        scene.allowsOrbit = reviewing || inspecting
        scene.onPaint = reviewing || inspecting ? nil : { index in
            do { try entry.setColor(paint, at: index); errorMessage = nil; syncScene() }
            catch { errorMessage = "That sticker could not be updated. Please try again." }
        }
    }

    private func faceDescription(_ face: CubeFaceID) -> String {
        let name = "the \(face.title.lowercased()) edge"
        guard let color = entry.stickers[face.rawValue * 9 + 4]?.colorID else { return name }
        return "\(color.rawValue) (\(face.title.lowercased()))"
    }

    private func sticker(at index: Int) -> some View {
        let color = entry.stickers[index]?.colorID
        return Button {
            do { try entry.setColor(paint, at: index); errorMessage = nil; syncScene() }
            catch { errorMessage = "That sticker could not be updated. Please try again." }
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.map { Color(uiColor: $0.uiColor) } ?? Color(uiColor: .tertiarySystemFill))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.35), lineWidth: 1))
                .overlay {
                    Text(color == nil ? "?" : (index % 9 == 4 ? face.notation : ""))
                        .font(.title2.bold()).foregroundStyle(color == nil ? Color.primary : .black)
                }
                .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(face.title) sticker \(index % 9 + 1), \(color?.rawValue ?? "empty")\(index % 9 == 4 ? ", center" : "")")
        .accessibilityHint(paint.map { "Paint \($0.rawValue)" } ?? "Erase color")
        .accessibilityIdentifier("manualSticker\(index)")
    }

    @ViewBuilder private var validationFeedback: some View {
        if let report = entry.validation {
            if report.isValid {
                Label(entry.cube?.isSolved == true ? "Valid cube · already solved" : "Valid cube · ready to solve", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Check your colors", systemImage: "exclamationmark.triangle").font(.headline)
                    ForEach(Array(report.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        Text(diagnostic.manualEntryMessage).font(.subheadline)
                    }
                }
            }
        } else {
            Text("Fill the remaining \(54 - entry.filledCount) stickers to check whether this cube can be solved.")
                .font(.subheadline).foregroundStyle(Color(white: 0.35))
        }
        if let message = errorMessage ?? entry.session.errorMessage {
            Text(message).foregroundStyle(.red).font(.subheadline)
        }
    }

    private func loadExample(scrambled: Bool) {
        let solved = try! CubeState.solved()
        let moves = try! MoveNotation.parse("R U R' U' F2 D L2 B")
        entry.load(scrambled ? solved.applying(moves) : solved)
        errorMessage = nil
        syncScene()
    }

    private func solve() {
        do { try entry.solve(); errorMessage = nil }
        catch { errorMessage = "Couldn’t start the solution. Review your entry and try again." }
    }
}
