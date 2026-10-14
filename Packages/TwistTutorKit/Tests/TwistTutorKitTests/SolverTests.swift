import XCTest
import CubeCore
import CubeValidation
import CryptoKit
@testable import CubeSolver

final class SolverTests: XCTestCase, @unchecked Sendable {
    func testAlreadySolvedReturnsVerifiedEmptySequence() async throws {
        let cube = try CubeState.solved()
        let result = try await QuickSolver().solve(cube)
        XCTAssertEqual(result.initialCube, cube)
        XCTAssertTrue(result.moves.isEmpty)
    }

    func testKnownScramblesAndPhaseTwoStates() async throws {
        for notation in ["R", "U2", "B'", "R U R' U'", "F R U R' U' F'", "U R2 D' F2 L2 B2 U2", "R2 L2 U2 D2 F2 B2"] {
            let cube = try CubeState.solved().applying(MoveNotation.parse(notation))
            let result = try await QuickSolver().solve(cube)
            XCTAssertTrue(cube.applying(result.moves).isSolved, notation)
            XCTAssertLessThanOrEqual(result.moves.count, 30)
        }
    }

    func testSeededScrambleSolveReplayRegression() async throws {
        var random = SeededRandom(seed: 0x599601)
        let count = ProcessInfo.processInfo.environment["TWISTTUTOR_SOLVER_CASES"].flatMap(Int.init) ?? 100
        let cube = try CubeState.solved()
        for sample in 0..<count {
            let scramble = (0..<30).map { _ in CubeMove(CubeFaceID.allCases[Int(random.next() % 6)], TurnAmount.allCases[Int(random.next() % 3)]) }
            let input = cube.applying(scramble)
            let result = try await QuickSolver().solve(input)
            XCTAssertEqual(result.initialCube, input)
            XCTAssertTrue(input.applying(result.moves).isSolved, "sample \(sample)")
            XCTAssertLessThanOrEqual(result.moves.count, 30)
            XCTAssertEqual(input, cube.applying(scramble), "Input must not mutate")
        }
    }

    func testIndependentRandomReachableCubieStates() async throws {
        var random = SeededRandom(seed: 0x600)
        for _ in 0..<50 {
            var cp = Array(0..<8), ep = Array(0..<12)
            for i in stride(from: 7, through: 1, by: -1) { cp.swapAt(i, Int(random.next() % UInt64(i + 1))) }
            for i in stride(from: 11, through: 1, by: -1) { ep.swapAt(i, Int(random.next() % UInt64(i + 1))) }
            let co = Coordinates.orientations(Int(random.next() % 2187), count: 8, base: 3)
            let eo = Coordinates.orientations(Int(random.next() % 2048), count: 12, base: 2)
            var state = try CubieState(cornerPermutation: cp, cornerOrientation: co, edgePermutation: ep, edgeOrientation: eo)
            if !CubeValidator.validate(state).isValid {
                ep.swapAt(0, 1)
                state = try CubieState(cornerPermutation: cp, cornerOrientation: co, edgePermutation: ep, edgeOrientation: eo)
            }
            let cube = try CubeConversion.facelets(from: state, centerColors: [.blue, .yellow, .red, .green, .white, .orange])
            let result = try await QuickSolver().solve(cube)
            XCTAssertTrue(cube.applying(result.moves).isSolved)
        }
    }

