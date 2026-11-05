import Testing
@testable import ChessKit

/// Counts leaf nodes of the legal-move tree. The reference numbers below are the
/// well-known "perft" results; matching them proves move generation is correct,
/// including castling, en passant, promotion and pins.
func perft(_ position: Position, depth: Int) -> Int {
    if depth == 0 { return 1 }
    let moves = position.legalMoves()
    if depth == 1 { return moves.count }
    return moves.reduce(0) { $0 + perft(position.making($1), depth: depth - 1) }
}

@Suite("Move generation (perft)")
struct PerftTests {
    @Test("Start position", arguments: [(1, 20), (2, 400), (3, 8_902), (4, 197_281)])
    func start(depth: Int, expected: Int) {
        #expect(perft(.start, depth: depth) == expected)
    }

    @Test("Kiwipete: castling, pins, en passant", arguments: [(1, 48), (2, 2_039), (3, 97_862)])
    func kiwipete(depth: Int, expected: Int) throws {
        let p = try #require(Position(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"))
        #expect(perft(p, depth: depth) == expected)
    }

    @Test("Endgame with en-passant discovered checks", arguments: [(1, 14), (2, 191), (3, 2_812), (4, 43_238)])
    func position3(depth: Int, expected: Int) throws {
        let p = try #require(Position(fen: "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"))
        #expect(perft(p, depth: depth) == expected)
    }

    @Test("Promotions and castling rights", arguments: [(1, 6), (2, 264), (3, 9_467)])
    func position4(depth: Int, expected: Int) throws {
        let p = try #require(Position(fen: "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"))
        #expect(perft(p, depth: depth) == expected)
    }

    @Test("Position 5", arguments: [(1, 44), (2, 1_486), (3, 62_379)])
    func position5(depth: Int, expected: Int) throws {
        let p = try #require(Position(fen: "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"))
        #expect(perft(p, depth: depth) == expected)
    }
}

@Suite("Game rules")
struct GameTests {
    func play(_ sans: [String], from game: Game = Game()) throws -> Game {
        var game = game
        for san in sans {
            let move = try #require(game.position.move(fromSAN: san), "Illegal move \(san)")
            try game.play(move)
        }
        return game
    }

    @Test func fenRoundTrip() throws {
        let fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        #expect(try #require(Position(fen: fen)).fen == fen)
        #expect(Position.start.fen == Position.startFEN)
    }

    @Test func foolsMate() throws {
        let game = try play(["f3", "e5", "g4", "Qh4#"])
        #expect(game.status == .checkmate(winner: .black))
        #expect(game.history.last?.san == "Qh4#")
        #expect(game.legalMoves.isEmpty)
    }

    @Test func stalemate() throws {
        let p = try #require(Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        #expect(Game(position: p).status == .stalemate)
    }

    @Test func cannotMoveIntoCheck() throws {
        // White king on e1, black rook on d8: Kd1/Kd2 are illegal.
        let p = try #require(Position(fen: "3rk3/8/8/8/8/8/8/4K3 w - - 0 1"))
        let targets = Set(p.legalMoves(from: Square("e1")!).map(\.to.name))
        #expect(targets == ["e2", "f1", "f2"])
    }

    @Test func pinnedPieceCannotMove() throws {
        let p = try #require(Position(fen: "4r1k1/8/8/8/8/8/4N3/4K3 w - - 0 1"))
        #expect(p.legalMoves(from: Square("e2")!).isEmpty)
    }

    @Test func castlingBothSides() throws {
        let p = try #require(Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        let kingTargets = Set(p.legalMoves(from: Square("e1")!).map(\.to.name))
        #expect(kingTargets.isSuperset(of: ["g1", "c1"]))

        let after = p.making(Move(uci: "e1g1")!)
        #expect(after[Square("f1")!] == Piece(.rook, .white))
        #expect(after[Square("h1")!] == nil)
        #expect(!after.castling.contains(.whiteKingside))
        #expect(!after.castling.contains(.whiteQueenside))
        #expect(p.san(for: Move(uci: "e1c1")!) == "O-O-O")
    }

    @Test func noCastlingThroughCheck() throws {
        // Black bishop on a6 covers f1.
        let p = try #require(Position(fen: "4k3/8/b7/8/8/8/8/4K2R w K - 0 1"))
        #expect(!p.legalMoves().contains(Move(uci: "e1g1")!))
    }

    @Test func enPassant() throws {
        let game = try play(["e4", "a6", "e5", "d5"])
        #expect(game.position.enPassant == Square("d6"))
        let ep = Move(uci: "e5d6")!
        #expect(game.position.san(for: ep) == "exd6")
        let after = game.position.making(ep)
        #expect(after[Square("d5")!] == nil)
        #expect(after[Square("d6")!] == Piece(.pawn, .white))
    }

    @Test func promotion() throws {
        let p = try #require(Position(fen: "8/P6k/8/8/8/8/8/K7 w - - 0 1"))
        let promotions = p.legalMoves(from: Square("a7")!)
        #expect(promotions.count == 4)
        let after = p.making(Move(uci: "a7a8n")!)
        #expect(after[Square("a8")!] == Piece(.knight, .white))
        #expect(p.san(for: Move(uci: "a7a8q")!) == "a8=Q")
    }

    @Test func sanDisambiguation() throws {
        let p = try #require(Position(fen: "4k3/8/8/8/8/8/8/N3K1N1 w - - 0 1"))
        #expect(p.san(for: Move(uci: "a1b3")!) == "Nb3")
        let rooks = try #require(Position(fen: "4k3/8/8/8/8/8/4K3/R6R w - - 0 1"))
        #expect(rooks.san(for: Move(uci: "a1d1")!) == "Rad1")
    }

    @Test func threefoldRepetition() throws {
        let game = try play(["Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1", "Ng8"])
        #expect(game.status == .threefoldRepetition)
    }

    @Test func insufficientMaterial() throws {
        #expect(Game(position: Position(fen: "8/8/4k3/8/8/3NK3/8/8 w - - 0 1")!).status == .insufficientMaterial)
        #expect(Game(position: Position(fen: "8/8/4k3/8/8/3RK3/8/8 w - - 0 1")!).status == .ongoing)
    }

    @Test func fiftyMoveRule() throws {
        #expect(Game(position: Position(fen: "8/8/4k3/8/8/3RK3/8/8 w - - 100 80")!).status == .fiftyMoveRule)
    }

    @Test func undoRestoresPosition() throws {
        var game = try play(["e4", "e5"])
        game.undo()
        game.undo()
        #expect(game.position == .start)
        #expect(game.history.isEmpty)
        let undoneAgain = game.undo()
        #expect(!undoneAgain)
    }

    @Test func illegalMoveIsRejected() {
        #expect(throws: Game.MoveError.illegalMove) {
            var game = Game()
            try game.play(Move(uci: "e2e5")!)
        }
    }
}
