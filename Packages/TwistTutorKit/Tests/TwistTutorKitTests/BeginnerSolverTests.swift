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

final class BeginnerCoachingTests: XCTestCase {
    /// The spoken directions must agree with the cube geometry, seen from the holding position.
    func testSpokenDirectionsMatchGeometry() throws {
        let solved = try CubeState.solved()
        func destinationFace(of index: Int, after move: String) throws -> CubeFaceID {
            let id = solved.stickers[index].id
            let moved = solved.applying(try MoveNotation.parse(move))
            return CubeFaceID(rawValue: moved.stickers.firstIndex { $0.id == id }! / 9)!
        }
        let front = CubeFaceID.front.rawValue * 9, up = CubeFaceID.up.rawValue * 9
        XCTAssertEqual(try destinationFace(of: front + 5, after: "R"), .up)      // right side up
        XCTAssertEqual(try destinationFace(of: front + 3, after: "L"), .down)    // left side down
        XCTAssertEqual(try destinationFace(of: front + 1, after: "U"), .left)    // top layer left
        XCTAssertEqual(try destinationFace(of: front + 7, after: "D"), .right)   // bottom layer right
        XCTAssertEqual(try destinationFace(of: up + 7, after: "F"), .right)      // front clockwise
        XCTAssertEqual(try destinationFace(of: up + 1, after: "B"), .left)       // back's top slides left
        XCTAssertEqual(CubeMove(.right).spokenInstruction, "Turn the right side up")
        XCTAssertEqual(CubeMove(.up, .counterclockwise).spokenInstruction, "Turn the top layer to the right")
        XCTAssertEqual(CubeMove(.left, .counterclockwise).shortLabel, "Left ↑")
    }

    func testLessonsFollowOnePieceAtATime() async throws {
        let cube = try CubeState.solved().applying(MoveNotation.parse("R U R' U' F2 D L2 B U2 R' F D'"))
        let plan = try await BeginnerSolver().plan(for: cube)
        let colors = CoachColors(cube: cube)
        for stage in [BeginnerStage.cross, .firstCorners, .middleEdges] {
            let lessons = plan.lessons.filter { $0.stage == stage }
            if stage != .middleEdges { XCTAssertLessThanOrEqual(lessons.count, 4, "\(stage) should teach one lesson per piece") }
            XCTAssertTrue(lessons.allSatisfy { $0.piece != nil })
        }
        for lesson in plan.lessons {
            XCTAssertFalse(lesson.headline(colors).isEmpty)
            XCTAssertFalse(lesson.coaching(colors).isEmpty)
            XCTAssertLessThanOrEqual(lesson.setupMoveCount, lesson.moveRange.count)
            XCTAssertTrue(lesson.setupMoveCount == 0 || plan.solution.moves[lesson.moveRange.lowerBound].face == .up)
        }
    }
}

extension BeginnerCoachingTests {
    /// The Learn tab's practice cube must exercise every goal. Keep in sync with LearnHomeView.practiceScramble.
    func testPracticeCubeTeachesEveryGoal() async throws {
        let cube = try CubeState.solved().applying(MoveNotation.parse("D2 F' R U2 L B2 D' R2 F L' U B' R2 D F2 U' L2 B R'"))
        let plan = try await BeginnerSolver().plan(for: cube)
        XCTAssertEqual(Set(plan.lessons.map(\.stage)), Set(BeginnerStage.allCases))
    }
}
