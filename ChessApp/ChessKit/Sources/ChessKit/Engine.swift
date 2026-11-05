import Foundation

/// The computer opponent.
///
/// Principal-variation search with iterative deepening on a time budget, a
/// transposition table, null-move pruning, late-move reductions, check extensions,
/// killer/history move ordering and a quiescence search, on top of a tapered
/// PeSTO evaluation.
public struct Engine: Sendable {
    public enum Level: Int, Sendable, CaseIterable, Identifiable {
        case easy = 1, medium = 2, hard = 3
        public var id: Int { rawValue }

        /// Thinking time per move.
        var timeLimit: Duration {
            switch self {
            case .easy: .milliseconds(150)
            case .medium: .milliseconds(700)
            case .hard: .milliseconds(2500)
            }
        }

        var maxDepth: Int {
            switch self {
            case .easy: 2
            case .medium: 64
            case .hard: 64
            }
        }

        /// Root moves within this many centipawns of the best one may be picked for variety.
        var randomMargin: Int {
            switch self {
            case .easy: 60
            case .medium: 0
            case .hard: 0
            }
        }
    }

    public struct SearchResult: Sendable {
        public let move: Move
        /// Centipawns from the point of view of the side to move.
        public let score: Int
        public let depth: Int
        public let nodes: Int
    }

    public var level: Level
    /// When true, the easy level picks randomly among (almost) equally good moves.
    public var randomize: Bool
    /// Overrides the level's time budget (used by tests and benchmarks).
    public var timeLimit: Duration?
    /// Overrides the level's maximum depth (used by tests).
    public var maxDepth: Int?

    public init(level: Level = .medium, randomize: Bool = true, timeLimit: Duration? = nil, maxDepth: Int? = nil) {
        self.level = level
        self.randomize = randomize
        self.timeLimit = timeLimit
        self.maxDepth = maxDepth
    }

    /// The best move for the side to move, or nil when there is none (mate/stalemate)
    /// or the surrounding task was cancelled.
    /// - Parameter history: earlier positions of the game, so the engine can see repetitions.
    public func bestMove(in position: Position, history: [Position] = []) -> Move? {
        search(position, history: history)?.move
    }

    public func search(_ position: Position, history: [Position] = []) -> SearchResult? {
        let searcher = Searcher(
            deadline: ContinuousClock.now + (timeLimit ?? level.timeLimit),
            history: history.map(\.hash)
        )
        let margin = randomize ? level.randomMargin : 0
        return searcher.run(position, maxDepth: maxDepth ?? level.maxDepth, randomMargin: margin)
    }

    /// Static evaluation in centipawns from the point of view of the side to move.
    public func evaluate(_ position: Position) -> Int {
        Evaluation.evaluate(position)
    }
}

// MARK: - Search

let mateScore = 30_000
private let infinity = 32_000

private final class Searcher {
    private struct TTEntry {
        var key: UInt64 = 0
        var move: UInt16 = 0
        var score: Int32 = 0
        var depth: Int8 = -1
        var bound: UInt8 = 0   // 1 = exact, 2 = lower (fail high), 3 = upper (fail low)
    }

    private static let ttBits = 19
    private var tt = [TTEntry](repeating: TTEntry(), count: 1 << ttBits)
    private let ttMask = UInt64((1 << ttBits) - 1)

    private var killers = [[Move?]](repeating: [nil, nil], count: 128)
    private var historyScores = [Int](repeating: 0, count: 2 * 64 * 64)

    /// Hashes of the game so far plus the current search path, for repetition detection.
    private var path: [UInt64]
    private let deadline: ContinuousClock.Instant
    private var nodes = 0
    private var stopped = false

    init(deadline: ContinuousClock.Instant, history: [UInt64]) {
        self.deadline = deadline
        path = history
        path.reserveCapacity(history.count + 128)
    }

    func run(_ root: Position, maxDepth: Int, randomMargin: Int) -> Engine.SearchResult? {
        var rootMoves = root.legalMoves()
        guard !rootMoves.isEmpty else { return nil }
        if rootMoves.count == 1 {
            return Engine.SearchResult(move: rootMoves[0], score: 0, depth: 0, nodes: 0)
        }

        if randomMargin > 0 {
            return pickVaried(root, moves: rootMoves, depth: maxDepth, margin: randomMargin)
        }

        var best: Engine.SearchResult?
        path.append(root.hash)
        for depth in 1...maxDepth {
            var alpha = -infinity
            var iterationBest: (Move, Int)?
            // Search the previous best move first.
            if let previous = best?.move, let i = rootMoves.firstIndex(of: previous) {
                rootMoves.swapAt(0, i)
            }
            for (index, move) in rootMoves.enumerated() {
                let child = root.making(move)
                path.append(child.hash)
                var score: Int
                if index == 0 {
                    score = -search(child, depth: depth - 1, ply: 1, alpha: -infinity, beta: -alpha, allowNull: true)
                } else {
                    score = -search(child, depth: depth - 1, ply: 1, alpha: -alpha - 1, beta: -alpha, allowNull: true)
                    if score > alpha, !stopped {
                        score = -search(child, depth: depth - 1, ply: 1, alpha: -infinity, beta: -alpha, allowNull: true)
                    }
                }
                path.removeLast()
                if stopped { break }
                if score > alpha {
                    alpha = score
                    iterationBest = (move, score)
                }
            }
            // A partially searched iteration still counts if it improved on the old best move.
            if let (move, score) = iterationBest {
                best = Engine.SearchResult(move: move, score: score, depth: depth, nodes: nodes)
            }
            if stopped { break }
            // No need to look further once a forced mate is found.
            if abs(alpha) > mateScore - 200 { break }
            if ContinuousClock.now > deadline { break }
        }
        return best ?? Engine.SearchResult(move: rootMoves[0], score: 0, depth: 0, nodes: nodes)
    }

