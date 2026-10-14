import CubeCore
import CubeValidation
import Foundation

public enum SolverError: Error, Equatable, Sendable {
    case invalidCube([CubeDiagnostic])
    case tablesUnavailable
    case corruptTables
    case searchLimitReached
    case verificationFailed
    case resultForDifferentCube
}

/// A verified result cannot be constructed by an algorithm or UI without replay verification.
public struct VerifiedSolution: Equatable, Sendable {
    public let initialCube: CubeState
    public let moves: [CubeMove]
    fileprivate init(initialCube: CubeState, moves: [CubeMove]) { self.initialCube = initialCube; self.moves = moves }
}

public enum SolutionVerifier {
    public static func verify(_ moves: [CubeMove], for cube: CubeState) throws -> VerifiedSolution {
        let report = CubeValidator.validate(cube)
        guard report.isValid else { throw SolverError.invalidCube(report.diagnostics) }
        // Uses the facelet engine, not the solver's coordinate transitions or search assertions.
        guard cube.applying(moves).isSolved else { throw SolverError.verificationFailed }
        return VerifiedSolution(initialCube: cube, moves: moves)
    }
}

public protocol CubeSolving: Sendable {
    func solve(_ cube: CubeState) async throws -> VerifiedSolution
}

public struct SolverLimits: Sendable {
    public let maximumNodes: Int
    public let timeout: Duration
    public init(maximumNodes: Int = 50_000_000, timeout: Duration = .seconds(10)) {
        self.maximumNodes = max(0, maximumNodes)
        self.timeout = max(.zero, timeout)
    }
}

public struct QuickSolver: CubeSolving {
    public let limits: SolverLimits
    public init(limits: SolverLimits = SolverLimits()) { self.limits = limits }

    public func solve(_ cube: CubeState) async throws -> VerifiedSolution {
        try Task.checkCancellation()
        let limits = self.limits
        // Explicitly detached: synchronous search and table I/O must never execute on MainActor.
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let report = CubeValidator.validate(cube)
            guard report.isValid else { throw SolverError.invalidCube(report.diagnostics) }
            if cube.isSolved { return try SolutionVerifier.verify([], for: cube) }
            let deadline = ContinuousClock.now + limits.timeout
            let tables = try SolverTables.bundled.get()
            try Task.checkCancellation()
            let cubies = try CubeConversion.cubies(from: cube)
            let search = TwoPhaseSearch(tables: tables, initial: cubies, limits: limits, deadline: deadline)
            let moves = try search.solve()
            try Task.checkCancellation()
            return try SolutionVerifier.verify(moves, for: cube)
        }
        return try await withTaskCancellationHandler {
            let result = try await work.value
            try Task.checkCancellation()
            return result
        } onCancel: { work.cancel() }
    }
}
