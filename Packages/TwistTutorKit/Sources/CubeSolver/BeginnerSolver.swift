import CubeCore
import CubeValidation
import Foundation

public enum BeginnerStage: Int, CaseIterable, Sendable {
    case cross, firstCorners, middleEdges, topCross, topFace, topCorners, topEdges
    public var title: String {
        ["Make the first cross", "Finish the first layer", "Fill the middle layer", "Make the top cross", "Finish the top color", "Place the top corners", "Place the last edges"][rawValue]
    }
    public var goal: String {
        ["Make a cross around the bottom center. Each edge’s other color must match its side center.",
         "Place the four bottom corners between their matching centers. The whole bottom layer should match.",
         "Move edges without the top color into the middle. The bottom two layers should now match their centers.",
         "Turn the four top edges so their top stickers match the top center. Their side colors can wait.",
         "Turn the top corners until the whole top face matches its center. Corners may still be in the wrong places.",
         "Move top corners to the sides with matching centers. Keep the finished top color intact.",
         "Cycle the remaining top edges to their matching sides. All six faces will now match."][rawValue]
    }
}

public struct TeachingPiece: Equatable, Sendable {
    public let colors: [CubeColorID]
    public let stickerIDs: [UUID]
    public let destinationIndices: [Int]
    public let destinationFaces: [CubeFaceID]
    public func currentIndices(in cube: CubeState) -> [Int] {
        cube.stickers.indices.filter { stickerIDs.contains(cube.stickers[$0].id) }
    }
}

public struct BeginnerLesson: Equatable, Sendable {
    public let stage: BeginnerStage
    public let name: String
    public let explanation: String
    public let moveRange: Range<Int>
    public let piece: TeachingPiece?
}

public struct BeginnerPlan: Equatable, Sendable {
    public let solution: VerifiedSolution
    public let lessons: [BeginnerLesson]
    public let alreadyComplete: [BeginnerStage]
    public func lesson(at moveIndex: Int) -> BeginnerLesson? { lessons.first { $0.moveRange.contains(moveIndex) } }
}

/// Layer-by-layer teaching. Search chooses familiar algorithms for the entered cube;
/// it never substitutes an optimal-solver sequence for a beginner lesson.
public struct BeginnerSolver: Sendable {
    public init() {}
    public func plan(for cube: CubeState) async throws -> BeginnerPlan {
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let report = CubeValidator.validate(cube)
            guard report.isValid else { throw SolverError.invalidCube(report.diagnostics) }
            var state = try CubeConversion.cubies(from: cube)
            var moves: [CubeMove] = []
            var lessons: [BeginnerLesson] = []
            var complete: [BeginnerStage] = []
            let deadline = ContinuousClock.now + .seconds(30)
            for stage in BeginnerStage.allCases {
                try Task.checkCancellation()
                let algorithms = TeachingSearch.algorithms(for: stage)
                let projection = TeachingSearch.projection(for: stage)
                let initial = TeachingSearch.key(state, pieces: projection)
                let goal = TeachingSearch.key(.solved, pieces: projection)
                let path: [Int]
                if stage.rawValue < 3 {
                    path = try TeachingSearch.bidirectional(initial, goal: goal, algorithms: algorithms, pieces: projection, deadline: deadline)
                } else {
                    path = try TeachingSearch.forward(initial, stage: stage, algorithms: algorithms, pieces: projection, deadline: deadline)
                }
                if path.isEmpty { complete.append(stage) }
                for index in path {
                    let algorithm = algorithms[index]
                    let start = moves.count
                    let next = state.applying(algorithm.moves)
                    let piece = TeachingSearch.targetPiece(stage: stage, before: state, after: next, cube: cube.applying(moves))
                    moves += algorithm.moves
                    state = next
                    lessons.append(BeginnerLesson(stage: stage, name: algorithm.name, explanation: algorithm.why, moveRange: start..<moves.count, piece: piece))
                }
                // Verify every milestone on the full state, including all earlier layers.
                guard TeachingSearch.milestone(stage, state) else { throw SolverError.verificationFailed }
            }
            return BeginnerPlan(solution: try SolutionVerifier.verify(moves, for: cube), lessons: lessons, alreadyComplete: complete)
        }
        return try await withTaskCancellationHandler {
            let plan = try await work.value
            try Task.checkCancellation()
            return plan
        } onCancel: { work.cancel() }
    }
}

