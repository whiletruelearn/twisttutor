public enum CubeConversionError: Error, Equatable, Sendable {
    case duplicateCenters
    case unknownCorner(slot: CornerID, faceletIndices: [Int])
    case unknownEdge(slot: EdgeID, faceletIndices: [Int])
    case duplicatePieces
}

public enum CubeConversion {
    static let cornerIndices = CornerID.allCases.map { CubeGeometry.indices(for: $0.faces) }
    static let edgeIndices = EdgeID.allCases.map { CubeGeometry.indices(for: $0.faces) }

    public static func cubies(from cube: CubeState) throws -> CubieState {
        let centers = cube.centerColors
        guard Set(centers).count == 6 else { throw CubeConversionError.duplicateCenters }
        var cp: [Int] = [], co: [Int] = [], ep: [Int] = [], eo: [Int] = []
        for slot in CornerID.allCases {
            let indices = cornerIndices[slot.rawValue]
            let observed = indices.map { cube.stickers[$0].colorID }
            var match: (Int, Int)?
            for piece in CornerID.allCases {
                let expected = piece.faces.map { centers[$0.rawValue] }
                for orientation in 0..<3 where (0..<3).allSatisfy({ observed[($0 + orientation) % 3] == expected[$0] }) {
                    match = (piece.rawValue, orientation)
                }
            }
            guard let match else { throw CubeConversionError.unknownCorner(slot: slot, faceletIndices: indices) }
            cp.append(match.0); co.append(match.1)
        }
        for slot in EdgeID.allCases {
            let indices = edgeIndices[slot.rawValue]
            let observed = indices.map { cube.stickers[$0].colorID }
            var match: (Int, Int)?
            for piece in EdgeID.allCases {
                let expected = piece.faces.map { centers[$0.rawValue] }
                for orientation in 0..<2 where (0..<2).allSatisfy({ observed[($0 + orientation) % 2] == expected[$0] }) {
                    match = (piece.rawValue, orientation)
                }
            }
            guard let match else { throw CubeConversionError.unknownEdge(slot: slot, faceletIndices: indices) }
            ep.append(match.0); eo.append(match.1)
        }
        return try CubieState(cornerPermutation: cp, cornerOrientation: co, edgePermutation: ep, edgeOrientation: eo)
    }

    /// Color-only projection, useful for solver fixtures. Use CubeEncoding to retain observation metadata.
    public static func facelets(from cubies: CubieState, centerColors: [CubeColorID] = CubeColorID.allCases) throws -> CubeState {
        let solved = try CubeState.solved(centerColors: centerColors)
        return restore(cubies, catalog: solved.stickers)
    }

    static func mapping(_ cubies: CubieState) -> [(source: Int, destination: Int)] {
        var mapping = CubeFaceID.allCases.map { (source: $0.rawValue * 9 + 4, destination: $0.rawValue * 9 + 4) }
        for slot in 0..<8 {
            for component in 0..<3 {
                mapping.append((cornerIndices[cubies.cornerPermutation[slot]][component], cornerIndices[slot][(component + cubies.cornerOrientation[slot]) % 3]))
            }
        }
        for slot in 0..<12 {
            for component in 0..<2 {
                mapping.append((edgeIndices[cubies.edgePermutation[slot]][component], edgeIndices[slot][(component + cubies.edgeOrientation[slot]) % 2]))
            }
        }
        return mapping
    }

    static func restore(_ cubies: CubieState, catalog: [Sticker]) -> CubeState {
        var result = catalog
        for pair in mapping(cubies) { result[pair.destination] = catalog[pair.source] }
        return try! CubeState(stickers: result)
    }
}

/// Lossless facelets ⇄ cubies bridge. The catalog is indexed by physical sticker identity,
/// so confidence/provenance follows the same sticker even after subsequent cubie moves.
public struct CubeEncoding: Equatable, Sendable {
    public private(set) var cubies: CubieState
    private let stickerCatalog: [Sticker]

    public init(_ cube: CubeState) throws {
        let cubies = try CubeConversion.cubies(from: cube)
        guard Set(cubies.cornerPermutation).count == 8, Set(cubies.edgePermutation).count == 12 else {
            throw CubeConversionError.duplicatePieces
        }
        self.cubies = cubies
        var catalog = cube.stickers
        for pair in CubeConversion.mapping(cubies) { catalog[pair.source] = cube.stickers[pair.destination] }
        self.stickerCatalog = catalog
    }

    public var facelets: CubeState { CubeConversion.restore(cubies, catalog: stickerCatalog) }

    public func applying(_ move: CubeMove) -> CubeEncoding {
        var result = self
        result.cubies = cubies.applying(move)
        return result
    }
}
