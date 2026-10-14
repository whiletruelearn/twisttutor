public enum TurnAmount: Int, CaseIterable, Sendable {
    case clockwise = 1, half = 2, counterclockwise = 3
}

public struct CubeMove: Equatable, Hashable, Sendable {
    public let face: CubeFaceID
    public let amount: TurnAmount

    public init(_ face: CubeFaceID, _ amount: TurnAmount = .clockwise) {
        self.face = face
        self.amount = amount
    }

    public var inverse: CubeMove {
        CubeMove(face, amount == .half ? .half : (amount == .clockwise ? .counterclockwise : .clockwise))
    }

    public var notation: String {
        face.notation + (amount == .half ? "2" : (amount == .counterclockwise ? "'" : ""))
    }
}

public enum NotationError: Error, Equatable, Sendable { case invalidToken(String) }

public enum MoveNotation {
    /// Only outer face turns are in V1. Reject unsupported notation instead of partially parsing it.
    public static func parse(_ text: String) throws -> [CubeMove] {
        try text.split(whereSeparator: \.isWhitespace).map { token in
            let value = String(token)
            guard let face = CubeFaceID.allCases.first(where: { $0.notation == String(value.prefix(1)) }) else {
                throw NotationError.invalidToken(value)
            }
            let amount: TurnAmount
            switch value.dropFirst() {
            case "": amount = .clockwise
            case "'": amount = .counterclockwise
            case "2": amount = .half
            default: throw NotationError.invalidToken(value)
            }
            return CubeMove(face, amount)
        }
    }

    public static func format(_ moves: [CubeMove]) -> String { moves.map(\.notation).joined(separator: " ") }
    public static func inverse(_ moves: [CubeMove]) -> [CubeMove] { moves.reversed().map(\.inverse) }
}
