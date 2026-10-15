import XCTest
import CubeCore
import CubeValidation
import CubeSolver
import AppWorkflow

@MainActor final class ManualEntryTests: XCTestCase {
    func testGuidedFaceProgressUndoEraseAndClear() throws {
        let entry = ManualCubeEntry()
        XCTAssertEqual(Set(ManualCubeEntry.faceOrder), Set(CubeFaceID.allCases))
        XCTAssertFalse(entry.canUndo)
        for face in ManualCubeEntry.faceOrder {
            for local in 0..<9 { try entry.setColor(.red, at: face.rawValue * 9 + local) }
            XCTAssertEqual(entry.filledCount(on: face), 9)
        }
        XCTAssertEqual(entry.completedFaceCount, 6)
        XCTAssertEqual(entry.count(.red), 54)
        XCTAssertFalse(entry.canSolve)
        try entry.setColor(nil, at: 0)
        XCTAssertEqual(entry.completedFaceCount, 5)
        entry.undo()
        XCTAssertEqual(entry.completedFaceCount, 6)
        entry.clear()
        XCTAssertEqual(entry.filledCount, 0)
        entry.undo()
        XCTAssertEqual(entry.filledCount, 54)
        entry.load(try .solved())
        XCTAssertTrue(entry.canSolve)
        entry.undo()
        XCTAssertEqual(entry.count(.red), 54)
    }

    func testNoOpPaintDoesNotConsumeUndoAndUndoInvalidatesSolution() async throws {
        let entry = ManualCubeEntry()
        try entry.setColor(nil, at: 0)
        XCTAssertFalse(entry.canUndo)
        try entry.setColor(.blue, at: 0)
        try entry.setColor(.blue, at: 0)
        entry.undo()
        XCTAssertEqual(entry.filledCount, 0)
        XCTAssertFalse(entry.canUndo)
        entry.load(try .solved())
        let task = try XCTUnwrap(entry.solve())
        await task.value
        XCTAssertNotNil(entry.session.solution)
        entry.undo()
        XCTAssertNil(entry.session.solution)
        XCTAssertEqual(entry.filledCount, 0)
    }

    func testIncompleteEntryEraseAndEditableCenters() throws {
        let entry = ManualCubeEntry()
        XCTAssertEqual(entry.filledCount, 0)
        XCTAssertNil(entry.cube)
        XCTAssertFalse(entry.canSolve)
        XCTAssertNil(try entry.solve())
        try entry.setColor(.orange, at: 4)
        XCTAssertEqual(entry.count(.orange), 1)
        XCTAssertEqual(entry.stickers[4]?.colorID, .orange)
        try entry.setColor(nil, at: 4)
        XCTAssertEqual(entry.filledCount, 0)
        XCTAssertThrowsError(try entry.setColor(.red, at: 54))
        XCTAssertThrowsError(try entry.setColor(nil, at: -1))
        entry.load(try .solved())
        entry.clear()
        XCTAssertNil(entry.cube)
        XCTAssertEqual(entry.session.phase, .idle)
    }

    func testInvalidCountsCentersAndImpossibleStateNeverReachSolver() async throws {
        let entry = ManualCubeEntry()
        let spy = CountingSolver()
        var centers = try CubeState.solved().stickers
        centers.swapAt(4, 9)
        var flipped = try CubeState.solved().stickers
        flipped.swapAt(5, 10) // UR edge flips, without changing color totals.
        let cases = [try CubeState.solved().replacingColor(at: 0, with: .red),
                     try CubeState(stickers: centers), try CubeState(stickers: flipped)]
        for cube in cases {
            entry.load(cube)
            XCTAssertFalse(entry.canSolve)
            XCTAssertFalse(try XCTUnwrap(entry.validation).isValid)
            XCTAssertNil(try entry.solve(using: spy))
            XCTAssertEqual(entry.session.phase, .requiresCorrection)
            XCTAssertNil(entry.session.solution)
        }
        let calls = await spy.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(entry.validation?.diagnostics, [.edgeFlipParity])
        XCTAssertTrue(CubeDiagnostic.edgeFlipParity.manualEntryMessage.contains("flipped"))
    }

