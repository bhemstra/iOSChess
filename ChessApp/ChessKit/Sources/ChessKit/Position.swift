/// A complete, immutable-by-default chess position: piece placement, side to move,
/// castling rights, en-passant square and move clocks. Value type, so "trying" a
/// move is simply making it on a copy.
public struct Position: Sendable, Hashable {
    public private(set) var board: [Piece?]
    public private(set) var sideToMove: PieceColor
    public private(set) var castling: CastlingRights
    /// The square a pawn may capture onto en passant (set right after a double push).
    public private(set) var enPassant: Square?
    public private(set) var halfmoveClock: Int
    public private(set) var fullmoveNumber: Int

    public static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    public static let start = Position(fen: startFEN)!

    public subscript(square: Square) -> Piece? { board[square.index] }

    // MARK: - FEN

    public init?(fen: String) {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2 else { return nil }

        var board = [Piece?](repeating: nil, count: 64)
        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return nil }
        for (i, rankString) in ranks.enumerated() {
            let rank = 7 - i
            var file = 0
            for c in rankString {
                if let n = c.wholeNumberValue {
                    file += n
                } else {
                    guard let piece = Piece(fenCharacter: c), let sq = Square(file: file, rank: rank) else { return nil }
                    board[sq.index] = piece
                    file += 1
                }
            }
            guard file == 8 else { return nil }
        }
        self.board = board

        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: return nil
        }

        var castling = CastlingRights()
        if fields.count > 2 {
            for c in fields[2] {
                switch c {
                case "K": castling.insert(.whiteKingside)
                case "Q": castling.insert(.whiteQueenside)
                case "k": castling.insert(.blackKingside)
                case "q": castling.insert(.blackQueenside)
                case "-": break
                default: return nil
                }
            }
        }
        self.castling = castling
        enPassant = fields.count > 3 && fields[3] != "-" ? Square(String(fields[3])) : nil
        halfmoveClock = fields.count > 4 ? Int(fields[4]) ?? 0 : 0
        fullmoveNumber = fields.count > 5 ? Int(fields[5]) ?? 1 : 1
    }

    public var fen: String {
        var rows: [String] = []
        for rank in (0..<8).reversed() {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = board[rank * 8 + file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row.append(piece.fenCharacter)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }
        var castle = ""
        if castling.contains(.whiteKingside) { castle += "K" }
        if castling.contains(.whiteQueenside) { castle += "Q" }
        if castling.contains(.blackKingside) { castle += "k" }
        if castling.contains(.blackQueenside) { castle += "q" }
        if castle.isEmpty { castle = "-" }
        return [rows.joined(separator: "/"), sideToMove == .white ? "w" : "b", castle,
                enPassant?.name ?? "-", String(halfmoveClock), String(fullmoveNumber)].joined(separator: " ")
    }

    // MARK: - Attacks

    static let knightOffsets = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    static let kingOffsets = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    static let rookDirections = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    static let bishopDirections = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

    public func kingSquare(of color: PieceColor) -> Square? {
        let king = Piece(.king, color)
        return board.firstIndex(of: king).map(Square.init(index:))
    }

    /// Whether `square` is attacked by any piece of `attacker`.
    public func isAttacked(_ square: Square, by attacker: PieceColor) -> Bool {
        // Pawns attack diagonally forward, so look one rank "behind" the square.
        for df in [-1, 1] {
            if let s = square.offset(df, -attacker.pawnDirection), board[s.index] == Piece(.pawn, attacker) {
                return true
            }
        }
        for (df, dr) in Self.knightOffsets {
            if let s = square.offset(df, dr), board[s.index] == Piece(.knight, attacker) { return true }
        }
        for (df, dr) in Self.kingOffsets {
            if let s = square.offset(df, dr), board[s.index] == Piece(.king, attacker) { return true }
        }
        for (dirs, slider) in [(Self.rookDirections, PieceKind.rook), (Self.bishopDirections, .bishop)] {
            for (df, dr) in dirs {
                var current = square.offset(df, dr)
                while let s = current {
                    if let piece = board[s.index] {
                        if piece.color == attacker && (piece.kind == slider || piece.kind == .queen) { return true }
                        break
                    }
                    current = s.offset(df, dr)
                }
            }
        }
        return false
    }

    public func isInCheck(_ color: PieceColor) -> Bool {
        guard let king = kingSquare(of: color) else { return false }
        return isAttacked(king, by: color.opponent)
    }

    /// Whether the side to move is in check.
    public var isCheck: Bool { isInCheck(sideToMove) }

    // MARK: - Move generation

    /// All legal moves for the side to move.
    public func legalMoves() -> [Move] {
        pseudoLegalMoves().filter { move in
            !making(move).isInCheck(sideToMove)
        }
    }

    /// Legal moves for the piece standing on `square`.
    public func legalMoves(from square: Square) -> [Move] {
        guard let piece = self[square], piece.color == sideToMove else { return [] }
        return pseudoLegalMoves(from: square, piece: piece).filter { !making($0).isInCheck(sideToMove) }
    }

    func pseudoLegalMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)
        for i in 0..<64 {
            if let piece = board[i], piece.color == sideToMove {
                moves += pseudoLegalMoves(from: Square(index: i), piece: piece)
            }
        }
        return moves
    }

    private func pseudoLegalMoves(from: Square, piece: Piece) -> [Move] {
        var moves: [Move] = []
        let us = piece.color

        func addSliding(_ directions: [(Int, Int)]) {
            for (df, dr) in directions {
                var current = from.offset(df, dr)
                while let s = current {
                    if let target = board[s.index] {
                        if target.color != us { moves.append(Move(from: from, to: s)) }
                        break
                    }
                    moves.append(Move(from: from, to: s))
                    current = s.offset(df, dr)
                }
            }
        }

        func addSteps(_ offsets: [(Int, Int)]) {
            for (df, dr) in offsets {
                if let s = from.offset(df, dr), board[s.index]?.color != us {
                    moves.append(Move(from: from, to: s))
                }
            }
        }

        switch piece.kind {
        case .pawn:
            let dir = us.pawnDirection
            let promotionRank = us == .white ? 7 : 0
            func addPawnMove(_ to: Square) {
                if to.rank == promotionRank {
                    for kind in PieceKind.promotionChoices { moves.append(Move(from: from, to: to, promotion: kind)) }
                } else {
                    moves.append(Move(from: from, to: to))
                }
            }
            if let one = from.offset(0, dir), board[one.index] == nil {
                addPawnMove(one)
                let startRank = us == .white ? 1 : 6
                if from.rank == startRank, let two = from.offset(0, 2 * dir), board[two.index] == nil {
                    moves.append(Move(from: from, to: two))
                }
            }
            for df in [-1, 1] {
                guard let target = from.offset(df, dir) else { continue }
                if let victim = board[target.index], victim.color != us {
                    addPawnMove(target)
                } else if target == enPassant {
                    moves.append(Move(from: from, to: target))
                }
            }
        case .knight:
            addSteps(Self.knightOffsets)
        case .bishop:
            addSliding(Self.bishopDirections)
        case .rook:
            addSliding(Self.rookDirections)
        case .queen:
            addSliding(Self.rookDirections + Self.bishopDirections)
        case .king:
            addSteps(Self.kingOffsets)
            addCastlingMoves(from: from, color: us, into: &moves)
        }
        return moves
    }

    private func addCastlingMoves(from: Square, color: PieceColor, into moves: inout [Move]) {
        let rank = color.homeRank
        guard from == Square(file: 4, rank: rank), !isAttacked(from, by: color.opponent) else { return }

        func empty(_ files: [Int]) -> Bool { files.allSatisfy { board[rank * 8 + $0] == nil } }
        func safe(_ files: [Int]) -> Bool {
            files.allSatisfy { !isAttacked(Square(file: $0, rank: rank)!, by: color.opponent) }
        }
        let rook = Piece(.rook, color)

        if castling.contains(.kingside(color)), board[rank * 8 + 7] == rook, empty([5, 6]), safe([5, 6]) {
            moves.append(Move(from: from, to: Square(file: 6, rank: rank)!))
        }
        if castling.contains(.queenside(color)), board[rank * 8] == rook, empty([1, 2, 3]), safe([2, 3]) {
            moves.append(Move(from: from, to: Square(file: 2, rank: rank)!))
        }
    }

    // MARK: - Making moves

    /// Returns the position after `move`. The move is assumed to be (pseudo-)legal.
    public func making(_ move: Move) -> Position {
        var next = self
        next.apply(move)
        return next
    }

    /// The piece captured by `move`, including en passant.
    public func capturedPiece(by move: Move) -> Piece? {
        if let victim = self[move.to] { return victim }
        if self[move.from]?.kind == .pawn, move.to == enPassant, move.from.file != move.to.file {
            return Piece(.pawn, sideToMove.opponent)
        }
        return nil
    }

    public func isCastling(_ move: Move) -> Bool {
        self[move.from]?.kind == .king && abs(move.to.file - move.from.file) == 2
    }

    private mutating func apply(_ move: Move) {
        guard let piece = board[move.from.index] else { return }
        let us = piece.color
        let isCapture = capturedPiece(by: move) != nil

        // En passant: the captured pawn is beside the moving pawn, not on the target square.
        if piece.kind == .pawn, move.to == enPassant, board[move.to.index] == nil, move.from.file != move.to.file {
            board[move.to.offset(0, -us.pawnDirection)!.index] = nil
        }

        // Castling: also move the rook.
        if piece.kind == .king, abs(move.to.file - move.from.file) == 2 {
            let rank = move.from.rank
            let (rookFrom, rookTo) = move.to.file == 6 ? (7, 5) : (0, 3)
            board[rank * 8 + rookTo] = board[rank * 8 + rookFrom]
            board[rank * 8 + rookFrom] = nil
        }

        board[move.to.index] = move.promotion.map { Piece($0, us) } ?? piece
        board[move.from.index] = nil

        // Moving a king or rook, or capturing a rook on its home square, removes castling rights.
        for square in [move.from, move.to] {
            switch (square.file, square.rank) {
            case (4, 0): castling.subtract([.whiteKingside, .whiteQueenside])
            case (4, 7): castling.subtract([.blackKingside, .blackQueenside])
            case (0, 0): castling.remove(.whiteQueenside)
            case (7, 0): castling.remove(.whiteKingside)
            case (0, 7): castling.remove(.blackQueenside)
            case (7, 7): castling.remove(.blackKingside)
            default: break
            }
        }

        enPassant = piece.kind == .pawn && abs(move.to.rank - move.from.rank) == 2
            ? move.from.offset(0, us.pawnDirection)
            : nil

        halfmoveClock = piece.kind == .pawn || isCapture ? 0 : halfmoveClock + 1
        if us == .black { fullmoveNumber += 1 }
        sideToMove = us.opponent
    }

    // MARK: - Draw detection helpers

    /// True when neither side can possibly deliver mate (K v K, K+minor v K, K+B v K+B same colour).
    public var hasInsufficientMaterial: Bool {
        var minors: [(Piece, Square)] = []
        for square in Square.all {
            guard let piece = self[square], piece.kind != .king else { continue }
            switch piece.kind {
            case .pawn, .rook, .queen: return false
            default: minors.append((piece, square))
            }
        }
        if minors.count <= 1 { return true }
        // Only bishops, all on the same square colour.
        if minors.allSatisfy({ $0.0.kind == .bishop }) {
            let shades = Set(minors.map { $0.1.isLight })
            return shades.count == 1
        }
        return false
    }

    /// The parts of the position that count for threefold repetition.
    public struct RepetitionKey: Hashable, Sendable {
        let board: [Piece?]
        let sideToMove: PieceColor
        let castling: CastlingRights
        let enPassant: Square?
    }

    public var repetitionKey: RepetitionKey {
        // Only count the en-passant square when a capture is actually possible.
        let ep = enPassant.flatMap { ep in
            legalMoves().contains { $0.to == ep && self[$0.from]?.kind == .pawn } ? ep : nil
        }
        return RepetitionKey(board: board, sideToMove: sideToMove, castling: castling, enPassant: ep)
    }
}
