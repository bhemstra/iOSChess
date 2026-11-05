public enum GameStatus: Sendable, Equatable {
    case ongoing
    case checkmate(winner: PieceColor)
    case stalemate
    case fiftyMoveRule
    case threefoldRepetition
    case insufficientMaterial

    public var isOver: Bool { self != .ongoing }
}

/// A game: the current position plus the history needed for undo,
/// a move list and repetition detection.
public struct Game: Sendable {
    public struct Record: Sendable, Hashable {
        public let move: Move
        public let san: String
        public let positionBefore: Position
    }

    public private(set) var position: Position
    public private(set) var history: [Record] = []
    public private(set) var status: GameStatus = .ongoing
    private var repetitions: [Position.RepetitionKey: Int] = [:]

    public enum MoveError: Error, Equatable { case illegalMove, gameOver }

    public init(position: Position = .start) {
        self.position = position
        repetitions[position.repetitionKey] = 1
        status = computeStatus()
    }

    public var legalMoves: [Move] { status.isOver ? [] : position.legalMoves() }

    public var lastMove: Move? { history.last?.move }

    public mutating func play(_ move: Move) throws(MoveError) {
        guard !status.isOver else { throw .gameOver }
        guard position.legalMoves().contains(move) else { throw .illegalMove }
        history.append(Record(move: move, san: position.san(for: move), positionBefore: position))
        position = position.making(move)
        repetitions[position.repetitionKey, default: 0] += 1
        status = computeStatus()
    }

    /// Takes back the last move. Returns false when there is nothing to undo.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let last = history.popLast() else { return false }
        let key = position.repetitionKey
        repetitions[key, default: 1] -= 1
        if repetitions[key] == 0 { repetitions[key] = nil }
        position = last.positionBefore
        status = computeStatus()
        return true
    }

    private func computeStatus() -> GameStatus {
        if position.legalMoves().isEmpty {
            return position.isCheck ? .checkmate(winner: position.sideToMove.opponent) : .stalemate
        }
        if position.hasInsufficientMaterial { return .insufficientMaterial }
        if position.halfmoveClock >= 100 { return .fiftyMoveRule }
        if repetitions[position.repetitionKey, default: 0] >= 3 { return .threefoldRepetition }
        return .ongoing
    }
}
