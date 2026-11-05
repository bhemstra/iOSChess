import Testing
@testable import ChessKit

@Suite("Engine")
struct EngineTests {
    let engine = Engine(level: .hard, randomize: false, timeLimit: .milliseconds(800))

    @Test func findsMateInOne() throws {
        // Back-rank mate: Re8#.
        let p = try #require(Position(fen: "6k1/5ppp/8/8/8/8/8/4R1K1 w - - 0 1"))
        #expect(engine.bestMove(in: p) == Move(uci: "e1e8"))
    }

    @Test func findsMateInTwo() throws {
        // Rook ladder: 1. Ra7 (any) 2. Rb8#.
        let p = try #require(Position(fen: "6k1/8/8/8/8/8/R7/1R4K1 w - - 0 1"))
        let result = try #require(engine.search(p))
        #expect(result.score > mateScore - 10, "expected a forced mate, got \(result.score)")
    }

    @Test("Mate in three", arguments: [
        // Smothered-mate pattern: Qg8+ Rxg8 Nf7#… (here: 1.Nf7+ Kg8 2.Nh6+ Kh8 3.Qg8+ Rxg8 4.Nf7#) is too long;
        // use a clean rook-and-king mate in 3 instead.
        "k7/8/1K6/8/8/8/8/7R w - - 0 1",
    ])
    func findsMateInThree(fen: String) throws {
        let p = try #require(Position(fen: fen))
        let result = try #require(engine.search(p))
        #expect(result.score > mateScore - 10, "expected a forced mate, got \(result.score)")
    }

    @Test func capturesHangingQueen() throws {
        let p = try #require(Position(fen: "4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1"))
        #expect(engine.bestMove(in: p) == Move(uci: "d2d5"))
    }

    @Test func doesNotGrabDefendedPawn() throws {
        // Qxd5 loses the queen to Rxd5.
        let p = try #require(Position(fen: "3rk3/8/8/3p4/8/8/8/3QK3 w - - 0 1"))
        #expect(engine.bestMove(in: p) != Move(uci: "d1d5"))
    }

    @Test func findsKnightFork() throws {
        // Nc7+ forks king and rook.
        let p = try #require(Position(fen: "r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1"))
        #expect(engine.bestMove(in: p) == Move(uci: "b5c7"))
    }

    @Test func avoidsBackRankMate() throws {
        // Black threatens Rd1#; white must not play the greedy Qxb7.
        let p = try #require(Position(fen: "3r2k1/1p3ppp/8/8/8/8/5PPP/1Q4K1 w - - 0 1"))
        let move = try #require(engine.bestMove(in: p))
        let after = p.making(move)
        let mateThreat = after.legalMoves().contains { reply in
            let next = after.making(reply)
            return next.isCheck && next.legalMoves().isEmpty
        }
        #expect(!mateThreat, "\(move) allows a back-rank mate")
    }

    @Test("Converts won endgames to mate", arguments: [
        "8/8/8/4k3/8/8/8/3QK3 w - - 0 1",   // K+Q v K
        "8/8/8/4k3/8/8/8/R3K3 w - - 0 1",   // K+R v K
    ])
    func convertsWonEndgame(fen: String) throws {
        var game = Game(position: try #require(Position(fen: fen)))
        let fast = Engine(level: .hard, randomize: false, timeLimit: .milliseconds(150))
        var plies = 0
        while !game.status.isOver, plies < 120 {
            let history = game.history.map(\.positionBefore)
            let move = try #require(fast.bestMove(in: game.position, history: history))
            try game.play(move)
            plies += 1
        }
        #expect(game.status == .checkmate(winner: .white), "ended with \(game.status) after \(plies) plies")
    }

    @Test func returnsNilWhenNoMoves() throws {
        let p = try #require(Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        #expect(engine.bestMove(in: p) == nil)
    }

    @Test func playsALegalMoveAtEveryLevel() throws {
        for level in Engine.Level.allCases {
            let move = try #require(Engine(level: level, timeLimit: .milliseconds(100)).bestMove(in: .start))
            #expect(Position.start.legalMoves().contains(move))
        }
    }

    @Test func evaluationIsColourSymmetric() throws {
        let fen = "r1bqk2r/pp2bppp/2n1pn2/3p4/2PP4/2N2N2/PP2BPPP/R2QKB1R w KQkq - 0 1"
        let p = try #require(Position(fen: fen))
        let mirrored = try #require(Position(fen: Self.mirror(fen)))
        #expect(engine.evaluate(p) == engine.evaluate(mirrored))
    }

    /// Swaps colours and flips the board vertically.
    static func mirror(_ fen: String) -> String {
        let fields = fen.split(separator: " ").map(String.init)
        let ranks = fields[0].split(separator: "/").reversed().map { rank in
            String(rank.map { $0.isUppercase ? Character($0.lowercased()) : Character($0.uppercased()) })
        }
        let side = fields[1] == "w" ? "b" : "w"
        let castle = fields[2] == "-" ? "-" : String(fields[2].map {
            $0.isUppercase ? Character($0.lowercased()) : Character($0.uppercased())
        }.sorted { $0.isUppercase && !$1.isUppercase })
        return [ranks.joined(separator: "/"), side, castle, "-", "0", "1"].joined(separator: " ")
    }
}
