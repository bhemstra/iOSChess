import Testing
@testable import ChessKit

@Suite("Engine")
struct EngineTests {
    let engine = Engine(level: .hard, randomize: false)

    @Test func findsMateInOne() throws {
        // Back-rank mate: Re8#.
        let p = try #require(Position(fen: "6k1/5ppp/8/8/8/8/8/4R1K1 w - - 0 1"))
        #expect(engine.bestMove(in: p) == Move(uci: "e1e8"))
    }

    @Test func findsMateInTwo() throws {
        // Two rooks ladder: 1. Ra7 (any) 2. Rb8#.
        let p = try #require(Position(fen: "6k1/8/8/8/8/8/R7/1R4K1 w - - 0 1"))
        let move = try #require(engine.bestMove(in: p))
        let after = p.making(move)
        // Whatever black does, white must have a mate next move.
        for reply in after.legalMoves() {
            let p2 = after.making(reply)
            let mate = p2.legalMoves().contains { p2.making($0).legalMoves().isEmpty && p2.making($0).isCheck }
            #expect(mate, "No mate after \(move) \(reply)")
        }
    }

    @Test func capturesHangingQueen() throws {
        let p = try #require(Position(fen: "4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1"))
        #expect(engine.bestMove(in: p) == Move(uci: "d2d5"))
    }

    @Test func doesNotGrabPoisonedPawn() throws {
        // Qxd5 loses the queen to ...Rxd5? No: the pawn on d5 is defended by the rook on d8.
        let p = try #require(Position(fen: "3rk3/8/8/3p4/8/8/8/3QK3 w - - 0 1"))
        #expect(engine.bestMove(in: p) != Move(uci: "d1d5"))
    }

    @Test func returnsNilWhenNoMoves() throws {
        let p = try #require(Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        #expect(engine.bestMove(in: p) == nil)
    }

    @Test func playsALegalMoveFromStart() throws {
        for level in Engine.Level.allCases {
            let move = try #require(Engine(level: level).bestMove(in: .start))
            #expect(Position.start.legalMoves().contains(move))
        }
    }

    @Test func evaluationIsSymmetric() {
        #expect(engine.evaluate(.start) == 0)
    }
}
