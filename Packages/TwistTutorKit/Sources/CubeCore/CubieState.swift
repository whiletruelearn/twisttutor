public enum CornerID: Int, CaseIterable, Sendable {
    case urf, ufl, ulb, ubr, dfr, dlf, dbl, drb
    public var faces: [CubeFaceID] {
        [[.up,.right,.front], [.up,.front,.left], [.up,.left,.back], [.up,.back,.right],
         [.down,.front,.right], [.down,.left,.front], [.down,.back,.left], [.down,.right,.back]][rawValue]
    }
}

public enum EdgeID: Int, CaseIterable, Sendable {
    case ur, uf, ul, ub, dr, df, dl, db, fr, fl, bl, br
    public var faces: [CubeFaceID] {
        [[.up,.right], [.up,.front], [.up,.left], [.up,.back], [.down,.right], [.down,.front],
         [.down,.left], [.down,.back], [.front,.right], [.front,.left], [.back,.left], [.back,.right]][rawValue]
    }
}

/// Arrays map destination slot -> piece identity. Orientations use the ordered faces above.
/// Shape/range is guaranteed here; uniqueness and reachability belong to CubeValidator.
public struct CubieState: Equatable, Sendable {
    public let cornerPermutation: [Int]
    public let cornerOrientation: [Int]
    public let edgePermutation: [Int]
    public let edgeOrientation: [Int]

    public init(cornerPermutation: [Int], cornerOrientation: [Int], edgePermutation: [Int], edgeOrientation: [Int]) throws {
        for (name, values, count, upperBound) in [
            ("cornerPermutation", cornerPermutation, 8, 8), ("cornerOrientation", cornerOrientation, 8, 3),
            ("edgePermutation", edgePermutation, 12, 12), ("edgeOrientation", edgeOrientation, 12, 2),
        ] {
            guard values.count == count else {
                throw CubeModelError.cubieArrayCount(field: name, expected: count, actual: values.count)
            }
            for (index, value) in values.enumerated() where !(0..<upperBound).contains(value) {
                throw CubeModelError.cubieValueOutOfRange(field: name, index: index, value: value)
            }
        }
        self.cornerPermutation = cornerPermutation; self.cornerOrientation = cornerOrientation
        self.edgePermutation = edgePermutation; self.edgeOrientation = edgeOrientation
    }

    public static let solved = try! CubieState(
        cornerPermutation: Array(0..<8), cornerOrientation: Array(repeating: 0, count: 8),
        edgePermutation: Array(0..<12), edgeOrientation: Array(repeating: 0, count: 12)
    )
    public var isSolved: Bool { self == .solved }

    // Derive once from integer geometry; no third-party implementation or move tables are bundled.
    private static let quarterTurns: [CubieState] = CubeFaceID.allCases.map { face in
        try! CubeConversion.cubies(from: CubeState.solved().applying(CubeMove(face)))
    }

    public func applying(_ move: CubeMove) -> CubieState {
        var result = self
        let turn = Self.quarterTurns[move.face.rawValue]
        for _ in 0..<move.amount.rawValue {
            result = try! CubieState(
                cornerPermutation: turn.cornerPermutation.map { result.cornerPermutation[$0] },
                cornerOrientation: (0..<8).map { (result.cornerOrientation[turn.cornerPermutation[$0]] + turn.cornerOrientation[$0]) % 3 },
                edgePermutation: turn.edgePermutation.map { result.edgePermutation[$0] },
                edgeOrientation: (0..<12).map { (result.edgeOrientation[turn.edgePermutation[$0]] + turn.edgeOrientation[$0]) % 2 }
            )
        }
        return result
    }

    public func applying(_ moves: [CubeMove]) -> CubieState { moves.reduce(self) { $0.applying($1) } }
}