    /// Scores every root move exactly at a shallow depth and picks one of the good ones at random.
    private func pickVaried(_ root: Position, moves: [Move], depth: Int, margin: Int) -> Engine.SearchResult? {
        path.append(root.hash)
        var scored: [(Move, Int)] = []
        for move in moves {
            let child = root.making(move)
            path.append(child.hash)
            scored.append((move, -search(child, depth: depth - 1, ply: 1, alpha: -infinity, beta: infinity, allowNull: false)))
            path.removeLast()
        }
        let best = scored.map(\.1).max()!
        let (move, score) = scored.filter { $0.1 >= best - margin }.randomElement()!
        return Engine.SearchResult(move: move, score: score, depth: depth, nodes: nodes)
    }

    private func checkTime() {
        if nodes & 2047 == 0 && (ContinuousClock.now > deadline || Task.isCancelled) {
            stopped = true
        }
    }

    private func isRepetition(_ position: Position) -> Bool {
        // Only positions since the last capture or pawn move can repeat; same side to move.
        let current = path.count - 1
        var i = current - 2
        let limit = max(0, current - position.halfmoveClock)
        while i >= limit {
            if path[i] == position.hash { return true }
            i -= 2
        }
        return false
    }

    private func search(_ position: Position, depth: Int, ply: Int, alpha: Int, beta: Int, allowNull: Bool) -> Int {
        if position.halfmoveClock >= 100 || isRepetition(position) { return 0 }

        let inCheck = position.isCheck
        var depth = depth
        if inCheck { depth += 1 }
        if depth <= 0 { return quiescence(position, ply: ply, alpha: alpha, beta: beta) }

        nodes += 1
        checkTime()
        if stopped || ply >= 120 { return 0 }

        var alpha = alpha
        let isPV = beta - alpha > 1

        // Transposition table.
        let slot = Int(position.hash & ttMask)
        let entry = tt[slot]
        var ttMove: Move?
        if entry.key == position.hash {
            ttMove = decode(entry.move)
            if !isPV, Int(entry.depth) >= depth {
                let score = fromTT(Int(entry.score), ply: ply)
                switch entry.bound {
                case 1: return score
                case 2 where score >= beta: return score
                case 3 where score <= alpha: return score
                default: break
                }
            }
        }

        // Null-move pruning: if passing still beats beta, this position is good enough.
        if allowNull, !inCheck, !isPV, depth >= 3, beta < mateScore - 200,
           position.hasNonPawnMaterial(position.sideToMove),
           Evaluation.evaluate(position) >= beta {
            let reduction = depth >= 6 ? 3 : 2
            let child = position.makingNullMove()
            path.append(child.hash)
            let score = -search(child, depth: depth - 1 - reduction, ply: ply + 1, alpha: -beta, beta: -beta + 1, allowNull: false)
            path.removeLast()
            if stopped { return 0 }
            if score >= beta { return score >= mateScore - 200 ? beta : score }
        }

        var moves: [Move] = []
        moves.reserveCapacity(48)
        position.generateMoves(into: &moves)
        var scores = moves.map { orderScore($0, in: position, ttMove: ttMove, ply: ply) }

        let us = position.sideToMove
        var bestScore = -infinity
        var bestMove: Move?
        var legalCount = 0
        let originalAlpha = alpha

        for i in 0..<moves.count {
            // Selection sort: pick the most promising remaining move.
            var top = i
            for j in (i + 1)..<moves.count where scores[j] > scores[top] { top = j }
            if top != i { moves.swapAt(i, top); scores.swapAt(i, top) }
            let move = moves[i]

            let child = position.making(move)
            if child.isInCheck(us) { continue }
            legalCount += 1

            let isQuiet = position.capturedPiece(by: move) == nil && move.promotion == nil
            path.append(child.hash)
            var score: Int
            if legalCount == 1 {
                score = -search(child, depth: depth - 1, ply: ply + 1, alpha: -beta, beta: -alpha, allowNull: true)
            } else {
                // Late-move reductions for quiet moves that are ordered late.
                var reduction = 0
                if depth >= 3, legalCount > 3, isQuiet, !inCheck, !child.isCheck {
                    reduction = legalCount > 10 ? 2 : 1
                }
                score = -search(child, depth: depth - 1 - reduction, ply: ply + 1, alpha: -alpha - 1, beta: -alpha, allowNull: true)
                if score > alpha, reduction > 0 {
                    score = -search(child, depth: depth - 1, ply: ply + 1, alpha: -alpha - 1, beta: -alpha, allowNull: true)
                }
                if score > alpha, score < beta {
                    score = -search(child, depth: depth - 1, ply: ply + 1, alpha: -beta, beta: -alpha, allowNull: true)
                }
            }
            path.removeLast()
            if stopped { return 0 }

            if score > bestScore {
                bestScore = score
                bestMove = move
            }
            if score > alpha {
                alpha = score
                if score >= beta {
                    if isQuiet {
                        if killers[ply][0] != move {
                            killers[ply][1] = killers[ply][0]
                            killers[ply][0] = move
                        }
                        historyScores[historyIndex(move, us)] += depth * depth
                    }
                    break
                }
            }
        }

        if legalCount == 0 {
            return inCheck ? -mateScore + ply : 0
        }

        let bound: UInt8 = bestScore >= beta ? 2 : bestScore > originalAlpha ? 1 : 3
        tt[slot] = TTEntry(key: position.hash, move: encode(bestMove), score: Int32(toTT(bestScore, ply: ply)),
                           depth: Int8(clamping: depth), bound: bound)
        return bestScore
    }

