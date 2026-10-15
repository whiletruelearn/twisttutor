import XCTest
import CubeCore
import CubeSolver

final class BeginnerSolverTests: XCTestCase {
    func testTeachingPlansSolveActualScramblesAndPreserveMilestones() async throws {
        var seed: UInt64 = 7623
        for sample in 0..<500 {
            var cube = try CubeState.solved()
            for _ in 0..<25 {
                seed = seed &* 6364136223846793005 &+ 1
                cube = cube.applying(CubeMove(CubeFaceID.allCases[Int((seed >> 32) % 6)], TurnAmount.allCases[Int((seed >> 40) % 3)]))
            }
            let plan = try await BeginnerSolver().plan(for: cube)
            XCTAssertEqual(plan.solution.initialCube, cube)
            XCTAssertTrue(cube.applying(plan.solution.moves).isSolved, "Sample \(sample)")
            var count = 0
            for lesson in plan.lessons {
                XCTAssertEqual(lesson.moveRange.lowerBound, count)
                if let piece = lesson.piece {
                    let before = cube.applying(Array(plan.solution.moves.prefix(count)))
                    XCTAssertEqual(Set(piece.currentIndices(in: before).map { before.stickers[$0].colorID }), Set(piece.colors))
                    let positions = Set(piece.currentIndices(in: before).map { CubeRenderLayout.facelets[$0].position })
                    XCTAssertEqual(positions.count, 1)
                    XCTAssertEqual(Set(piece.destinationIndices.map { CubeRenderLayout.facelets[$0].position }).count, 1)
                    XCTAssertEqual(piece.destinationIndices.count, piece.colors.count)
                }
                count = lesson.moveRange.upperBound
                let state = try CubeConversion.cubies(from: cube.applying(Array(plan.solution.moves.prefix(count))))
                if lesson.stage.rawValue >= 1 {
                    XCTAssertTrue((4..<8).allSatisfy { state.edgePermutation[$0] == $0 && state.edgeOrientation[$0] == 0 })
                }
                if lesson.stage.rawValue >= 2 {
                    XCTAssertTrue((4..<8).allSatisfy { state.cornerPermutation[$0] == $0 && state.cornerOrientation[$0] == 0 })
                }
                if lesson.stage.rawValue >= 3 {
                    XCTAssertTrue((8..<12).allSatisfy { state.edgePermutation[$0] == $0 && state.edgeOrientation[$0] == 0 })
                }
            }
            XCTAssertEqual(count, plan.solution.moves.count)
        }
    }
    func testSolvedAndRemappedCenters() async throws {
        let solved = try await BeginnerSolver().plan(for: .solved())
        XCTAssertTrue(solved.lessons.isEmpty)
        XCTAssertEqual(solved.alreadyComplete.count, 7)
        let cube = try CubeState.solved(centerColors: Array(CubeColorID.allCases.reversed())).applying(MoveNotation.parse("R U F2 L' B D2"))
        let plan = try await BeginnerSolver().plan(for: cube)
        XCTAssertTrue(cube.applying(plan.solution.moves).isSolved)
        XCTAssertEqual(cube.centerColors, cube.applying(plan.solution.moves).centerColors)
    }
    func testDeterminismAndInvalidState() async throws {
        let cube = try CubeState.solved().applying(MoveNotation.parse("R U F L D B R2"))
        let first = try await BeginnerSolver().plan(for: cube)
        let second = try await BeginnerSolver().plan(for: cube)
        XCTAssertEqual(first, second)
        var stickers = cube.stickers
        stickers[0].colorID = stickers[0].colorID == .white ? .red : .white
        do {
            _ = try await BeginnerSolver().plan(for: CubeState(stickers: stickers))
            XCTFail("Invalid colors accepted")
        } catch SolverError.invalidCube {} catch { XCTFail("\(error)") }
    }
    func testAlreadyFinishedStagesAreSkippedAfterEarlySolve() async throws {
        let cube = try CubeState.solved().applying(CubeMove(.down))
        let plan = try await BeginnerSolver().plan(for: cube)
        XCTAssertEqual(plan.lessons.map(\.stage), [.cross])
        XCTAssertEqual(plan.alreadyComplete, Array(BeginnerStage.allCases.dropFirst()))
        XCTAssertTrue(cube.applying(plan.solution.moves).isSolved)
    }
    func testCancellation() async throws {
        let work = Task { try await BeginnerSolver().plan(for: CubeState.solved().applying(MoveNotation.parse("F R U B D L"))) }
        work.cancel()
        do { _ = try await work.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }
}