    func testAll54ManualColorsSolveAndAnimateToVerifiedCompletion() async throws {
        let entry = ManualCubeEntry()
        // Different centers prove entry and playback do not assume white-up/green-front.
        let original = try CubeState.solved(centerColors: [.blue,.yellow,.red,.green,.white,.orange])
        let scramble = original.applying(try MoveNotation.parse("R U R' U' F2 D L2 B"))
        for (index, sticker) in scramble.stickers.enumerated() { try entry.setColor(sticker.colorID, at: index) }
        XCTAssertEqual(entry.filledCount, 54)
        XCTAssertTrue(entry.canSolve)
        let task = try XCTUnwrap(entry.solve())
        await task.value
        let solution = try XCTUnwrap(entry.session.solution)
        XCTAssertEqual(solution.initialCube, entry.cube)
        XCTAssertEqual(entry.session.phase, .solving)
        let playback = CubePlayback(solution: solution)
        XCTAssertNil(playback.begin(CubeMove(.up)), "A verified sequence cannot accept arbitrary turns")
        for index in solution.moves.indices {
            let turn = try XCTUnwrap(playback.beginNext())
            XCTAssertEqual(turn.move, solution.moves[index])
            XCTAssertEqual(playback.completedMoveCount, index)
            XCTAssertNil(playback.beginNext())
            XCTAssertTrue(playback.complete(turn.id))
            XCTAssertEqual(playback.cube, solution.initialCube.applying(Array(solution.moves.prefix(index + 1))))
            let replay = try XCTUnwrap(playback.replay())
            XCTAssertTrue(playback.complete(replay.id))
            XCTAssertEqual(playback.completedMoveCount, index + 1)
        }
        XCTAssertTrue(playback.isSolutionComplete)
        XCTAssertNil(playback.beginNext())
        XCTAssertEqual(playback.cube.stickers.map(\.colorID), original.stickers.map(\.colorID))
        try entry.session.complete()
        XCTAssertEqual(entry.session.phase, .completed)
    }

    func testPauseResumeRestartAndStaleAnimationCompletion() throws {
        let initial = try CubeState.solved().applying(MoveNotation.parse("R U"))
        let solution = try SolutionVerifier.verify(MoveNotation.parse("U' R'"), for: initial)
        let playback = CubePlayback(solution: solution)
        let cancelled = try XCTUnwrap(playback.beginNext())
        playback.cancel()
        XCTAssertEqual(playback.cube, initial)
        XCTAssertEqual(playback.completedMoveCount, 0)
        let resumed = try XCTUnwrap(playback.beginNext())
        XCTAssertFalse(playback.complete(cancelled.id))
        XCTAssertTrue(playback.complete(resumed.id))
        let second = try XCTUnwrap(playback.beginNext())
        playback.restartSolution()
        XCTAssertFalse(playback.complete(second.id))
        XCTAssertEqual(playback.cube, initial)
        XCTAssertEqual(playback.completedMoveCount, 0)
        XCTAssertNil(playback.lastTurn)
        while let turn = playback.beginNext() { XCTAssertTrue(playback.complete(turn.id)) }
        XCTAssertTrue(playback.isSolutionComplete)
        playback.restartSolution()
        XCTAssertFalse(playback.isSolutionComplete)
        playback.replace(with: try .solved())
        XCTAssertNil(playback.solution)
        XCTAssertFalse(playback.isSolutionComplete, "A solved explorer cube isn't a completed solution")
    }

