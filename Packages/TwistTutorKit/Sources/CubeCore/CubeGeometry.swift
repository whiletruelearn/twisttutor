// Integer geometry avoids floating-point drift and makes scanner/renderer conventions explicit.
struct Vector: Equatable, Hashable, Sendable {
    let x: Int
    let y: Int
    let z: Int
    init(_ x: Int, _ y: Int, _ z: Int) { self.x = x; self.y = y; self.z = z }
    static func + (a: Self, b: Self) -> Self { Self(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func * (a: Self, b: Int) -> Self { Self(a.x * b, a.y * b, a.z * b) }
    func dot(_ b: Self) -> Int { x * b.x + y * b.y + z * b.z }
    func cross(_ b: Self) -> Self { Self(y*b.z-z*b.y, z*b.x-x*b.z, x*b.y-y*b.x) }
    /// -90 degrees about the outward normal = clockwise looking directly at that face.
    func turned(around axis: Self) -> Self { self.cross(axis) + axis * dot(axis) }
}

struct FaceletLocation: Hashable, Sendable {
    let position: Vector
    let normal: Vector
}

enum CubeGeometry {
    static let normals = [Vector(0,1,0), Vector(1,0,0), Vector(0,0,1), Vector(0,-1,0), Vector(-1,0,0), Vector(0,0,-1)]
    static let rights = [Vector(1,0,0), Vector(0,0,-1), Vector(1,0,0), Vector(1,0,0), Vector(0,0,1), Vector(-1,0,0)]
    static let downs = [Vector(0,0,1), Vector(0,-1,0), Vector(0,-1,0), Vector(0,0,-1), Vector(0,-1,0), Vector(0,-1,0)]
    static let locations: [FaceletLocation] = CubeFaceID.allCases.flatMap { face in
        (0..<9).map { index in
            let f = face.rawValue
            return FaceletLocation(position: normals[f] + rights[f] * (index % 3 - 1) + downs[f] * (index / 3 - 1), normal: normals[f])
        }
    }
    static let indices = Dictionary(uniqueKeysWithValues: locations.enumerated().map { ($0.element, $0.offset) })
    static let quarterTurns: [[Int]] = CubeFaceID.allCases.map { face in
        let axis = normals[face.rawValue]
        return locations.map { location in
            let target = location.position.dot(axis) == 1
                ? FaceletLocation(position: location.position.turned(around: axis), normal: location.normal.turned(around: axis))
                : location
            return indices[target]!
        }
    }

    static func indices(for faces: [CubeFaceID]) -> [Int] {
        let position = faces.reduce(Vector(0,0,0)) { $0 + normals[$1.rawValue] }
        return faces.map { indices[FaceletLocation(position: position, normal: normals[$0.rawValue])]! }
    }
}

extension CubeState {
    public func applying(_ move: CubeMove) -> CubeState {
        var result = stickers
        let permutation = CubeGeometry.quarterTurns[move.face.rawValue]
        for _ in 0..<move.amount.rawValue {
            let previous = result
            for source in 0..<54 { result[permutation[source]] = previous[source] }
        }
        return try! CubeState(stickers: result)
    }

    public func applying(_ moves: [CubeMove]) -> CubeState { moves.reduce(self) { $0.applying($1) } }
}

/// A captured face must declare its spatial identity and the rotation needed to become canonical.
/// Capture order alone cannot infer the orientation of arbitrary Photos images.
public enum FaceRotation: Int, CaseIterable, Sendable {
    case none = 0, clockwise = 1, half = 2, counterclockwise = 3
}

public struct CapturedFace: Equatable, Sendable {
    public let face: CubeFaceID
    public let imageFace: CubeFace
    public let rotationToCanonical: FaceRotation

    public init(face: CubeFaceID, imageFace: CubeFace, rotationToCanonical: FaceRotation) {
        self.face = face; self.imageFace = imageFace; self.rotationToCanonical = rotationToCanonical
    }

    public var canonicalFace: CubeFace {
        var stickers = imageFace.stickers
        for _ in 0..<rotationToCanonical.rawValue {
            let old = stickers
            for row in 0..<3 { for column in 0..<3 { stickers[column * 3 + 2 - row] = old[row * 3 + column] } }
        }
        return try! CubeFace(stickers: stickers)
    }
}

public enum CaptureAssemblyError: Error, Equatable, Sendable {
    case duplicateFace(CubeFaceID)
    case missingFaces([CubeFaceID])
}

public enum CaptureAssembly {
    public static let sequence: [CubeFaceID] = [.front, .right, .back, .left, .up, .down]

    public static func assemble(_ captures: [CapturedFace]) throws -> CubeState {
        var faces: [CubeFaceID: CubeFace] = [:]
        for capture in captures {
            guard faces[capture.face] == nil else { throw CaptureAssemblyError.duplicateFace(capture.face) }
            faces[capture.face] = capture.canonicalFace
        }
        let missing = CubeFaceID.allCases.filter { faces[$0] == nil }
        guard missing.isEmpty else { throw CaptureAssemblyError.missingFaces(missing) }
        return try CubeState(faces: CubeFaceID.allCases.map { faces[$0]! })
    }
}
