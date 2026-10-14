import CubeCore

/// Per-request state; immutable shared tables allow independent concurrent solves.
final class TwoPhaseSearch {
    let tables: SolverTables
    let initial: CubieState
    let limits: SolverLimits
    let deadline: ContinuousClock.Instant
    var nodes = 0
    var phase1Path: [Int] = []
    var phase2Path: [Int] = []

    init(tables: SolverTables, initial: CubieState, limits: SolverLimits, deadline: ContinuousClock.Instant) {
        self.tables = tables; self.initial = initial; self.limits = limits; self.deadline = deadline
    }

    func solve() throws -> [CubeMove] {
        try checkpoint(force: true)
        let twist = Coordinates.orientation(initial.cornerOrientation, base: 3)
        let flip = Coordinates.orientation(initial.edgeOrientation, base: 2)
        let slice = Coordinates.slice(initial.edgePermutation)
        let lower = phase1Distance(twist, flip, slice)
        for depth in lower...12 {
            if try phase1(twist, flip, slice, remaining: depth, previousFace: -1) {
                return (phase1Path + phase2Path).map { Coordinates.moves[$0] }
            }
        }
        throw SolverError.searchLimitReached
    }

    func checkpoint(force: Bool = false) throws {
        nodes += 1
        if nodes > limits.maximumNodes { throw SolverError.searchLimitReached }
        if force || nodes & 1023 == 0 {
            try Task.checkCancellation()
            if ContinuousClock.now >= deadline { throw SolverError.searchLimitReached }
        }
    }

    func phase1Distance(_ twist: Int, _ flip: Int, _ slice: Int) -> Int {
        max(Int(tables.twistSliceDistances[twist * 495 + slice]), Int(tables.flipSliceDistances[flip * 495 + slice]))
    }

    func phase2Distance(_ corners: Int, _ edges: Int, _ slice: Int) -> Int {
        max(Int(tables.cornerSliceDistances[corners * 24 + slice]), Int(tables.edgeSliceDistances[edges * 24 + slice]))
    }

    /// Adjacent equal faces combine; opposite faces commute, so keep one canonical ordering.
    func allowed(_ face: Int, after previous: Int) -> Bool {
        if face == previous { return false }
        if previous >= 0 && face % 3 == previous % 3 && face < previous { return false }
        return true
    }

    func phase1(_ twist: Int, _ flip: Int, _ slice: Int, remaining: Int, previousFace: Int) throws -> Bool {
        try checkpoint()
        guard phase1Distance(twist, flip, slice) <= remaining else { return false }
        if remaining == 0 {
            guard twist == 0, flip == 0, slice == Coordinates.solvedSlice else { return false }
            let state = initial.applying(phase1Path.map { Coordinates.moves[$0] })
            let corners = Coordinates.permutation(state.cornerPermutation)
            let edges = Coordinates.permutation(Array(state.edgePermutation.prefix(8)))
            let slicePermutation = Coordinates.permutation(state.edgePermutation.suffix(4).map { $0 - 8 })
            // Start phase 2 without cross-boundary pruning: it must retain its full 18-move bound.
            for depth in phase2Distance(corners, edges, slicePermutation)...18 {
                if try phase2(corners, edges, slicePermutation, remaining: depth, previousFace: -1) { return true }
            }
            return false
        }
        for move in 0..<18 where allowed(move / 3, after: previousFace) {
            phase1Path.append(move)
            if try phase1(Int(tables.twistMoves[twist * 18 + move]), Int(tables.flipMoves[flip * 18 + move]),
                          Int(tables.sliceMoves[slice * 18 + move]), remaining: remaining - 1, previousFace: move / 3) { return true }
            phase1Path.removeLast()
        }
        return false
    }

    func phase2(_ corners: Int, _ edges: Int, _ slice: Int, remaining: Int, previousFace: Int) throws -> Bool {
        try checkpoint()
        guard phase2Distance(corners, edges, slice) <= remaining else { return false }
        if remaining == 0 { return corners == 0 && edges == 0 && slice == 0 }
        for (index, move) in Coordinates.phase2MoveIndices.enumerated() where allowed(move / 3, after: previousFace) {
            phase2Path.append(move)
            if try phase2(Int(tables.cornerMoves[corners * 10 + index]), Int(tables.edgeMoves[edges * 10 + index]),
                          Int(tables.slicePermutationMoves[slice * 10 + index]), remaining: remaining - 1, previousFace: move / 3) { return true }
            phase2Path.removeLast()
        }
        return false
    }
}
