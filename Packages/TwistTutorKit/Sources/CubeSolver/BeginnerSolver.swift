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
    /// Leading top-layer turns that park the piece before the pattern begins.
    public let setupMoveCount: Int
    public var patternRange: Range<Int> { (moveRange.lowerBound + setupMoveCount)..<moveRange.upperBound }
    public var isSetupOnly: Bool { setupMoveCount == moveRange.count }
    /// False when this lesson only frees a stuck piece so a later lesson can place it.
    public let placesPiece: Bool
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
                // A teacher works one piece at a time: group the turns that place each piece,
                // including the top-layer turns that line it up, into a single lesson.
                for group in TeachingSearch.lessonGroups(path, stage: stage, algorithms: algorithms, from: state) {
                    let start = moves.count
                    let groupMoves = group.flatMap { algorithms[$0].moves }
                    let next = state.applying(groupMoves)
                    let (piece, places) = TeachingSearch.targetPiece(stage: stage, before: state, after: next, cube: cube.applying(moves))
                    let setup = group.prefix { algorithms[$0].isSetup }.reduce(0) { $0 + algorithms[$1].moves.count }
                    let pattern = algorithms[group.first { !algorithms[$0].isSetup } ?? group[0]]
                    moves += groupMoves
                    state = next
                    lessons.append(BeginnerLesson(stage: stage, name: pattern.name, explanation: pattern.why, moveRange: start..<moves.count,
                                                  piece: piece, setupMoveCount: stage == .cross ? 0 : setup, placesPiece: places))
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
        let isSetup: Bool
        init(_ moves: [CubeMove], _ name: String, _ why: String) {
            self.moves = moves; self.name = name; self.why = why
            isSetup = moves.count == 1 && moves[0].face == .up
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
            return CubeFaceID.allCases.flatMap { face in TurnAmount.allCases.map { Algorithm([CubeMove(face, $0)], "Build the cross", "There’s no fixed pattern for the cross — you steer each edge with single turns. Sometimes an edge has to step out of the way and come back flipped, so its side color lines up with the right center.") } }
        }
        var result: [Algorithm] = []
        if stage != .topEdges {
            result += TurnAmount.allCases.map { Algorithm([CubeMove(.up, $0)], "Line up the top layer", "Turning only the top layer never disturbs what you’ve already built below, so it’s the safe way to move pieces into position.") }
        }
        let recipe: (String, String, String)
        switch stage {
        case .firstCorners: recipe = ("R U R'", "Insert a bottom corner", "The pattern lifts a bottom gap up, swings the corner over it, then lowers the side back down. Because the side goes back where it started, your cross stays safe. If the corner comes in twisted, repeating the pattern turns it a little more each time.")
        case .middleEdges: recipe = ("U R U' R' U' F' U F", "Insert a middle edge", "The first half moves the edge out of the way and opens a slot. The second half lowers the edge into that slot and repairs the bottom layer. That’s why the bottom looks broken mid-way: the pattern borrows it and gives it back.")
        case .topCross: recipe = ("F R U R' U' F'", "Turn the top edges", "Turning the front face first tucks two top edges sideways. The four turns in the middle shuffle them, and turning the front back brings them up flipped. Your finished layers return untouched.")
        case .topFace: recipe = ("R U R' U R U2 R'", "Turn the top corners", "This seven-turn pattern twists three top corners in place and leaves the cross alone. Doing it again from another side keeps twisting until every corner shows the top color.")
        case .topCorners: recipe = ("R U R' U' R' F R2 U' R' U' R U R' F'", "Swap top corners", "This longer pattern swaps two neighboring top corners (and two edges along the way). Everything else — including the top color — ends up exactly where it was.")
        case .topEdges: recipe = ("R U' R U R U R U' R' U' R2", "Cycle the last edges", "This pattern carries three top edges around in a little loop while every corner stays still. Run it once or twice and each edge lands next to its matching center.")
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
    static func lessonGroups(_ path: [Int], stage: BeginnerStage, algorithms: [Algorithm], from start: CubieState) -> [[Int]] {
        var groups: [[Int]] = []
        var current: [Int] = []
        var state = start
        let pieces = projection(for: stage)
        func placedCount(_ state: CubieState) -> Int {
            pieces.filter { piece in
                piece.corner ? state.cornerPermutation[piece.id] == piece.id && state.cornerOrientation[piece.id] == 0
                    : state.edgePermutation[piece.id] == piece.id && state.edgeOrientation[piece.id] == 0
            }.count
        }
        var placed = placedCount(state)
        for index in path {
            current.append(index)
            if stage == .cross || stage == .firstCorners {
                // One lesson per piece. It ends as soon as one more piece is home,
                // even when that takes a repeated corner pattern.
                state = state.applying(algorithms[index].moves)
                let count = placedCount(state)
                if count > placed { groups.append(current); current = []; placed = count }
            } else if !algorithms[index].isSetup {
                groups.append(current); current = []
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
    static func targetPiece(stage: BeginnerStage, before: CubieState, after: CubieState, cube: CubeState) -> (TeachingPiece?, Bool) {
        let candidates: [Piece]
        switch stage {
        case .cross: candidates = (4..<8).map { Piece(corner: false, id: $0) }
        case .firstCorners: candidates = (4..<8).map { Piece(corner: true, id: $0) }
        case .middleEdges: candidates = (8..<12).map { Piece(corner: false, id: $0) }
        case .topEdges: candidates = (0..<4).map { Piece(corner: false, id: $0) }
        case .topCorners: candidates = (0..<4).map { Piece(corner: true, id: $0) }
        // These patterns change the whole top at once; there is no single piece to follow.
        case .topCross, .topFace: return (nil, true)
        }
        func solved(_ piece: Piece, in state: CubieState) -> Bool {
            piece.corner ? state.cornerPermutation[piece.id] == piece.id && state.cornerOrientation[piece.id] == 0
                : state.edgePermutation[piece.id] == piece.id && state.edgeOrientation[piece.id] == 0
        }
        let unsolved = candidates.filter { !solved($0, in: before) }
        let placed = unsolved.first { solved($0, in: after) }
        // A pattern that places nothing has lifted a stuck piece out of its layer onto the top.
        let lifted = unsolved.first { piece in
            let from = (piece.corner ? before.cornerPermutation : before.edgePermutation).firstIndex(of: piece.id)!
            let to = (piece.corner ? after.cornerPermutation : after.edgePermutation).firstIndex(of: piece.id)!
            return from >= 4 && to < 4
        }
        guard let target = placed ?? lifted ?? unsolved.first else { return (nil, true) }
        let permutation = target.corner ? before.cornerPermutation : before.edgePermutation
        let source = permutation.firstIndex(of: target.id)!
        let destinationFaces = target.corner ? CornerID(rawValue: target.id)!.faces : EdgeID(rawValue: target.id)!.faces
        let sourceFaces = target.corner ? CornerID(rawValue: source)!.faces : EdgeID(rawValue: source)!.faces
        func indices(_ faces: [CubeFaceID]) -> [Int] {
            let position = faces.reduce(SIMD3<Float>.zero) { $0 + CubeRenderLayout.axis(for: $1) }
            return CubeRenderLayout.facelets.filter { $0.position == position }.map(\.index)
        }
        return (TeachingPiece(colors: destinationFaces.map { cube.centerColors[$0.rawValue] },
                              stickerIDs: indices(sourceFaces).map { cube.stickers[$0].id },
                              destinationIndices: indices(destinationFaces), destinationFaces: destinationFaces), placed != nil || stage.rawValue >= 3)
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
