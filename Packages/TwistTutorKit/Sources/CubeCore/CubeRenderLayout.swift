/// Renderer-facing projection of the same canonical geometry used by the move engine.
/// Coordinates are cubie centers in -1...1; outward normals are unit axis vectors.
public enum CubeRenderLayout {
    public struct Facelet: Equatable, Sendable {
        public let index: Int
        public let position: SIMD3<Float>
        public let normal: SIMD3<Float>
        public let right: SIMD3<Float>
        public let down: SIMD3<Float>
    }

    public static let facelets: [Facelet] = CubeGeometry.locations.enumerated().map { index, location in
        Facelet(index: index, position: location.position.simd, normal: location.normal.simd,
                right: CubeGeometry.rights[index / 9].simd, down: CubeGeometry.downs[index / 9].simd)
    }

    public static func axis(for face: CubeFaceID) -> SIMD3<Float> { CubeGeometry.normals[face.rawValue].simd }

    /// Prime turns take the short positive quarter turn; double turns rotate clockwise.
    public static func angle(for move: CubeMove) -> Float {
        switch move.amount {
        case .clockwise: -.pi / 2
        case .counterclockwise: .pi / 2
        case .half: -.pi
        }
    }
}

private extension Vector {
    var simd: SIMD3<Float> { SIMD3(Float(x), Float(y), Float(z)) }
}
