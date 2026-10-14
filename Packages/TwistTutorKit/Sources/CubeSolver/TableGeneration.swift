import CubeCore
import Foundation

/// Developer tooling only. The application never generates tables at launch or during a solve.
@_spi(Tooling) public enum SolverTableGenerator {
    public static func generate(at url: URL) throws {
        try makeTables().encoded().write(to: url, options: .atomic)
    }

    static func makeTables() -> SolverTables {
        let transforms = Coordinates.transforms
        func orientations(count: Int, base: Int, corners: Bool) -> [UInt16] {
            let length = corners ? 8 : 12
            return (0..<count).flatMap { index in
                let values = Coordinates.orientations(index, count: length, base: base)
                return transforms.map { move in
                    let permutation = corners ? move.cornerPermutation : move.edgePermutation
                    let offset = corners ? move.cornerOrientation : move.edgeOrientation
                    return UInt16(Coordinates.orientation((0..<length).map { (values[permutation[$0]] + offset[$0]) % base }, base: base))
                }
            }
        }
        let twist = orientations(count: 2187, base: 3, corners: true)
        let flip = orientations(count: 2048, base: 2, corners: false)
        let slice: [UInt16] = Coordinates.sliceMasks.flatMap { mask in
            transforms.map { move in
                var target = 0
                for i in 0..<12 where mask & (1 << move.edgePermutation[i]) != 0 { target |= 1 << i }
                return UInt16(Coordinates.sliceIndex[target])
            }
        }
        let phase2 = Coordinates.phase2MoveIndices.map { transforms[$0] }
        func permutations(count: Int, length: Int, mapping: (CubieState) -> [Int]) -> [UInt16] {
            (0..<count).flatMap { index in
                let values = Coordinates.permutation(index, count: length)
                return phase2.map { move in UInt16(Coordinates.permutation(mapping(move).map { values[$0] })) }
            }
        }
        let corners = permutations(count: 40320, length: 8) { $0.cornerPermutation }
        let edges = permutations(count: 40320, length: 8) { Array($0.edgePermutation.prefix(8)) }
        let slicePerm = permutations(count: 24, length: 4) { $0.edgePermutation.suffix(4).map { $0 - 8 } }
        return SolverTables(
            twistMoves: twist, flipMoves: flip, sliceMoves: slice, cornerMoves: corners,
            edgeMoves: edges, slicePermutationMoves: slicePerm,
            twistSliceDistances: distances(first: twist, second: slice, width: 18, root: Coordinates.solvedSlice),
            flipSliceDistances: distances(first: flip, second: slice, width: 18, root: Coordinates.solvedSlice),
            cornerSliceDistances: distances(first: corners, second: slicePerm, width: 10, root: 0),
            edgeSliceDistances: distances(first: edges, second: slicePerm, width: 10, root: 0)
        )
    }

    private static func distances(first: [UInt16], second: [UInt16], width: Int, root: Int) -> [UInt8] {
        let secondCount = second.count / width
        let count = first.count / width * secondCount
        var result = Array(repeating: UInt8.max, count: count)
        var queue = [UInt32]()
        queue.reserveCapacity(count)
        queue.append(UInt32(root)); result[root] = 0
        var head = 0
        while head < queue.count {
            let state = Int(queue[head]); head += 1
            let a = state / secondCount * width, b = state % secondCount * width
            let depth = result[state] + 1
            for move in 0..<width {
                let next = Int(first[a + move]) * secondCount + Int(second[b + move])
                if result[next] == .max {
                    result[next] = depth
                    queue.append(UInt32(next))
                }
            }
        }
        precondition(queue.count == count, "Disconnected coordinate graph")
        return result
    }
}
