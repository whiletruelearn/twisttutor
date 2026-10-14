import SwiftUI
import CubeCore
import AppWorkflow

struct ManualEntryView: View {
    @State private var entry = ManualCubeEntry()
    @State private var scene = CubeScene()
    @State private var reviewing = false
    private var faceIndex: Int { ManualCubeEntry.faceOrder.firstIndex(of: face)! }
    @State private var face: CubeFaceID = .front
    @State private var paint: CubeColorID? = .white
    @State private var showSolution = false
    @State private var confirmClear = false
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(reviewing ? "Check your cube" : "Face \(faceIndex + 1) of 6 · \(face.title)").font(.title3.bold())
                    Spacer()
                    Menu("Entry options", systemImage: "ellipsis.circle") {
                        Button("Load solved example") { loadExample(scrambled: false) }
                        Button("Load mixed example") { loadExample(scrambled: true) }
                        Button("Clear all stickers", role: .destructive) { confirmClear = true }
                    }
                }
                Text("\(entry.completedFaceCount) of 6 faces entered · \(entry.filledCount)/54 stickers")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                ProgressView(value: Double(entry.filledCount), total: 54)
                if reviewing {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(ManualCubeEntry.faceOrder, id: \.self) { item in
                                Button { selectFace(item) } label: {
                                    VStack(spacing: 4) {
                                        Text(item.title).font(.subheadline.bold())
                                        Text("\(entry.filledCount(on: item))/9").font(.caption)
                                    }.padding(.horizontal, 10).frame(minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("\(item.title) face, \(entry.filledCount(on: item)) of 9 stickers")
                            }
                        }
                    }
                }
                if !reviewing {
                    Label("\(faceDescription(ManualCubeEntry.topNeighbor(of: face))) edge at top", systemImage: "arrow.up")
                        .font(.subheadline)
                }
                CubeViewport(scene: scene).frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(reviewing ? "Cube preview. Drag to inspect." : "\(face.title) face. Drag to rotate. Use accessible sticker buttons below to paint.")
                HStack {
                    Button(reviewing ? "Reset view" : "Face front", systemImage: "viewfinder") {
                        if reviewing { scene.resetView() } else { scene.focus(on: face) }
                    }
                    Spacer()
                    Button("Undo", systemImage: "arrow.uturn.backward") { entry.undo(); syncScene() }
                        .disabled(!entry.canUndo)
                }
                if !reviewing {
                    Text("Only the \(face.title.lowercased()) face is painted. Gray stickers are empty.")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("How to orient the cube") {
                        Text("Choose your Up and Front faces first and keep those names fixed. Rotate the whole cube to view each face; don’t twist its layers. Match the named edge at the top, select a color, then tap its stickers.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Sticker buttons") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(0..<9, id: \.self) { sticker(at: face.rawValue * 9 + $0) }
                        }.frame(maxWidth: 240).frame(maxWidth: .infinity)
                    }
                }
                validationFeedback

            }
            .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if !reviewing { palette }
                if entry.session.phase == .calculatingSolution {
                    ProgressView("Finding a verified solution…")
                    Button("Cancel calculation") { entry.session.cancelSolutionCalculation() }
                } else {
                    if reviewing {
                        Button("Solve my cube") { solve() }
                            .buttonStyle(.borderedProminent).disabled(!entry.canSolve)
                    } else {
                        HStack {
                            Button("Previous face") { selectFace(ManualCubeEntry.faceOrder[faceIndex - 1]) }
                                .disabled(faceIndex == 0)
                            Spacer()
                            if faceIndex < 5 {
                                Button("Next face") { selectFace(ManualCubeEntry.faceOrder[faceIndex + 1]) }
                                    .buttonStyle(.borderedProminent)
                            } else {
                                Button("Review cube") { review() }.buttonStyle(.borderedProminent)
                            }
                        }
                        if entry.filledCount == 54 && faceIndex < 5 { Button("Review cube") { review() } }
                    }
                }
                Text(entry.validation?.isValid == false ? "Check colors — scroll for details" : "\(entry.filledCount) of 54 stickers entered")
                    .font(.footnote.monospacedDigit())
            }
            .padding().frame(maxWidth: .infinity).background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle("Your cube").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear all 54 stickers?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear stickers", role: .destructive) { entry.clear(); errorMessage = nil; selectFace(.front); syncScene() }
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { entry.session.cancelSolutionCalculation() }
        }
        .onAppear { syncScene(); if reviewing { scene.resetView() } else { scene.focus(on: face) } }
        .onDisappear { entry.session.cancelSolutionCalculation(); scene.onPaint = nil }

    }

    private var palette: some View {
        VStack(spacing: 8) {
            HStack {
                Text(paint.map { "Painting \($0.rawValue)" } ?? "Erasing stickers").font(.subheadline.bold())
                Spacer()
                Button("Erase", systemImage: "eraser") { paint = nil }
                    .accessibilityAddTraits(paint == nil ? .isSelected : [])
            }
            HStack(spacing: 4) {
                ForEach(CubeColorID.allCases, id: \.self) { color in
                    Button { paint = color } label: {
                        VStack(spacing: 3) {
                            Circle().fill(Color(uiColor: color.uiColor)).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(.gray, lineWidth: 1))
                                .overlay { if paint == color { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black) } }
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
        scene.onPaint = reviewing ? nil : { index in
            do { try entry.setColor(paint, at: index); errorMessage = nil; syncScene() }
            catch { errorMessage = "That sticker could not be updated. Please try again." }
        }
    }

    private func faceDescription(_ face: CubeFaceID) -> String {
        let name = "\(face.title) (\(face.notation))"
        guard let color = entry.stickers[face.rawValue * 9 + 4]?.colorID else { return name }
        return "\(color.rawValue.capitalized) / \(name)"
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
                .font(.subheadline).foregroundStyle(.secondary)
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