    func testImpossibleInputIsRejected() async throws {
        let badCount = try CubeState.solved().replacingColor(at: 0, with: .red)
        let flipped = try CubieState(cornerPermutation: Array(0..<8), cornerOrientation: Array(repeating: 0, count: 8),
                                    edgePermutation: Array(0..<12), edgeOrientation: [1] + Array(repeating: 0, count: 11))
        for cube in [badCount, try CubeConversion.facelets(from: flipped)] {
            do {
                _ = try await QuickSolver().solve(cube)
                XCTFail("Invalid input reached solver")
            } catch let error as SolverError {
                guard case .invalidCube = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testIndependentVerifierRejectsBadOutput() throws {
        let cube = try CubeState.solved().applying(CubeMove(.right))
        for wrong in [[], [CubeMove(.right)], [CubeMove(.up)]] {
            XCTAssertThrowsError(try SolutionVerifier.verify(wrong, for: cube)) {
                XCTAssertEqual($0 as? SolverError, .verificationFailed)
            }
        }
        let result = try SolutionVerifier.verify([CubeMove(.right, .counterclockwise)], for: cube)
        XCTAssertTrue(cube.applying(result.moves).isSolved)
    }

    func testNodeAndTimeLimitsReturnFailureNotPartialMoves() async throws {
        let cube = try CubeState.solved().applying(MoveNotation.parse("R F U L D"))
        for limits in [SolverLimits(maximumNodes: 0), SolverLimits(timeout: .zero)] {
            do {
                _ = try await QuickSolver(limits: limits).solve(cube)
                XCTFail("Expected limit failure")
            } catch { XCTAssertEqual(error as? SolverError, .searchLimitReached) }
        }
    }

    func testCancelledRequestNeverReturnsSolution() async throws {
        let cube = try CubeState.solved().applying(MoveNotation.parse("R F U L D B R2 F2 L2 U'"))
        let request = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await QuickSolver().solve(cube)
        }
        do { _ = try await request.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSearchCooperativelyChecksCancellation() async throws {
        let tables = try SolverTables.bundled.get()
        let request = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            let search = TwoPhaseSearch(tables: tables, initial: .solved, limits: SolverLimits(), deadline: .now + .seconds(10))
            return try search.solve()
        }
        do { _ = try await request.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testConcurrentRequestsShareNoMutableSearchState() async throws {
        let cube = try CubeState.solved()
        let inputs = try ["R U F", "B D L2", "U2 R2 D'", "F' L U B'"].map { try cube.applying(MoveNotation.parse($0)) }
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for input in inputs { group.addTask { let result = try await QuickSolver().solve(input); return input.applying(result.moves).isSolved } }
            for try await solved in group { XCTAssertTrue(solved) }
        }
    }

    func testBundledTablesRejectTruncationOrCorruption() throws {
        let data = try SolverTables.bundled.get().encoded()
        XCTAssertEqual(data.count, SolverTables.byteCount)
        XCTAssertThrowsError(try SolverTables.decode(data.dropLast()))
        var damaged = data; damaged[100] ^= 1
        XCTAssertThrowsError(try SolverTables.decode(damaged)) { XCTAssertEqual($0 as? SolverError, .corruptTables) }
        damaged = data; damaged[0] ^= 1
        XCTAssertThrowsError(try SolverTables.decode(damaged))
        // A well-checksummed file with invalid transition indices must still be rejected.
        damaged = data; damaged[8] = 255; damaged[9] = 255
        damaged.replaceSubrange((damaged.count - 32)..<damaged.count, with: Array(SHA256.hash(data: damaged.dropLast(32))))
        XCTAssertThrowsError(try SolverTables.decode(damaged))
        // Phase-one lower bounds cannot exceed its search bound of 12.
        damaged = data
        let firstDistance = 8 + SolverTables.moveDimensions.reduce(0) { $0 + $1.0 * $1.1 * 2 }
        damaged[firstDistance] = 13
        damaged.replaceSubrange((damaged.count - 32)..<damaged.count, with: Array(SHA256.hash(data: damaged.dropLast(32))))
        XCTAssertThrowsError(try SolverTables.decode(damaged))
    }

    func testCoordinateRanksAndTransitionsMatchCore() throws {
        for count in [4, 8] {
            let limit = count == 4 ? 24 : 40320
            for rank in 0..<limit { XCTAssertEqual(Coordinates.permutation(Coordinates.permutation(rank, count: count)), rank) }
        }
        let tables = try SolverTables.bundled.get()
        var random = SeededRandom(seed: 0xC001)
        var state = CubieState.solved
        for _ in 0..<100 {
            let twist = Coordinates.orientation(state.cornerOrientation, base: 3)
            let flip = Coordinates.orientation(state.edgeOrientation, base: 2)
            let slice = Coordinates.slice(state.edgePermutation)
            for (index, move) in Coordinates.moves.enumerated() {
                let next = state.applying(move)
                XCTAssertEqual(Int(tables.twistMoves[twist * 18 + index]), Coordinates.orientation(next.cornerOrientation, base: 3))
                XCTAssertEqual(Int(tables.flipMoves[flip * 18 + index]), Coordinates.orientation(next.edgeOrientation, base: 2))
                XCTAssertEqual(Int(tables.sliceMoves[slice * 18 + index]), Coordinates.slice(next.edgePermutation))
            }
            state = state.applying(Coordinates.moves[Int(random.next() % 18)])
        }
    }
}
