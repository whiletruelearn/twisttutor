import CubeCore

/// The words a patient teacher would use. Colors come from the learner's own centers,
/// and turn directions are described from the hands holding the cube, never from notation.
public struct CoachColors: Equatable, Sendable {
    public let top: CubeColorID
    public let bottom: CubeColorID
    public let front: CubeColorID
    public init(cube: CubeState) {
        top = cube.centerColors[CubeFaceID.up.rawValue]
        bottom = cube.centerColors[CubeFaceID.down.rawValue]
        front = cube.centerColors[CubeFaceID.front.rawValue]
    }
}

public enum CubeLayer: Int, CaseIterable, Sendable {
    case bottom, middle, top
    public var title: String { ["Bottom layer", "Middle layer", "Top layer"][rawValue] }
    public var stages: [BeginnerStage] { BeginnerStage.allCases.filter { $0.layer == self } }
}

extension BeginnerStage: Identifiable {
    public var id: Int { rawValue }
    public var number: Int { rawValue + 1 }
    public var layer: CubeLayer {
        switch self {
        case .cross, .firstCorners: .bottom
        case .middleEdges: .middle
        default: .top
        }
    }

    public func headline(_ c: CoachColors) -> String {
        switch self {
        case .cross: "Make a \(c.bottom.name) cross"
        case .firstCorners: "Fill in the bottom corners"
        case .middleEdges: "Fill the middle layer"
        case .topCross: "Make a \(c.top.name) cross on top"
        case .topFace: "Make the whole top \(c.top.name)"
        case .topCorners: "Put the top corners in place"
        case .topEdges: "Finish the last edges"
        }
    }

    /// What we are making and why it matters, said the way you would say it across a table.
    public func introduction(_ c: CoachColors) -> String {
        switch self {
        case .cross:
            "We build the cube from the bottom up, like a house. First, a plus sign of \(c.bottom.name) around the \(c.bottom.name) center on the bottom. It’s the foundation for everything else."
        case .firstCorners:
            "Your cross has four gaps between its arms. Each gap gets a corner with \(c.bottom.name) on it. Fill all four and the whole bottom layer is done."
        case .middleEdges:
            "The bottom layer is finished, so we move up one row. Four edges belong between the side centers. You can spot them easily: they’re the edges with no \(c.top.name) on them."
        case .topCross:
            "Only the top layer is left. We’ll take it in small steps. First, make a \(c.top.name) plus sign on top. Ignore the sides for now."
        case .topFace:
            "Your top has a \(c.top.name) cross. Now we turn the corners so the entire top becomes \(c.top.name)."
        case .topCorners:
            "The top is \(c.top.name), but some corners are sitting in the wrong spots. We’ll swap them until each corner’s side colors match the sides it touches."
        case .topEdges:
            "This is the last step. A few top edges are in the wrong places. One pattern moves three of them around at once."
        }
    }

    /// The single thing beginners most often miss in this stage.
    public func tip(_ c: CoachColors) -> String {
        switch self {
        case .cross:
            "An arm only counts when its other color matches the center beside it. The \(c.bottom.name)–\(c.front.name) edge belongs under the \(c.front.name) center, not just anywhere."
        case .firstCorners:
            "First turn the top so the corner sits right above its gap. Then the short pattern drops it in. Sometimes you repeat it two or three times — that’s normal."
        case .middleEdges:
            "Halfway through each pattern, your bottom layer will look broken. Don’t stop. It comes back together by the last move."
        case .topCross:
            "You might see a dot, an L shape or a line of \(c.top.name) on top. The same pattern works for all of them. You may need it more than once."
        case .topFace:
            "The pattern twists corners in place. It can look like it made things worse at first. Trust it and keep going."
        case .topCorners:
            "Keep your eyes on the corners. The edges may shuffle around too — we fix those last."
        case .topEdges:
            "Every move counts here. If something looks off afterwards, step back a few moves and redo them slowly."
        }
    }

