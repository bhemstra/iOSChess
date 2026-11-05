import ChessKit
import Observation

enum Opponent: Hashable {
    case human
    case computer(Engine.Level)
}

/// The UI state of one game: selection, drag-and-drop targets, promotion choice
/// and the computer opponent. All chess rules live in ChessKit.
@MainActor
@Observable
final class GameModel {
    struct BoardPiece: Identifiable {
        let id: Int
        let piece: Piece
        let square: Square
    }

    struct PromotionRequest: Identifiable {
        let from: Square
        let to: Square
        var id: String { from.name + to.name }
    }

    let opponent: Opponent
    /// The colour the (bottom) human player plays with.
    let humanColor: PieceColor

    private(set) var game = Game()
    private(set) var selected: Square?
    private(set) var isThinking = false
    var pendingPromotion: PromotionRequest?
    var isFlipped: Bool

    /// Stable identity per piece, so SwiftUI can slide pieces instead of fading them.
    private var pieceIDs: [Int: Int] = [:]
    private var nextPieceID = 0
    private var engineTask: Task<Void, Never>?

    /// Where "new game" starts from (only differs from the standard start in debug sessions).
    private let startPosition: Position

    init(opponent: Opponent, humanColor: PieceColor = .white, startPosition: Position = .start) {
        self.opponent = opponent
        self.startPosition = startPosition
        game = Game(position: startPosition)
        self.humanColor = humanColor
        isFlipped = humanColor == .black
        assignPieceIDs()
        startEngineIfNeeded()
    }

    // MARK: - Derived state

    var position: Position { game.position }

    var pieces: [BoardPiece] {
        Square.all.compactMap { square in
            guard let piece = position[square], let id = pieceIDs[square.index] else { return nil }
            return BoardPiece(id: id, piece: piece, square: square)
        }
    }

    var targets: Set<Square> {
        guard let selected else { return [] }
        return Set(position.legalMoves(from: selected).map(\.to))
    }

    var checkedKing: Square? {
        position.isCheck ? position.kingSquare(of: position.sideToMove) : nil
    }

    var isHumanTurn: Bool {
        guard !game.status.isOver, !isThinking else { return false }
        if case .computer = opponent { return position.sideToMove == humanColor }
        return true
    }

    var statusText: String {
        switch game.status {
        case .checkmate(let winner): "Schaakmat — \(winner.dutchName) wint"
        case .stalemate: "Pat — remise"
        case .fiftyMoveRule: "Remise (50-zettenregel)"
        case .threefoldRepetition: "Remise (drievoudige herhaling)"
        case .insufficientMaterial: "Remise (onvoldoende materiaal)"
        case .ongoing:
            if isThinking { "Computer denkt na…" }
            else if position.isCheck { "\(position.sideToMove.dutchName) staat schaak" }
            else { "\(position.sideToMove.dutchName) aan zet" }
        }
    }

    // MARK: - Input

    /// A tap on a square: select an own piece, or move the selected piece there.
    func tap(_ square: Square) {
        guard isHumanTurn else { return }
        if let selected, targets.contains(square) {
            attemptMove(from: selected, to: square)
        } else if position[square]?.color == position.sideToMove, square != selected {
            selected = square
        } else {
            selected = nil
        }
    }

    /// Start of a drag on `square`. Returns whether that piece may be dragged.
    func beginDrag(at square: Square) -> Bool {
        guard isHumanTurn, position[square]?.color == position.sideToMove else { return false }
        selected = square
        return true
    }

    func endDrag(from: Square, to: Square?) {
        guard let to, to != from else { return }
        attemptMove(from: from, to: to)
    }

    private func attemptMove(from: Square, to: Square) {
        let candidates = position.legalMoves(from: from).filter { $0.to == to }
        if candidates.count > 1 {
            pendingPromotion = PromotionRequest(from: from, to: to)
        } else if let move = candidates.first {
            play(move)
        }
    }

    func promote(to kind: PieceKind) {
        guard let request = pendingPromotion else { return }
        pendingPromotion = nil
        play(Move(from: request.from, to: request.to, promotion: kind))
    }

    func cancelPromotion() {
        pendingPromotion = nil
        selected = nil
    }

    // MARK: - Game flow

    private func play(_ move: Move) {
        let before = position
        do {
            try game.play(move)
        } catch {
            return
        }
        trackPieceIDs(for: move, in: before)
        selected = nil
        startEngineIfNeeded()
    }

    var canUndo: Bool { !game.history.isEmpty }

    /// Takes back the last move; against the computer, takes back a full turn.
    func undo() {
        stopEngine()
        game.undo()
        if case .computer = opponent, position.sideToMove != humanColor {
            game.undo()
        }
        selected = nil
        assignPieceIDs()
        startEngineIfNeeded()
    }

    func newGame() {
        stopEngine()
        game = Game(position: startPosition)
        selected = nil
        pendingPromotion = nil
        assignPieceIDs()
        startEngineIfNeeded()
    }

    // MARK: - Computer opponent

    private func startEngineIfNeeded() {
        guard case .computer(let level) = opponent,
              !game.status.isOver,
              position.sideToMove != humanColor else { return }

        isThinking = true
        let start = position
        let engine = Engine(level: level)
        engineTask = Task {
            // Search off the main thread; cancelling this task cancels the search.
            let search = Task.detached(priority: .userInitiated) { engine.bestMove(in: start) }
            async let minimumDelay: Void? = try? Task.sleep(for: .milliseconds(350))
            let move = await withTaskCancellationHandler {
                await search.value
            } onCancel: {
                search.cancel()
            }
            _ = await minimumDelay
            guard !Task.isCancelled, position == start else { return }
            isThinking = false
            if let move { play(move) }
        }
    }

    private func stopEngine() {
        engineTask?.cancel()
        engineTask = nil
        isThinking = false
    }

    // MARK: - Piece identity

    private func assignPieceIDs() {
        pieceIDs = [:]
        for square in Square.all where position[square] != nil {
            pieceIDs[square.index] = nextPieceID
            nextPieceID += 1
        }
    }

    private func trackPieceIDs(for move: Move, in before: Position) {
        let movingID = pieceIDs.removeValue(forKey: move.from.index)
        pieceIDs[move.to.index] = movingID
        // En passant removes a pawn that is not on the target square.
        if before[move.from]?.kind == .pawn, move.to == before.enPassant, move.from.file != move.to.file {
            pieceIDs[move.to.index - 8 * (before.sideToMove == .white ? 1 : -1)] = nil
        }
        if before.isCastling(move) {
            let rank = move.from.rank
            let (rookFrom, rookTo) = move.to.file == 6 ? (7, 5) : (0, 3)
            pieceIDs[rank * 8 + rookTo] = pieceIDs.removeValue(forKey: rank * 8 + rookFrom)
        }
    }
}

extension PieceColor {
    var dutchName: String { self == .white ? "Wit" : "Zwart" }
}

extension PieceKind {
    var dutchName: String {
        switch self {
        case .pawn: "Pion"
        case .knight: "Paard"
        case .bishop: "Loper"
        case .rook: "Toren"
        case .queen: "Dame"
        case .king: "Koning"
        }
    }
}
