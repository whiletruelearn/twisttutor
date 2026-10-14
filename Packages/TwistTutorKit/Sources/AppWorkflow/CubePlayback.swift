import Foundation
import Observation
import CubeCore

/// Commits only completed animations. A token prevents cancelled or late frames from committing.
@MainActor @Observable
public final class CubePlayback {
    public struct Turn: Equatable, Sendable {
        public let id: UUID
        public let move: CubeMove
        public let source: CubeState
        public let target: CubeState
        public let isReplay: Bool
    }

    public private(set) var cube: CubeState
    public private(set) var activeTurn: Turn?
    public private(set) var lastTurn: Turn?
    public var isBusy: Bool { activeTurn != nil }

    public init(cube: CubeState) { self.cube = cube }

    @discardableResult public func begin(_ move: CubeMove) -> Turn? {
        guard !isBusy else { return nil }
        let turn = Turn(id: UUID(), move: move, source: cube, target: cube.applying(move), isReplay: false)
        activeTurn = turn
        return turn
    }

    @discardableResult public func replay() -> Turn? {
        guard !isBusy, let lastTurn else { return nil }
        let turn = Turn(id: UUID(), move: lastTurn.move, source: lastTurn.source, target: lastTurn.target, isReplay: true)
        activeTurn = turn
        return turn
    }

    @discardableResult public func complete(_ id: UUID) -> Bool {
        guard let turn = activeTurn, turn.id == id else { return false }
        cube = turn.target
        if !turn.isReplay { lastTurn = turn }
        activeTurn = nil
        return true
    }

    public func cancel() { activeTurn = nil }

    public func replace(with cube: CubeState) {
        cancel()
        self.cube = cube
        lastTurn = nil
    }
}
