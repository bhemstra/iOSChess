/// A small but sound chess engine: negamax with alpha-beta pruning, a capture-only
/// quiescence search and a material + piece-square evaluation.
public struct Engine: Sendable {
    public enum Level: Int, Sendable, CaseIterable, Identifiable {
        case easy = 1, medium = 2, hard = 3
        public var id: Int { rawValue }
        var depth: Int { rawValue }
    }

    public var level: Level
    /// When true, picks randomly among moves that are (almost) equally good, for variety.
    public var randomize: Bool

    public init(level: Level = .medium, randomize: Bool = true) {
        self.level = level
        self.randomize = randomize
    }

    static let mateScore = 100_000
    static let infinity = 1_000_000

    /// The best move for the side to move, or nil when there is none (mate/stalemate)
    /// or the surrounding task was cancelled.
    public func bestMove(in position: Position) -> Move? {
        let moves = ordered(position.legalMoves(), in: position)
        guard !moves.isEmpty else { return nil }
        if moves.count == 1 { return moves[0] }

        var scored: [(Move, Int)] = []
        var alpha = -Self.infinity
        for move in moves {
            if Task.isCancelled { return nil }
            // Search with a slightly widened window so near-equal moves get exact scores.
            let window = randomize ? alpha - Self.randomMargin : alpha
            let score = -search(position.making(move), depth: level.depth - 1, ply: 1,
                                alpha: -Self.infinity, beta: -window)
            scored.append((move, score))
            alpha = max(alpha, score)
        }
        let best = scored.map(\.1).max()!
        let candidates = scored.filter { $0.1 >= best - (randomize ? Self.randomMargin : 0) }
        return randomize ? candidates.randomElement()!.0 : candidates[0].0
    }

    /// Moves within this many centipawns of the best are considered equally good.
    static let randomMargin = 15

    // MARK: - Search

    private func search(_ position: Position, depth: Int, ply: Int, alpha: Int, beta: Int) -> Int {
        if depth <= 0 { return quiescence(position, alpha: alpha, beta: beta, depth: 0) }

        let moves = ordered(position.legalMoves(), in: position)
        if moves.isEmpty {
            // Prefer faster mates and slower losses.
            return position.isCheck ? -Self.mateScore + ply : 0
        }
        if position.halfmoveClock >= 100 || position.hasInsufficientMaterial { return 0 }

        var alpha = alpha
        for move in moves {
            let score = -search(position.making(move), depth: depth - 1, ply: ply + 1, alpha: -beta, beta: -alpha)
            if score >= beta { return score }
            alpha = max(alpha, score)
        }
        return alpha
    }

    /// Only looks at captures and promotions so the evaluation isn't done in the middle of an exchange.
    private func quiescence(_ position: Position, alpha: Int, beta: Int, depth: Int) -> Int {
        let standPat = evaluate(position)
        if standPat >= beta || depth >= 6 { return standPat }
        var alpha = max(alpha, standPat)

        let tactical = position.pseudoLegalMoves().filter {
            position.capturedPiece(by: $0) != nil || $0.promotion != nil
        }
        for move in ordered(tactical, in: position) {
            let next = position.making(move)
            if next.isInCheck(position.sideToMove) { continue }
            let score = -quiescence(next, alpha: -beta, beta: -alpha, depth: depth + 1)
            if score >= beta { return score }
            alpha = max(alpha, score)
        }
        return alpha
    }

    /// Most valuable victim / least valuable attacker first, then promotions, then quiet moves.
    private func ordered(_ moves: [Move], in position: Position) -> [Move] {
        func key(_ move: Move) -> Int {
            var k = 0
            if let victim = position.capturedPiece(by: move) {
                k += 10 * Self.value(victim.kind) - Self.value(position[move.from]?.kind ?? .pawn) / 10
            }
            if let promotion = move.promotion { k += Self.value(promotion) }
            return k
        }
        return moves.sorted { key($0) > key($1) }
    }

    // MARK: - Evaluation

    static func value(_ kind: PieceKind) -> Int {
        switch kind {
        case .pawn: 100
        case .knight: 320
        case .bishop: 330
        case .rook: 500
        case .queen: 900
        case .king: 20_000
        }
    }

    /// Score in centipawns from the point of view of the side to move.
    public func evaluate(_ position: Position) -> Int {
        var score = 0
        for square in Square.all {
            guard let piece = position[square] else { continue }
            // Tables are written from white's view with rank 8 first.
            let row = piece.color == .white ? 7 - square.rank : square.rank
            let pieceScore = Self.value(piece.kind) + Self.table(for: piece.kind)[row * 8 + square.file]
            score += piece.color == .white ? pieceScore : -pieceScore
        }
        return position.sideToMove == .white ? score : -score
    }

    static func table(for kind: PieceKind) -> [Int] {
        switch kind {
        case .pawn: pawnTable
        case .knight: knightTable
        case .bishop: bishopTable
        case .rook: rookTable
        case .queen: queenTable
        case .king: kingTable
        }
    }

    // Simplified evaluation tables (after Tomasz Michniewski).
    static let pawnTable = [
         0,  0,  0,  0,  0,  0,  0,  0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
         5,  5, 10, 25, 25, 10,  5,  5,
         0,  0,  0, 20, 20,  0,  0,  0,
         5, -5,-10,  0,  0,-10, -5,  5,
         5, 10, 10,-20,-20, 10, 10,  5,
         0,  0,  0,  0,  0,  0,  0,  0,
    ]
    static let knightTable = [
        -50,-40,-30,-30,-30,-30,-40,-50,
        -40,-20,  0,  0,  0,  0,-20,-40,
        -30,  0, 10, 15, 15, 10,  0,-30,
        -30,  5, 15, 20, 20, 15,  5,-30,
        -30,  0, 15, 20, 20, 15,  0,-30,
        -30,  5, 10, 15, 15, 10,  5,-30,
        -40,-20,  0,  5,  5,  0,-20,-40,
        -50,-40,-30,-30,-30,-30,-40,-50,
    ]
    static let bishopTable = [
        -20,-10,-10,-10,-10,-10,-10,-20,
        -10,  0,  0,  0,  0,  0,  0,-10,
        -10,  0,  5, 10, 10,  5,  0,-10,
        -10,  5,  5, 10, 10,  5,  5,-10,
        -10,  0, 10, 10, 10, 10,  0,-10,
        -10, 10, 10, 10, 10, 10, 10,-10,
        -10,  5,  0,  0,  0,  0,  5,-10,
        -20,-10,-10,-10,-10,-10,-10,-20,
    ]
    static let rookTable = [
         0,  0,  0,  0,  0,  0,  0,  0,
         5, 10, 10, 10, 10, 10, 10,  5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
         0,  0,  0,  5,  5,  0,  0,  0,
    ]
    static let queenTable = [
        -20,-10,-10, -5, -5,-10,-10,-20,
        -10,  0,  0,  0,  0,  0,  0,-10,
        -10,  0,  5,  5,  5,  5,  0,-10,
         -5,  0,  5,  5,  5,  5,  0, -5,
          0,  0,  5,  5,  5,  5,  0, -5,
        -10,  5,  5,  5,  5,  5,  0,-10,
        -10,  0,  5,  0,  0,  0,  0,-10,
        -20,-10,-10, -5, -5,-10,-10,-20,
    ]
    static let kingTable = [
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -20,-30,-30,-40,-40,-30,-30,-20,
        -10,-20,-20,-20,-20,-20,-20,-10,
         20, 20,  0,  0,  0,  0, 20, 20,
         20, 30, 10,  0,  0, 10, 30, 20,
    ]
}