    /// How the learner can tell, with the real cube in their hands, that the goal is reached.
    public func doneWhen(_ c: CoachColors) -> String {
        switch self {
        case .cross: "Tip your cube up: you’ll see a \(c.bottom.name) plus on the bottom, and each arm’s side color matches the center above it."
        case .firstCorners: "The whole bottom is \(c.bottom.name), and the bottom row on every side matches its center."
        case .middleEdges: "The bottom two rows on every side match their centers. Only the top row is still mixed."
        case .topCross: "There’s a \(c.top.name) plus on top. Its side colors don’t need to match yet."
        case .topFace: "The entire top is \(c.top.name). The top row on the sides can still be mixed."
        case .topCorners: "Every top corner’s side colors match the centers below them."
        case .topEdges: "All six sides are a single color each."
        }
    }

    /// What a teacher says when you get there.
    public var celebration: String {
        switch self {
        case .cross: "Your cross is done!"
        case .firstCorners: "First layer solved!"
        case .middleEdges: "Two layers done!"
        case .topCross: "Top cross made!"
        case .topFace: "The top is one color!"
        case .topCorners: "Corners are home!"
        case .topEdges: "You solved your cube!"
        }
    }

    public var encouragement: String {
        switch self {
        case .cross: "This is the hardest step to see, and you just did it."
        case .firstCorners: "A third of the cube is finished. That’s a real milestone."
        case .middleEdges: "You’re past the halfway point. The rest happens on top."
        case .topCross: "Three small steps left, all on the top layer."
        case .topFace: "Two steps to go. You’re close."
        case .topCorners: "Just one step left."
        case .topEdges: "Every face matches. Mix it up and try again — it gets easier each time."
        }
    }
}

extension BeginnerLesson {
    /// One line naming what this group of turns achieves.
    public func headline(_ c: CoachColors) -> String {
        if isSetupOnly { return "Line up the top layer" }
        switch stage {
        case .cross:
            guard let side = piece?.sideColors(excluding: c.bottom).first else { return "Bring a cross edge home" }
            return "Bring the \(c.bottom.name)–\(side.name) edge home"
        case .firstCorners:
            guard let sides = piece?.sideColors(excluding: c.bottom), sides.count == 2 else { return "Drop in a bottom corner" }
            return "Drop in the \(c.bottom.name)–\(sides[0].name)–\(sides[1].name) corner"
        case .middleEdges:
            guard let colors = piece?.colors, colors.count == 2 else { return "Tuck in a middle edge" }
            if !placesPiece { return "Lift out the \(colors[0].name)–\(colors[1].name) edge" }
            return "Tuck in the \(colors[0].name)–\(colors[1].name) edge"
        case .topCross: return "Flip the top edges"
        case .topFace: return "Twist the top corners"
        case .topCorners: return "Swap the top corners"
        case .topEdges: return "Cycle the top edges"
        }
    }

    /// What to look for and what is about to happen, before the first turn.
    public func coaching(_ c: CoachColors) -> String {
        if isSetupOnly { return "Turn only the top layer until its side colors line up with the centers below." }
        switch stage {
        case .cross:
            guard let side = piece?.sideColors(excluding: c.bottom).first else {
                return "Follow the turns. An edge might leave the bottom for a moment before it comes back the right way round."
            }
            return "Find the edge with \(c.bottom.name) and \(side.name). It goes under the \(side.name) center with \(c.bottom.name) facing down. It may take a detour on the way."
        case .firstCorners:
            guard let sides = piece?.sideColors(excluding: c.bottom), sides.count == 2 else { return "Park the corner above its gap, then drop it in." }
            let park = setupMoveCount > 0 ? "First turn the top until it sits right above its gap. Then a" : "A"
            return "This corner lives between the \(sides[0].name) and \(sides[1].name) centers. \(park) short pattern drops it in. If it’s stuck on the bottom, or comes in twisted, the pattern repeats — that’s expected."
        case .middleEdges:
            guard let colors = piece?.colors, colors.count == 2 else { return "Line the edge up, then tuck it into the middle." }
            if !placesPiece {
                return "This edge is stuck in the middle layer — in the wrong spot or flipped. Running the pattern once lifts it up to the top, so we can tuck it back in properly."
            }
            let park = setupMoveCount > 0 ? "First turn the top to line it up. " : ""
            return "This edge belongs between the \(colors[0].name) and \(colors[1].name) centers. \(park)Then the pattern tucks it in. The bottom will look broken mid-way — keep going."
        case .topCross:
            return "Keep holding the cube exactly as shown. This pattern flips top edges so more \(c.top.name) appears on top."
        case .topFace:
            return "Keep the \(c.top.name) cross on top. This pattern twists the top corners; repeating it from the right angle finishes the top."
        case .topCorners:
            return "This pattern swaps two top corners. The rest of the cube returns to how it was by the last move."
        case .topEdges:
            return "This pattern moves three top edges around while the corners stay put."
        }
    }

