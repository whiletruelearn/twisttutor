import Foundation
import Observation
import CubeCore
import CubeSolver

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
    public private(set) var solution: VerifiedSolution?
    public private(set) var completedMoveCount = 0
    public var isSolutionComplete: Bool {
        guard let solution else { return false }
        return completedMoveCount == solution.moves.count && cube.isSolved && !isBusy
    }
    public var nextMove: CubeMove? {
        guard let solution, completedMoveCount < solution.moves.count else { return nil }
        return solution.moves[completedMoveCount]
    }
    public var isBusy: Bool { activeTurn != nil }

    public init(cube: CubeState) { self.cube = cube }

    public init(solution: VerifiedSolution) {
        self.solution = solution
        cube = solution.initialCube
    }

    @discardableResult public func beginNext() -> Turn? {
        guard !isBusy, let nextMove else { return nil }
        return beginTurn(nextMove)
    }

    public func restartSolution() {
        guard let solution else { return }
        cancel()
        cube = solution.initialCube
        completedMoveCount = 0
        lastTurn = nil
    }

    @discardableResult public func begin(_ move: CubeMove) -> Turn? {
        guard !isBusy, solution == nil else { return nil }
        return beginTurn(move)
    }

    private func beginTurn(_ move: CubeMove) -> Turn {
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
        if !turn.isReplay {
            lastTurn = turn
            if solution != nil { completedMoveCount += 1 }
        }
        activeTurn = nil
        return true
    }

    public func cancel() { activeTurn = nil }

    public func replace(with cube: CubeState) {
        cancel()
        self.cube = cube
        solution = nil
        completedMoveCount = 0
        lastTurn = nil
    }
}