private enum TeachingSearch {
    struct Piece { let corner: Bool; let id: Int }
    struct Algorithm {
        let moves: [CubeMove]
        let name: String
        let why: String
        let edges: [UInt64]
        let corners: [UInt64]
        init(_ moves: [CubeMove], _ name: String, _ why: String) {
            self.moves = moves; self.name = name; self.why = why
            let effect = CubieState.solved.applying(moves)
            var edges = [UInt64](repeating: 0, count: 24)
            var corners = edges
            for destination in 0..<12 {
                let source = effect.edgePermutation[destination]
                for orientation in 0..<2 { edges[source * 2 + orientation] = UInt64(destination * 2 + (orientation + effect.edgeOrientation[destination]) % 2) }
            }
            for destination in 0..<8 {
                let source = effect.cornerPermutation[destination]
                for orientation in 0..<3 { corners[source * 3 + orientation] = UInt64(destination * 3 + (orientation + effect.cornerOrientation[destination]) % 3) }
            }
            self.edges = edges; self.corners = corners
        }
    }
    static func projection(for stage: BeginnerStage) -> [Piece] {
        switch stage {
        case .cross: (4..<8).map { Piece(corner: false, id: $0) }
        case .firstCorners: (4..<8).map { Piece(corner: true, id: $0) }
        case .middleEdges: (8..<12).map { Piece(corner: false, id: $0) }
        default: (0..<4).map { Piece(corner: false, id: $0) } + (0..<4).map { Piece(corner: true, id: $0) }
        }
    }
    static func key(_ state: CubieState, pieces: [Piece]) -> UInt64 {
        pieces.enumerated().reduce(0) { result, pair in
            let (index, piece) = pair
            let permutation = piece.corner ? state.cornerPermutation : state.edgePermutation
            let orientations = piece.corner ? state.cornerOrientation : state.edgeOrientation
            let position = permutation.firstIndex(of: piece.id)!
            return result | UInt64(position * (piece.corner ? 3 : 2) + orientations[position]) << (index * 5)
        }
    }
    static func applying(_ algorithm: Algorithm, to key: UInt64, pieces: [Piece]) -> UInt64 {
        var result: UInt64 = 0
        for (index, piece) in pieces.enumerated() {
            let value = Int((key >> (index * 5)) & 31)
            result |= (piece.corner ? algorithm.corners[value] : algorithm.edges[value]) << (index * 5)
        }
        return result
    }
    static func algorithms(for stage: BeginnerStage) -> [Algorithm] {
        if stage == .cross {
            return CubeFaceID.allCases.flatMap { face in TurnAmount.allCases.map { Algorithm([CubeMove(face, $0)], "Build the cross", "Bring bottom-color edges around the bottom center, then line up their side colors. We may move an edge away briefly to put it back correctly.") } }
        }
        var result: [Algorithm] = []
        if stage != .topEdges {
            result += TurnAmount.allCases.map { Algorithm([CubeMove(.up, $0)], "Line up the top layer", "Turn only the top layer to put the next pieces in position. Keep holding the cube with the same front and top.") }
        }
        let recipe: (String, String, String)
        switch stage {
        case .firstCorners: recipe = ("R U R'", "Insert a bottom corner", "Open a side, move the top, then close the side. Repeating this short pattern places and turns bottom corners while keeping the cross together.")
        case .middleEdges: recipe = ("U R U' R' U' F' U F", "Insert a middle edge", "Move the edge away, open a space, and bring it into the middle layer. The first layer is restored when this whole pattern finishes.")
        case .topCross: recipe = ("F R U R' U' F'", "Turn the top edges", "Open the indicated side, do a four-turn trigger, and close that side. This flips top edges while restoring the two finished layers.")
        case .topFace: recipe = ("R U R' U R U2 R'", "Turn the top corners", "This seven-move pattern turns top corners while keeping the top cross. It may need to be repeated from another side.")
        case .topCorners: recipe = ("R U R' U' R' F R2 U' R' U' R U R' F'", "Swap top corners", "This pattern exchanges two top corners and two top edges. The finished colors and bottom two layers return at the end.")
        case .topEdges: recipe = ("R U' R U R U R U' R' U' R2", "Cycle the last edges", "Move three top edges around the top while keeping all corners in place. The finished layers return at the end of the pattern.")
        default: preconditionFailure()
        }
        let sides: [CubeFaceID] = [.front, .right, .back, .left]
        let base = try! MoveNotation.parse(recipe.0)
        for rotation in 0..<4 {
            let moves = base.map { move -> CubeMove in
                guard let index = sides.firstIndex(of: move.face) else { return move }
                return CubeMove(sides[(index + rotation) % 4], move.amount)
            }
            result.append(Algorithm(moves, recipe.1, recipe.2))
            result.append(Algorithm(MoveNotation.inverse(moves), recipe.1, recipe.2))
        }
        return result
    }
    static func targetPiece(stage: BeginnerStage, before: CubieState, after: CubieState, cube: CubeState) -> TeachingPiece? {
        let candidates: [Piece]
        switch stage {
        case .cross: candidates = (4..<8).map { Piece(corner: false, id: $0) }
        case .firstCorners: candidates = (4..<8).map { Piece(corner: true, id: $0) }
        case .middleEdges: candidates = (8..<12).map { Piece(corner: false, id: $0) }
        case .topCross, .topEdges: candidates = (0..<4).map { Piece(corner: false, id: $0) }
        case .topFace, .topCorners: candidates = (0..<4).map { Piece(corner: true, id: $0) }
        }
        func solved(_ piece: Piece, in state: CubieState) -> Bool {
            piece.corner ? state.cornerPermutation[piece.id] == piece.id && state.cornerOrientation[piece.id] == 0
                : state.edgePermutation[piece.id] == piece.id && state.edgeOrientation[piece.id] == 0
        }
        let unsolved = candidates.filter { !solved($0, in: before) }
        guard let target = unsolved.first(where: { solved($0, in: after) }) ?? unsolved.first else { return nil }
        let permutation = target.corner ? before.cornerPermutation : before.edgePermutation
        let source = permutation.firstIndex(of: target.id)!
        let destinationFaces = target.corner ? CornerID(rawValue: target.id)!.faces : EdgeID(rawValue: target.id)!.faces
        let sourceFaces = target.corner ? CornerID(rawValue: source)!.faces : EdgeID(rawValue: source)!.faces
        func indices(_ faces: [CubeFaceID]) -> [Int] {
            let position = faces.reduce(SIMD3<Float>.zero) { $0 + CubeRenderLayout.axis(for: $1) }
            return CubeRenderLayout.facelets.filter { $0.position == position }.map(\.index)
        }
        return TeachingPiece(colors: destinationFaces.map { cube.centerColors[$0.rawValue] },
                             stickerIDs: indices(sourceFaces).map { cube.stickers[$0].id },
                             destinationIndices: indices(destinationFaces), destinationFaces: destinationFaces)
    }