    /// Where a given move in this lesson sits, in plain words.
    public func phase(of moveIndex: Int) -> String {
        if isSetupOnly { return "Line up the top" }
        if moveIndex < patternRange.lowerBound {
            return "Get ready · turn the top"
        }
        let turn = "turn \(moveIndex - patternRange.lowerBound + 1) of \(patternRange.count)"
        // The cross is steered with single turns; there is no pattern to memorize.
        return stage == .cross ? turn.prefix(1).uppercased() + turn.dropFirst() : "The pattern · \(turn)"
    }
}

extension TeachingPiece {
    func sideColors(excluding bottom: CubeColorID) -> [CubeColorID] {
        zip(colors, destinationFaces).filter { $0.1 != .down }.map(\.0)
    }
}

extension CubeColorID {
    public var name: String { rawValue }
}

extension CubeFaceID {
    /// Where this face is, from the learner's hands.
    public var whereFromHands: String {
        ["on top", "on the right", "facing you", "on the bottom", "on the left", "at the back"][rawValue]
    }
}

extension CubeMove {
    /// The turn said from the learner's hands, holding the front center toward them and the top center up.
    public var spokenInstruction: String {
        let twice = amount == .half
        switch face {
        case .up: return twice ? "Turn the top layer twice" : "Turn the top layer to the \(amount == .clockwise ? "left" : "right")"
        case .down: return twice ? "Turn the bottom layer twice" : "Turn the bottom layer to the \(amount == .clockwise ? "right" : "left")"
        case .right: return twice ? "Turn the right side twice" : "Turn the right side \(amount == .clockwise ? "up" : "down")"
        case .left: return twice ? "Turn the left side twice" : "Turn the left side \(amount == .clockwise ? "down" : "up")"
        case .front: return twice ? "Turn the front face twice" : "Turn the front face \(amount == .clockwise ? "clockwise" : "counterclockwise")"
        case .back: return twice ? "Turn the back face twice" : "Turn the back so its top slides \(amount == .clockwise ? "left" : "right")"
        }
    }

    /// A short hint about hand movement.
    public var handHint: String {
        switch (face, amount) {
        case (_, .half): "A half turn — either direction works."
        case (.front, .clockwise): "Like turning a steering wheel to the right."
        case (.front, _): "Like turning a steering wheel to the left."
        case (.right, .clockwise), (.left, .counterclockwise): "The front of that side rolls up and away from you."
        case (.right, _), (.left, _): "The front of that side rolls down toward you."
        case (.up, _), (.down, _): "Keep the rest of the cube still and slide just that row."
        case (.back, _): "Reach behind with your fingers; the front stays facing you."
        }
    }

    /// A compact label for showing a whole pattern at a glance.
    public var shortLabel: String {
        let side = ["Top", "Right", "Front", "Bottom", "Left", "Back"][face.rawValue]
        if amount == .half { return "\(side) ×2" }
        let cw = amount == .clockwise
        switch face {
        case .up: return "\(side) \(cw ? "←" : "→")"
        case .down: return "\(side) \(cw ? "→" : "←")"
        case .right: return "\(side) \(cw ? "↑" : "↓")"
        case .left: return "\(side) \(cw ? "↓" : "↑")"
        case .front: return "\(side) \(cw ? "↻" : "↺")"
        case .back: return "\(side) \(cw ? "←" : "→")"
        }
    }

    /// An SF Symbol matching `spokenInstruction`.
    public var directionSymbol: String {
        if amount == .half { return "arrow.triangle.2.circlepath" }
        let cw = amount == .clockwise
        switch face {
        case .up, .back: return cw ? "arrow.left" : "arrow.right"
        case .down: return cw ? "arrow.right" : "arrow.left"
        case .right: return cw ? "arrow.up" : "arrow.down"
        case .left: return cw ? "arrow.down" : "arrow.up"
        case .front: return cw ? "arrow.clockwise" : "arrow.counterclockwise"
        }
    }
}
