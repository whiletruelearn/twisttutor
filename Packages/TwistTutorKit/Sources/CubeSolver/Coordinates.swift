import CubeCore

/// Coordinate encodings are deliberately private to this solver's versioned tables.
/// They need not match a third-party solver's numeric coordinate numbering.
enum Coordinates {
    static let moves = CubeFaceID.allCases.flatMap { face in TurnAmount.allCases.map { CubeMove(face, $0) } }
    static let phase2MoveIndices = [0, 1, 2, 4, 7, 9, 10, 11, 13, 16]
    static let transforms = moves.map { CubieState.solved.applying($0) }
    static let sliceMasks = (0..<4096).filter { $0.nonzeroBitCount == 4 }
    static let sliceIndex: [Int] = {
        var index = Array(repeating: -1, count: 4096)
        for (i, mask) in sliceMasks.enumerated() { index[mask] = i }
        return index
    }()
    static let solvedSlice = sliceIndex[0xf00]

    static func orientation(_ values: [Int], base: Int) -> Int {
        values.dropLast().reduce(0) { $0 * base + $1 }
    }

    static func orientations(_ index: Int, count: Int, base: Int) -> [Int] {
        var values = Array(repeating: 0, count: count)
        var remainder = index
        for i in stride(from: count - 2, through: 0, by: -1) {
            values[i] = remainder % base
            remainder /= base
        }
        values[count - 1] = (base - values.reduce(0, +) % base) % base
        return values
    }

    static func slice(_ edges: [Int]) -> Int {
        var mask = 0
        for i in edges.indices where edges[i] >= 8 { mask |= 1 << i }
        return sliceIndex[mask]
    }

    /// Lexicographic Lehmer rank; identity is zero.
    static func permutation(_ values: [Int]) -> Int {
        var rank = 0
        for i in values.indices {
            var smaller = 0
            for j in (i + 1)..<values.count where values[j] < values[i] { smaller += 1 }
            rank = rank * (values.count - i) + smaller
        }
        return rank
    }

    static func permutation(_ rank: Int, count: Int) -> [Int] {
        var digits = Array(repeating: 0, count: count)
        var remainder = rank
        for i in stride(from: count - 1, through: 0, by: -1) {
            digits[i] = remainder % (count - i)
            remainder /= count - i
        }
        var remaining = Array(0..<count)
        return digits.map { remaining.remove(at: $0) }
    }
}
