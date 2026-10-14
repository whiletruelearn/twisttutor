import CubeCore
import CubeValidation
import CubeSolver
import Observation

/// Unfilled stickers stay unfilled: a partial entry must never masquerade as a solved cube.
@MainActor @Observable
public final class ManualCubeEntry {
    public private(set) var stickers: [Sticker?] = Array(repeating: nil, count: 54)
    public let session = AppSession()

    public init() {}
    public var filledCount: Int { stickers.compactMap { $0 }.count }
    public var cube: CubeState? {
        guard filledCount == 54 else { return nil }
        return try? CubeState(stickers: stickers.compactMap { $0 })
    }
    public var validation: ValidationReport? { cube.map { CubeValidator.validate($0) } }
    public var canSolve: Bool { validation?.isValid == true && session.phase != .calculatingSolution }

    public func count(_ color: CubeColorID) -> Int { stickers.filter { $0?.colorID == color }.count }

    public func setColor(_ color: CubeColorID?, at index: Int) throws {
        guard stickers.indices.contains(index) else { throw CubeModelError.indexOutOfRange(index) }
        session.leave()
        if let color {
            if var sticker = stickers[index] { sticker.colorID = color; stickers[index] = sticker }
            else { stickers[index] = Sticker(colorID: color) }
        } else { stickers[index] = nil }
    }

    public func load(_ cube: CubeState) {
        session.leave()
        stickers = cube.stickers.map { $0 }
    }

    public func clear() {
        session.leave()
        stickers = Array(repeating: nil, count: 54)
    }

    @discardableResult public func solve(using solver: any CubeSolving = QuickSolver()) throws -> Task<Void, Never>? {
        guard session.phase != .calculatingSolution else { return nil }
        guard let cube else { return nil }
        session.enterManually(cube)
        guard session.phase == .cubeReady else { return nil }
        return try session.calculateSolution(using: solver)
    }

    /// Neighbor at the top edge when looking directly at each canonical face.
    public static func topNeighbor(of face: CubeFaceID) -> CubeFaceID {
        [.back, .up, .up, .front, .up, .up][face.rawValue]
    }
}

extension CubeDiagnostic {
    public var manualEntryMessage: String {
        switch self {
        case .stickerCount: "Fill every sticker on all six faces."
        case .duplicateCenters: "Each face needs a different center color. Check the six centers."
        case let .colorCount(color, actual): "There are \(actual) \(color.rawValue) stickers; there must be nine."
        case let .unknownCorner(_, indices), let .unknownEdge(_, indices):
            "Check the piece at \(indices.map { CubeFaceID(rawValue: $0 / 9)!.notation + String($0 % 9 + 1) }.joined(separator: ", ")). Its colors cannot form a real cube piece."
        case .duplicateCorners: "A corner piece appears more than once. Check the corner colors."
        case .duplicateEdges: "An edge piece appears more than once. Check the edge colors."
        case .edgeFlipParity: "An edge appears flipped. Check edge colors and face orientation; this state cannot be solved with normal turns."
        case .cornerTwistSum: "A corner appears twisted. Check corner colors and face orientation; this state cannot be solved with normal turns."
        case .permutationParity: "Two pieces appear swapped. Check the face orientations and colors; this state cannot be solved with normal turns."
        }
    }
}