    func testPreviousStepRestoresEveryEndpointAndCurrentHighlight() throws {
        let moves = try MoveNotation.parse("U' R2 F")
        let initial = try CubeState.solved().applying(MoveNotation.inverse(moves))
        let playback = CubePlayback(solution: try SolutionVerifier.verify(moves, for: initial))
        XCTAssertNil(playback.beginPrevious())
        XCTAssertEqual(playback.currentStepIndex, 0)
        while let turn = playback.beginNext() { XCTAssertTrue(playback.complete(turn.id)) }
        XCTAssertNil(playback.currentStepIndex)
        for index in moves.indices.reversed() {
            let before = playback.cube
            let back = try XCTUnwrap(playback.beginPrevious())
            XCTAssertTrue(back.isBackward)
            XCTAssertEqual(back.move, moves[index].inverse)
            XCTAssertEqual(playback.currentStepIndex, index)
            XCTAssertNil(playback.beginNext())
            XCTAssertNil(playback.beginPrevious())
            XCTAssertNil(playback.replay())
            playback.cancel()
            XCTAssertEqual(playback.cube, before)
            XCTAssertEqual(playback.completedMoveCount, index + 1)
            let retry = try XCTUnwrap(playback.beginPrevious())
            XCTAssertFalse(playback.complete(back.id))
            XCTAssertTrue(playback.complete(retry.id))
            XCTAssertEqual(playback.completedMoveCount, index)
            XCTAssertEqual(playback.cube, initial.applying(Array(moves.prefix(index))))
            XCTAssertEqual(playback.currentStepIndex, index)
            if index > 0 {
                let replay = try XCTUnwrap(playback.replay())
                XCTAssertEqual(replay.move, moves[index - 1])
                XCTAssertEqual(playback.currentStepIndex, index - 1)
                XCTAssertTrue(playback.complete(replay.id))
                XCTAssertEqual(playback.completedMoveCount, index)
            } else {
                XCTAssertNil(playback.replay())
            }
        }
        XCTAssertNil(playback.beginPrevious())
        while let turn = playback.beginNext() { XCTAssertTrue(playback.complete(turn.id)) }
        XCTAssertTrue(playback.isSolutionComplete)
        let pending = try XCTUnwrap(playback.beginPrevious())
        playback.restartSolution()
        XCTAssertFalse(playback.complete(pending.id))
        XCTAssertEqual(playback.currentStepIndex, 0)
        XCTAssertEqual(playback.cube, initial)
    }

    func testAlreadySolvedNeedsNoAnimation() async throws {
        let entry = ManualCubeEntry()
        entry.load(try .solved())
        let task = try XCTUnwrap(entry.solve())
        await task.value
        let playback = CubePlayback(solution: try XCTUnwrap(entry.session.solution))
        XCTAssertTrue(playback.isSolutionComplete)
        XCTAssertNil(playback.beginNext())
        XCTAssertNil(playback.replay())
    }

    func testEditingOrClearingInvalidatesLateSolution() async throws {
        for clear in [false, true] {
            let entry = ManualCubeEntry()
            entry.load(try .solved())
            let result = try SolutionVerifier.verify([], for: XCTUnwrap(entry.cube))
            let gate = ManualSolutionGate()
            let task = try XCTUnwrap(entry.solve(using: gate))
            await gate.waitUntilEntered()
            XCTAssertNil(try entry.solve(using: gate), "Repeated submit must not start another solver")
            if clear { entry.clear() } else { try entry.setColor(.red, at: 0) }
            await gate.resolve(result)
            await task.value
            XCTAssertNil(entry.session.solution)
            XCTAssertEqual(entry.session.phase, .idle)
            XCTAssertFalse(entry.canSolve)
        }
    }

    func testOrientationHintsAgreeWithCanonicalFaceBasis() {
        for face in CubeFaceID.allCases {
            let top = ManualCubeEntry.topNeighbor(of: face)
            XCTAssertEqual(CubeRenderLayout.axis(for: top), -CubeRenderLayout.facelets[face.rawValue * 9].down)
        }
    }
}

private actor CountingSolver: CubeSolving {
    private(set) var calls = 0
    func solve(_ cube: CubeState) async throws -> VerifiedSolution {
        calls += 1
        return try SolutionVerifier.verify([], for: cube)
    }
}

private actor ManualSolutionGate: CubeSolving {
    private var continuation: CheckedContinuation<VerifiedSolution, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func solve(_ cube: CubeState) async throws -> VerifiedSolution {
        await withCheckedContinuation {
            continuation = $0
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }
    func waitUntilEntered() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func resolve(_ result: VerifiedSolution) { continuation?.resume(returning: result); continuation = nil }
}
