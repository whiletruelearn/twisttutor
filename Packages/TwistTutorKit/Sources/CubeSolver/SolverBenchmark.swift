import CubeCore
import Foundation
import Darwin

@_spi(Tooling) public struct SolverBenchmarkReport: Codable, Sendable {
    public let sampleCount: Int
    public let firstSolveMilliseconds: Double
    public let warmMedianMilliseconds: Double
    public let warmP95Milliseconds: Double
    public let warmMaximumMilliseconds: Double
    public let minimumMoves: Int
    public let meanMoves: Double
    public let maximumMoves: Int
    public let peakResidentBytes: Int64
    public let tableBytes: Int
    public let operatingSystem: String
}

/// For comparable cold timings, invoke in a fresh process before any other solver use.
@_spi(Tooling) public enum SolverBenchmark {
    public static func run(samples: Int) async throws -> SolverBenchmarkReport {
        let count = max(2, samples)
        var seed: UInt64 = 0x599_600_601
        func next() -> UInt64 {
            seed &+= 0x9E3779B97F4A7C15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        let solved = try CubeState.solved()
        var times: [Double] = [], lengths: [Int] = []
        for _ in 0..<count {
            let moves = (0..<30).map { _ in Coordinates.moves[Int(next() % 18)] }
            let cube = solved.applying(moves)
            let start = ContinuousClock.now
            let result = try await QuickSolver().solve(cube)
            let elapsed = start.duration(to: .now).components
            times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            lengths.append(result.moves.count)
        }
        let warm = times.dropFirst().sorted()
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return SolverBenchmarkReport(
            sampleCount: count, firstSolveMilliseconds: times[0],
            warmMedianMilliseconds: warm[warm.count / 2], warmP95Milliseconds: warm[min(warm.count - 1, Int(Double(warm.count) * 0.95))],
            warmMaximumMilliseconds: warm.last!, minimumMoves: lengths.min()!,
            meanMoves: Double(lengths.reduce(0, +)) / Double(count), maximumMoves: lengths.max()!,
            peakResidentBytes: Int64(usage.ru_maxrss), tableBytes: SolverTables.byteCount,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}
