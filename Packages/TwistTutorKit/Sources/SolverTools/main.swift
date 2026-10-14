import Foundation
@_spi(Tooling) import CubeSolver

@main struct SolverTools {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            print("Usage: SolverTools generate <output.bin> | benchmark <sample-count>")
            return
        }
        switch arguments[1] {
        case "generate":
            let start = ContinuousClock.now
            try SolverTableGenerator.generate(at: URL(fileURLWithPath: arguments[2]))
            print("Generated tables in \(start.duration(to: .now))")
        case "benchmark":
            guard let count = Int(arguments[2]), (2...100_000).contains(count) else {
                print("Sample count must be 2...100000")
                return
            }
            let report = try await SolverBenchmark.run(samples: count)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        default: print("Unknown command: \(arguments[1])")
        }
    }
}
