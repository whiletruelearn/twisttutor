import XCTest
@_spi(Tooling) import CubeSolver

final class SolverBenchmarkTests: XCTestCase, @unchecked Sendable {
    /// Run this class alone in a fresh Release test process to include cold table loading.
    func testColdAndWarmPerformance() async throws {
        let report = try await SolverBenchmark.run(samples: 100)
        let data = try JSONEncoder().encode(report)
        print("SOLVER_BENCHMARK \(String(decoding: data, as: UTF8.self))")
        XCTAssertLessThanOrEqual(report.maximumMoves, 30)
        // Report timings rather than assert fragile simulator/CI speed thresholds.
        XCTAssertGreaterThan(report.tableBytes, 0)
    }
}
