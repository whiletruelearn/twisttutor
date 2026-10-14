import CubeCore

public enum CubeDiagnostic: Equatable, Sendable {
    case stickerCount(actual: Int)
    case duplicateCenters
    case colorCount(color: CubeColorID, actual: Int)
    case unknownCorner(CornerID, indices: [Int])
    case unknownEdge(EdgeID, indices: [Int])
    case duplicateCorners
    case duplicateEdges
    case edgeFlipParity
    case cornerTwistSum
    case permutationParity

    public var message: String {
        switch self {
        case .stickerCount: "Scan all six faces so every sticker is included."
        case .duplicateCenters: "Two face centers have the same color. Review the centers or rescan those faces."
        case let .colorCount(color, actual): "We found \(actual) \(color.rawValue) stickers. There should be nine. Review stickers of this color."
        case .unknownCorner, .duplicateCorners: "Some corner colors do not match a real cube. Review the corner stickers."
        case .unknownEdge, .duplicateEdges: "Some edge colors do not match a real cube. Review the edge stickers."
        case .edgeFlipParity, .cornerTwistSum, .permutationParity:
            "This cube state can't occur from normal turns. We may have misread one of the stickers. Review the colors or rescan your cube."
        }
    }
}

public struct ValidationReport: Equatable, Sendable {
    public let diagnostics: [CubeDiagnostic]
    public var isValid: Bool { diagnostics.isEmpty }
    public init(diagnostics: [CubeDiagnostic]) { self.diagnostics = diagnostics }
}

public enum CubeValidator {
    /// Raw input entry point: callers can validate partial scans without constructing a CubeState.
    public static func validateColors(_ stickers: [Sticker]) -> ValidationReport {
        guard stickers.count == 54 else { return ValidationReport(diagnostics: [.stickerCount(actual: stickers.count)]) }
        var errors: [CubeDiagnostic] = []
        let centers = CubeFaceID.allCases.map { stickers[$0.rawValue * 9 + 4].colorID }
        if Set(centers).count != 6 { errors.append(.duplicateCenters) }
        for color in CubeColorID.allCases {
            let count = stickers.filter { $0.colorID == color }.count
            if count != 9 { errors.append(.colorCount(color: color, actual: count)) }
        }
        return ValidationReport(diagnostics: errors)
    }

    public static func validate(_ cube: CubeState) -> ValidationReport {
        let colors = validateColors(cube.stickers)
        guard colors.isValid else { return colors }
        do {
            return validate(try CubeConversion.cubies(from: cube))
        } catch let error as CubeConversionError {
            switch error {
            case .duplicateCenters: return ValidationReport(diagnostics: [.duplicateCenters])
            case let .unknownCorner(slot, indices): return ValidationReport(diagnostics: [.unknownCorner(slot, indices: indices)])
            case let .unknownEdge(slot, indices): return ValidationReport(diagnostics: [.unknownEdge(slot, indices: indices)])
            case .duplicatePieces: return ValidationReport(diagnostics: [.duplicateCorners, .duplicateEdges])
            }
        } catch {
            // CubeState and CubieState initializers enforce all structural preconditions.
            preconditionFailure("Unexpected conversion error: \(error)")
        }
    }

    public static func validate(_ cubies: CubieState) -> ValidationReport {
        var errors: [CubeDiagnostic] = []
        let cornersUnique = Set(cubies.cornerPermutation).count == 8
        let edgesUnique = Set(cubies.edgePermutation).count == 12
        if !cornersUnique { errors.append(.duplicateCorners) }
        if !edgesUnique { errors.append(.duplicateEdges) }
        if cubies.edgeOrientation.reduce(0, +) % 2 != 0 { errors.append(.edgeFlipParity) }
        if cubies.cornerOrientation.reduce(0, +) % 3 != 0 { errors.append(.cornerTwistSum) }
        if cornersUnique && edgesUnique && parity(cubies.cornerPermutation) != parity(cubies.edgePermutation) {
            errors.append(.permutationParity)
        }
        return ValidationReport(diagnostics: errors)
    }

    private static func parity(_ permutation: [Int]) -> Int {
        var inversions = 0
        for i in permutation.indices {
            for j in (i + 1)..<permutation.count where permutation[i] > permutation[j] { inversions += 1 }
        }
        return inversions % 2
    }
}