    struct Link { let parent: UInt64; let action: Int }
    static func check(_ visited: Int, deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw SolverError.searchLimitReached }
        guard visited < 1_000_000 else { throw SolverError.searchLimitReached }
    }
    static func path(to end: UInt64, in links: [UInt64: Link]) -> [Int] {
        var current = end; var result: [Int] = []
        while let link = links[current], link.action >= 0 { result.append(link.action); current = link.parent }
        return result.reversed()
    }
    static func bidirectional(_ initial: UInt64, goal: UInt64, algorithms: [Algorithm], pieces: [Piece], deadline: ContinuousClock.Instant) throws -> [Int] {
        if initial == goal { return [] }
        let inverse = algorithms.map { algorithm in algorithms.firstIndex { $0.moves == MoveNotation.inverse(algorithm.moves) }! }
        var left: [UInt64: Link] = [initial: Link(parent: initial, action: -1)]
        var right: [UInt64: Link] = [goal: Link(parent: goal, action: -1)]
        var lf = [initial], rf = [goal]
        while !lf.isEmpty && !rf.isEmpty {
            let expandingLeft = lf.count <= rf.count
            let frontier = expandingLeft ? lf : rf
            var next: [UInt64] = []
            for state in frontier {
                try check(left.count + right.count, deadline: deadline)
                for (index, algorithm) in algorithms.enumerated() {
                    let child = applying(algorithm, to: state, pieces: pieces)
                    if expandingLeft {
                        if left[child] != nil { continue }
                        left[child] = Link(parent: state, action: index)
                        if right[child] != nil { return path(to: child, in: left) + path(to: child, in: right).reversed().map { inverse[$0] } }
                    } else {
                        if right[child] != nil { continue }
                        right[child] = Link(parent: state, action: index)
                        if left[child] != nil { return path(to: child, in: left) + path(to: child, in: right).reversed().map { inverse[$0] } }
                    }
                    next.append(child)
                }
            }
            if expandingLeft { lf = next } else { rf = next }
        }
        throw SolverError.searchLimitReached
    }
    static func matches(_ key: UInt64, stage: BeginnerStage) -> Bool {
        for index in 0..<8 {
            let value = Int((key >> (index * 5)) & 31)
            if index < 4 {
                if value % 2 != 0 { return false }
                if stage == .topEdges && value / 2 != index { return false }
            } else {
                if stage.rawValue >= BeginnerStage.topFace.rawValue && value % 3 != 0 { return false }
                if stage.rawValue >= BeginnerStage.topCorners.rawValue && value / 3 != index - 4 { return false }
            }
        }
        return true
    }
    static func forward(_ initial: UInt64, stage: BeginnerStage, algorithms: [Algorithm], pieces: [Piece], deadline: ContinuousClock.Instant) throws -> [Int] {
        if matches(initial, stage: stage) { return [] }
        var links = [initial: Link(parent: initial, action: -1)]
        var queue = [initial]; var head = 0
        while head < queue.count {
            try check(head, deadline: deadline)
            let state = queue[head]; head += 1
            for (index, algorithm) in algorithms.enumerated() {
                let child = applying(algorithm, to: state, pieces: pieces)
                if links[child] != nil { continue }
                links[child] = Link(parent: state, action: index)
                if matches(child, stage: stage) { return path(to: child, in: links) }
                queue.append(child)
            }
        }
        throw SolverError.searchLimitReached
    }
    static func milestone(_ stage: BeginnerStage, _ state: CubieState) -> Bool {
        guard (4..<8).allSatisfy({ state.edgePermutation[$0] == $0 && state.edgeOrientation[$0] == 0 }) else { return false }
        if stage.rawValue >= 1 && !(4..<8).allSatisfy({ state.cornerPermutation[$0] == $0 && state.cornerOrientation[$0] == 0 }) { return false }
        if stage.rawValue >= 2 && !(8..<12).allSatisfy({ state.edgePermutation[$0] == $0 && state.edgeOrientation[$0] == 0 }) { return false }
        return stage.rawValue < 3 || matches(key(state, pieces: projection(for: stage)), stage: stage)
    }
}