    private func quiescence(_ position: Position, ply: Int, alpha: Int, beta: Int) -> Int {
        nodes += 1
        checkTime()
        if stopped { return 0 }

        let standPat = Evaluation.evaluate(position)
        if standPat >= beta || ply >= 120 { return standPat }
        var alpha = max(alpha, standPat)

        var moves: [Move] = []
        moves.reserveCapacity(16)
        position.generateMoves(into: &moves, capturesOnly: true)
        var scores = moves.map { orderScore($0, in: position, ttMove: nil, ply: ply) }
        let us = position.sideToMove

        for i in 0..<moves.count {
            var top = i
            for j in (i + 1)..<moves.count where scores[j] > scores[top] { top = j }
            if top != i { moves.swapAt(i, top); scores.swapAt(i, top) }
            let move = moves[i]

            // Delta pruning: even winning this piece can't bring the score up to alpha.
            if move.promotion == nil, let victim = position.capturedPiece(by: move),
               standPat + Evaluation.pieceValue(victim.kind) + 200 < alpha {
                continue
            }
            let child = position.making(move)
            if child.isInCheck(us) { continue }
            let score = -quiescence(child, ply: ply + 1, alpha: -beta, beta: -alpha)
            if stopped { return 0 }
            if score >= beta { return score }
            alpha = max(alpha, score)
        }
        return alpha
    }

    // MARK: Move ordering

    private func orderScore(_ move: Move, in position: Position, ttMove: Move?, ply: Int) -> Int {
        if move == ttMove { return 10_000_000 }
        if let victim = position.capturedPiece(by: move) {
            let attacker = position[move.from]?.kind ?? .pawn
            return 1_000_000 + 10 * Evaluation.pieceValue(victim.kind) - Evaluation.pieceValue(attacker) / 10
        }
        if let promotion = move.promotion { return 900_000 + Evaluation.pieceValue(promotion) }
        if killers[ply][0] == move { return 800_000 }
        if killers[ply][1] == move { return 700_000 }
        return historyScores[historyIndex(move, position.sideToMove)]
    }

    private func historyIndex(_ move: Move, _ color: PieceColor) -> Int {
        (color == .white ? 0 : 4096) + move.from.index * 64 + move.to.index
    }

    // MARK: TT helpers

    /// Mate scores are stored relative to the node, not the root.
    private func toTT(_ score: Int, ply: Int) -> Int {
        score > mateScore - 200 ? score + ply : score < -mateScore + 200 ? score - ply : score
    }

    private func fromTT(_ score: Int, ply: Int) -> Int {
        score > mateScore - 200 ? score - ply : score < -mateScore + 200 ? score + ply : score
    }

    private func encode(_ move: Move?) -> UInt16 {
        guard let move else { return 0 }
        let promo: UInt16 = switch move.promotion {
        case .knight: 1
        case .bishop: 2
        case .rook: 3
        case .queen: 4
        default: 0
        }
        return UInt16(move.from.index) | UInt16(move.to.index) << 6 | promo << 12
    }

    private func decode(_ raw: UInt16) -> Move? {
        guard raw != 0 else { return nil }
        let promo: PieceKind? = switch raw >> 12 {
        case 1: .knight
        case 2: .bishop
        case 3: .rook
        case 4: .queen
        default: nil
        }
        return Move(from: Square(index: Int(raw & 63)), to: Square(index: Int(raw >> 6 & 63)), promotion: promo)
    }
}
