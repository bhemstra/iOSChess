import Foundation
import Testing
@testable import ChessKit

/// Prints search depth and speed from a middlegame position. Run with CHESS_BENCH=1.
@Suite("Benchmark", .enabled(if: ProcessInfo.processInfo.environment["CHESS_BENCH"] != nil))
struct BenchmarkTests {
    @Test func speed() {
        let p = Position(fen: "r1bqk2r/pp2bppp/2n1pn2/3p4/2PP4/2N2N2/PP2BPPP/R2QKB1R w KQkq - 0 1")!
        let clock = ContinuousClock()
        var result: Engine.SearchResult?
        let elapsed = clock.measure {
            result = Engine(level: .hard, randomize: false, timeLimit: .seconds(2)).search(p)
        }
        if let result {
            print("depth \(result.depth), \(result.nodes) nodes in \(elapsed) → \(Int(Double(result.nodes) / (Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds)))) n/s, best \(result.move) (\(result.score))")
        }
    }
}
