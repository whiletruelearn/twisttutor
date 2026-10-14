import SwiftUI
import CubeCore
import AppWorkflow

struct ManualEntryView: View {
    @State private var entry = ManualCubeEntry()
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
                    Text("Paint each sticker").font(.headline)
                    Spacer()
                    Menu("Entry options", systemImage: "ellipsis.circle") {
                        Button("Load solved example") { loadExample(scrambled: false) }
                        Button("Load mixed example") { loadExample(scrambled: true) }
                        Button("Clear all stickers", role: .destructive) { confirmClear = true }
                    }
                }
                Text("Choose a color below, then tap the grid.").font(.subheadline).foregroundStyle(.secondary)
                DisclosureGroup("How to orient the cube") {
                    Text("Choose your Up and Front faces first and keep those names fixed. Rotate the whole cube to view each face; don’t twist its layers.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.font(.subheadline)
                Picker("Face to enter", selection: $face) {
                    ForEach(CubeFaceID.allCases, id: \.self) { Text($0.notation).tag($0) }
                }.pickerStyle(.segmented)
                VStack(spacing: 8) {
                    Text("\(face.title) (\(face.notation)) face").font(.title3.bold())
                    Label("\(faceDescription(ManualCubeEntry.topNeighbor(of: face))) edge at top", systemImage: "arrow.up")
                        .font(.subheadline).multilineTextAlignment(.center)
                    Text("Look straight at the \(faceDescription(face)) face.")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(0..<9, id: \.self) { local in
                            sticker(at: face.rawValue * 9 + local)
                        }
                    }.frame(maxWidth: 210)
                }.frame(maxWidth: .infinity)
                HStack {
                    Text(paint.map { "Painting \($0.rawValue)" } ?? "Erasing stickers").font(.headline)
                    Spacer()
                    Button("Erase", systemImage: "eraser") { paint = nil }
                        .accessibilityAddTraits(paint == nil ? .isSelected : [])
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(CubeColorID.allCases, id: \.self) { color in
                        Button { paint = color } label: {
                            VStack(spacing: 4) {
                                HStack(spacing: 5) {
                                    Circle().fill(Color(uiColor: color.uiColor)).frame(width: 14, height: 14)
                                        .overlay(Circle().stroke(.gray, lineWidth: 0.5))
                                    Text(color.rawValue.capitalized).font(.subheadline)
                                }
                                Text("\(entry.count(color))/9").font(.caption.monospacedDigit())
                            }.frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered).tint(paint == color ? .accentColor : .secondary)
                        .accessibilityLabel("Paint \(color.rawValue), \(entry.count(color)) of 9 entered")
                        .accessibilityAddTraits(paint == color ? .isSelected : [])
                    }
                }
                validationFeedback
                Text("Manual-entry test flow · No camera needed")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if entry.session.phase == .calculatingSolution {
                    ProgressView("Finding a verified solution…")
                    Button("Cancel calculation") { entry.session.cancelSolutionCalculation() }
                } else {
                    Button("Validate & solve") { solve() }
                        .buttonStyle(.borderedProminent).disabled(!entry.canSolve)
                }
                Text(entry.validation?.isValid == false ? "Check colors — scroll for details" : "\(entry.filledCount) of 54 stickers entered")
                    .font(.footnote.monospacedDigit())
            }
            .padding().frame(maxWidth: .infinity).background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle("Enter cube manually").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear all 54 stickers?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear stickers", role: .destructive) { entry.clear(); errorMessage = nil }
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
        .onDisappear { entry.session.cancelSolutionCalculation() }
    }

    private func faceDescription(_ face: CubeFaceID) -> String {
        let name = "\(face.title) (\(face.notation))"
        guard let color = entry.stickers[face.rawValue * 9 + 4]?.colorID else { return name }
        return "\(color.rawValue.capitalized) / \(name)"
    }

    private func sticker(at index: Int) -> some View {
        let color = entry.stickers[index]?.colorID
        return Button {
            do { try entry.setColor(paint, at: index); errorMessage = nil }
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
    }

    private func solve() {
        do { try entry.solve(); errorMessage = nil }
        catch { errorMessage = "Couldn’t start the solution. Review your entry and try again." }
    }
}
