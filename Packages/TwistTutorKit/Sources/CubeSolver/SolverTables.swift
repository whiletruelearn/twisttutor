import Foundation
import CryptoKit

struct SolverTables: Sendable {
    let twistMoves: [UInt16]
    let flipMoves: [UInt16]
    let sliceMoves: [UInt16]
    let cornerMoves: [UInt16]
    let edgeMoves: [UInt16]
    let slicePermutationMoves: [UInt16]
    let twistSliceDistances: [UInt8]
    let flipSliceDistances: [UInt8]
    let cornerSliceDistances: [UInt8]
    let edgeSliceDistances: [UInt8]

    static let magic = Array("TT2PH001".utf8)
    static let moveDimensions = [(2187, 18), (2048, 18), (495, 18), (40320, 10), (40320, 10), (24, 10)]
    static let distanceSizes = [2187 * 495, 2048 * 495, 40320 * 24, 40320 * 24]
    static let byteCount = 8 + moveDimensions.reduce(0) { $0 + $1.0 * $1.1 * 2 } + distanceSizes.reduce(0, +) + 32

    /// Lazy immutable data is shared across concurrent searches. This is always loaded off the UI actor.
    static let bundled: Result<SolverTables, Error> = Result {
        guard let url = Bundle.module.url(forResource: "TwoPhaseTables", withExtension: "bin") else {
            throw SolverError.tablesUnavailable
        }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func decode(_ data: Data) throws -> SolverTables {
        guard data.count == byteCount, Array(data.prefix(8)) == magic else { throw SolverError.corruptTables }
        let payload = data.dropLast(32)
        guard Array(SHA256.hash(data: payload)) == Array(data.suffix(32)) else { throw SolverError.corruptTables }
        var offset = 8
        func moves(count: Int, width: Int) throws -> [UInt16] {
            let result: [UInt16] = data.withUnsafeBytes { bytes in
                (0..<(count * width)).map { UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset + $0 * 2, as: UInt16.self)) }
            }
            offset += count * width * 2
            guard result.allSatisfy({ $0 < count }) else { throw SolverError.corruptTables }
            return result
        }
        func distances(_ count: Int, maximum: UInt8) throws -> [UInt8] {
            let result = Array(data[offset..<(offset + count)])
            offset += count
            guard result.allSatisfy({ $0 <= maximum }) else { throw SolverError.corruptTables }
            return result
        }
        return try SolverTables(
            twistMoves: moves(count: 2187, width: 18), flipMoves: moves(count: 2048, width: 18),
            sliceMoves: moves(count: 495, width: 18), cornerMoves: moves(count: 40320, width: 10),
            edgeMoves: moves(count: 40320, width: 10), slicePermutationMoves: moves(count: 24, width: 10),
            twistSliceDistances: distances(2187 * 495, maximum: 12), flipSliceDistances: distances(2048 * 495, maximum: 12),
            cornerSliceDistances: distances(40320 * 24, maximum: 18), edgeSliceDistances: distances(40320 * 24, maximum: 18)
        )
    }

    func encoded() -> Data {
        var data = Data(Self.magic)
        for table in [twistMoves, flipMoves, sliceMoves, cornerMoves, edgeMoves, slicePermutationMoves] {
            for value in table {
                data.append(UInt8(truncatingIfNeeded: value))
                data.append(UInt8(truncatingIfNeeded: value >> 8))
            }
        }
        for table in [twistSliceDistances, flipSliceDistances, cornerSliceDistances, edgeSliceDistances] { data.append(contentsOf: table) }
        data.append(contentsOf: SHA256.hash(data: data))
        return data
    }
}
