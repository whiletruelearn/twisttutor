import Foundation

/// Canonical solver order. Face indices are row-major, viewed from outside the cube.
public enum CubeFaceID: Int, CaseIterable, Sendable {
    case up, right, front, down, left, back

    public var notation: String { ["U", "R", "F", "D", "L", "B"][rawValue] }
}

/// Color names are observations, never fixed spatial directions.
public enum CubeColorID: String, CaseIterable, Sendable {
    case white, red, green, yellow, orange, blue
}

public struct ColorCandidate: Equatable, Sendable {
    public let color: CubeColorID
    public let confidence: Float

    public init(color: CubeColorID, confidence: Float) {
        self.color = color
        self.confidence = confidence
    }
}

/// Coordinates in the source image, normalized to 0...1 from its top-left.
public struct ImagePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Sticker: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var colorID: CubeColorID
    public let confidence: Float
    public let alternatives: [ColorCandidate]
    public let sourceFace: CubeFaceID?
    public let sourceImagePoint: ImagePoint?

    public init(
        id: UUID = UUID(), colorID: CubeColorID, confidence: Float = 1,
        alternatives: [ColorCandidate] = [], sourceFace: CubeFaceID? = nil,
        sourceImagePoint: ImagePoint? = nil
    ) {
        self.id = id
        self.colorID = colorID
        self.confidence = confidence
        self.alternatives = alternatives
        self.sourceFace = sourceFace
        self.sourceImagePoint = sourceImagePoint
    }
}

public enum CubeModelError: Error, Equatable, Sendable {
    case stickerCount(expected: Int, actual: Int)
    case faceCount(actual: Int)
    case indexOutOfRange(Int)
    case cubieArrayCount(field: String, expected: Int, actual: Int)
    case cubieValueOutOfRange(field: String, index: Int, value: Int)
    case centerColorsMustBeUnique
}

public struct CubeFace: Equatable, Sendable {
    public let stickers: [Sticker]
    public var centerColorID: CubeColorID { stickers[4].colorID }

    public init(stickers: [Sticker]) throws {
        guard stickers.count == 9 else {
            throw CubeModelError.stickerCount(expected: 9, actual: stickers.count)
        }
        self.stickers = stickers
    }
}

/// A well-shaped observation can still be physically impossible. Use CubeValidator before solving.
public struct CubeState: Equatable, Sendable {
    public private(set) var stickers: [Sticker]

    public init(stickers: [Sticker]) throws {
        guard stickers.count == 54 else {
            throw CubeModelError.stickerCount(expected: 54, actual: stickers.count)
        }
        self.stickers = stickers
    }

    public init(faces: [CubeFace]) throws {
        guard faces.count == 6 else { throw CubeModelError.faceCount(actual: faces.count) }
        try self.init(stickers: faces.flatMap(\.stickers))
    }

    public subscript(face: CubeFaceID) -> CubeFace {
        // Construction guarantees exactly six groups of nine.
        try! CubeFace(stickers: Array(stickers[(face.rawValue * 9)..<(face.rawValue * 9 + 9)]))
    }

    public var centerColors: [CubeColorID] { CubeFaceID.allCases.map { self[$0].centerColorID } }

    public var isSolved: Bool {
        Set(centerColors).count == 6 && CubeFaceID.allCases.allSatisfy { face in
            self[face].stickers.allSatisfy { $0.colorID == self[face].centerColorID }
        }
    }

    public static func solved(centerColors: [CubeColorID] = CubeColorID.allCases) throws -> CubeState {
        guard centerColors.count == 6, Set(centerColors).count == 6 else {
            throw CubeModelError.centerColorsMustBeUnique
        }
        return try CubeState(stickers: centerColors.flatMap { color in
            (0..<9).map { _ in Sticker(colorID: color) }
        })
    }

    public func replacingColor(at index: Int, with color: CubeColorID) throws -> CubeState {
        guard stickers.indices.contains(index) else { throw CubeModelError.indexOutOfRange(index) }
        var copy = self
        copy.stickers[index].colorID = color
        return copy
    }
}
