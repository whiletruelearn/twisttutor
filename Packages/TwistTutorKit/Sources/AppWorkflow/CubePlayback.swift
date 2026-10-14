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
        public var isBackward = false
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
    /// Zero-based step being animated, or the next step while paused.
    public var currentStepIndex: Int? {
        guard let solution, !solution.moves.isEmpty else { return nil }
        if let activeTurn, activeTurn.isReplay || activeTurn.isBackward {
            return completedMoveCount - 1
        }
        return completedMoveCount < solution.moves.count ? completedMoveCount : nil
    }
    public var canGoBack: Bool { solution != nil && completedMoveCount > 0 && !isBusy }

    @discardableResult public func beginPrevious() -> Turn? {
        guard canGoBack, let solution else { return nil }
        let move = solution.moves[completedMoveCount - 1].inverse
        let turn = Turn(id: UUID(), move: move, source: cube, target: cube.applying(move),
                        isReplay: false, isBackward: true)
        activeTurn = turn
        return turn
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
        if turn.isBackward, let solution {
            completedMoveCount -= 1
            // Replay always refers to the last completed forward step at this position.
            if completedMoveCount > 0 {
                let source = solution.initialCube.applying(Array(solution.moves.prefix(completedMoveCount - 1)))
                let move = solution.moves[completedMoveCount - 1]
                lastTurn = Turn(id: UUID(), move: move, source: source, target: cube, isReplay: false)
            } else {
                lastTurn = nil
            }
        } else if !turn.isReplay {
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
