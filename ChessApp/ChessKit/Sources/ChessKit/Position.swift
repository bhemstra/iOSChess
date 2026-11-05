/// A complete chess position: piece placement, side to move, castling rights,
/// en-passant square and move clocks.
///
/// The board is stored as a `SIMD64<Int8>` so a position is a small, fixed-size
/// value with no heap storage. "Trying" a move is simply making it on a copy, which
/// keeps the engine fast without any undo bookkeeping.
public struct Position: Sendable, Hashable {
    /// Piece codes per square: 0 = empty, 1…6 = white P N B R Q K, 9…14 = black.
    @usableFromInline var cells: SIMD64<Int8>
    public private(set) var sideToMove: PieceColor
    public private(set) var castling: CastlingRights
    /// The square a pawn may capture onto en passant (set right after a double push).
    public private(set) var enPassant: Square?
    public private(set) var halfmoveClock: Int
    public private(set) var fullmoveNumber: Int
    /// Zobrist hash of placement, side to move, castling rights and en-passant file.
    public private(set) var hash: UInt64 = 0
    var kingIndex: (white: Int, black: Int) = (-1, -1)

    public static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    public static let start = Position(fen: startFEN)!

    public subscript(square: Square) -> Piece? { Piece(code: cells[square.index]) }

    // MARK: - Hashable (the cached king squares are derived data)

    public static func == (lhs: Position, rhs: Position) -> Bool {
        lhs.cells == rhs.cells && lhs.sideToMove == rhs.sideToMove && lhs.castling == rhs.castling
            && lhs.enPassant == rhs.enPassant && lhs.halfmoveClock == rhs.halfmoveClock
            && lhs.fullmoveNumber == rhs.fullmoveNumber
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hash)
        hasher.combine(halfmoveClock)
        hasher.combine(fullmoveNumber)
    }

    // MARK: - FEN

    public init?(fen: String) {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2 else { return nil }

        var cells = SIMD64<Int8>(repeating: 0)
        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return nil }
        for (i, rankString) in ranks.enumerated() {
            let rank = 7 - i
            var file = 0
            for c in rankString {
                if let n = c.wholeNumberValue {
                    file += n
                } else {
                    guard let piece = Piece(fenCharacter: c), file < 8 else { return nil }
                    cells[rank * 8 + file] = piece.code
                    file += 1
                }
            }
            guard file == 8 else { return nil }
        }
        self.cells = cells

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

        var white = -1, black = -1
        for i in 0..<64 {
            if cells[i] == Code.king { white = i }
            if cells[i] == Code.king | Code.black { black = i }
        }
        guard white >= 0, black >= 0 else { return nil }
        kingIndex = (white, black)
        hash = computeHash()
    }

    public var fen: String {
        var rows: [String] = []
        for rank in (0..<8).reversed() {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = Piece(code: cells[rank * 8 + file]) {
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

    public func kingSquare(of color: PieceColor) -> Square? {
        let i = color == .white ? kingIndex.white : kingIndex.black
        return i >= 0 ? Square(index: i) : nil
    }

    /// Whether `square` is attacked by any piece of `attacker`.
    public func isAttacked(_ square: Square, by attacker: PieceColor) -> Bool {
        isAttacked(square.index, by: attacker)
    }

    @inline(__always)
    func isAttacked(_ sq: Int, by attacker: PieceColor) -> Bool {
        let colorBit: Int8 = attacker == .white ? 0 : Code.black
        let tables = Tables.shared

        // Pawns attack diagonally forward, so look one rank "behind" the square.
        let pawn = Code.pawn | colorBit
        for target in (attacker == .white ? tables.blackPawnAttacks[sq] : tables.whitePawnAttacks[sq])
        where cells[target] == pawn { return true }

        let knight = Code.knight | colorBit
        for target in tables.knightTargets[sq] where cells[target] == knight { return true }

        let king = Code.king | colorBit
        for target in tables.kingTargets[sq] where cells[target] == king { return true }

        let rook = Code.rook | colorBit, bishop = Code.bishop | colorBit, queen = Code.queen | colorBit
        for dir in 0..<8 {
            let straight = dir < 4
            for target in tables.rays[dir][sq] {
                let c = cells[target]
                if c == 0 { continue }
                if c == queen || c == (straight ? rook : bishop) { return true }
                break
            }
        }
        return false
    }

    public func isInCheck(_ color: PieceColor) -> Bool {
        let king = color == .white ? kingIndex.white : kingIndex.black
        return king >= 0 && isAttacked(king, by: color.opponent)
    }

    /// Whether the side to move is in check.
    public var isCheck: Bool { isInCheck(sideToMove) }

    // MARK: - Move generation

    /// All legal moves for the side to move.
    public func legalMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)
        generateMoves(into: &moves)
        let us = sideToMove
        return moves.filter { !making($0).isInCheck(us) }
    }

    /// Legal moves for the piece standing on `square`.
    public func legalMoves(from square: Square) -> [Move] {
        guard let piece = self[square], piece.color == sideToMove else { return [] }
        return legalMoves().filter { $0.from == square }
    }

    /// Pseudo-legal moves (may leave the own king in check). With `capturesOnly`,
    /// only captures and promotions are generated (for quiescence search).
    func generateMoves(into moves: inout [Move], capturesOnly: Bool = false) {
        let us = sideToMove
        let ownBit: Int8 = us == .white ? 0 : Code.black
        let tables = Tables.shared

        @inline(__always) func isEnemy(_ c: Int8) -> Bool { c != 0 && (c & Code.black) != ownBit }

        for from in 0..<64 {
            let c = cells[from]
            guard c != 0, (c & Code.black) == ownBit else { continue }
            let fromSq = Square(index: from)

            switch c & 7 {
            case Code.pawn:
                let dir = us == .white ? 8 : -8
                let rank = from >> 3
                let promotionRank = us == .white ? 6 : 1
                let startRank = us == .white ? 1 : 6
                let one = from + dir
                if cells[one] == 0 {
                    if rank == promotionRank {
                        for kind in PieceKind.promotionChoices {
                            moves.append(Move(from: fromSq, to: Square(index: one), promotion: kind))
                        }
                    } else if !capturesOnly {
                        moves.append(Move(from: fromSq, to: Square(index: one)))
                        if rank == startRank, cells[one + dir] == 0 {
                            moves.append(Move(from: fromSq, to: Square(index: one + dir)))
                        }
                    }
                }
                for target in (us == .white ? tables.whitePawnAttacks[from] : tables.blackPawnAttacks[from]) {
                    if isEnemy(cells[target]) {
                        if rank == promotionRank {
                            for kind in PieceKind.promotionChoices {
                                moves.append(Move(from: fromSq, to: Square(index: target), promotion: kind))
                            }
                        } else {
                            moves.append(Move(from: fromSq, to: Square(index: target)))
                        }
                    } else if target == enPassant?.index {
                        moves.append(Move(from: fromSq, to: Square(index: target)))
                    }
                }
            case Code.knight:
                for target in tables.knightTargets[from] {
                    let t = cells[target]
                    if isEnemy(t) || (t == 0 && !capturesOnly) {
                        moves.append(Move(from: fromSq, to: Square(index: target)))
                    }
                }
            case Code.king:
                for target in tables.kingTargets[from] {
                    let t = cells[target]
                    if isEnemy(t) || (t == 0 && !capturesOnly) {
                        moves.append(Move(from: fromSq, to: Square(index: target)))
                    }
                }
                if !capturesOnly { addCastlingMoves(from: from, into: &moves) }
            default:
                let kind = c & 7
                let dirs = kind == Code.rook ? 0..<4 : kind == Code.bishop ? 4..<8 : 0..<8
                for dir in dirs {
                    for target in tables.rays[dir][from] {
                        let t = cells[target]
                        if t == 0 {
                            if !capturesOnly { moves.append(Move(from: fromSq, to: Square(index: target))) }
                            continue
                        }
                        if isEnemy(t) { moves.append(Move(from: fromSq, to: Square(index: target))) }
                        break
                    }
                }
            }
        }
    }

    private func addCastlingMoves(from: Int, into moves: inout [Move]) {
        let color = sideToMove
        let base = color == .white ? 0 : 56
        guard from == base + 4 else { return }
        let rook = Code.rook | (color == .white ? 0 : Code.black)
        let enemy = color.opponent

        if castling.contains(.kingside(color)), cells[base + 7] == rook,
           cells[base + 5] == 0, cells[base + 6] == 0,
           !isAttacked(base + 4, by: enemy), !isAttacked(base + 5, by: enemy), !isAttacked(base + 6, by: enemy) {
            moves.append(Move(from: Square(index: from), to: Square(index: base + 6)))
        }
        if castling.contains(.queenside(color)), cells[base] == rook,
           cells[base + 1] == 0, cells[base + 2] == 0, cells[base + 3] == 0,
           !isAttacked(base + 4, by: enemy), !isAttacked(base + 3, by: enemy), !isAttacked(base + 2, by: enemy) {
            moves.append(Move(from: Square(index: from), to: Square(index: base + 2)))
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
        if isEnPassant(move) { return Piece(.pawn, sideToMove.opponent) }
        return nil
    }

    @inline(__always)
    func isEnPassant(_ move: Move) -> Bool {
        cells[move.to.index] == 0 && (cells[move.from.index] & 7) == Code.pawn
            && move.to == enPassant && move.from.file != move.to.file
    }

    public func isCastling(_ move: Move) -> Bool {
        (cells[move.from.index] & 7) == Code.king && abs(move.to.file - move.from.file) == 2
    }

    @inline(__always)
    private mutating func set(_ sq: Int, _ code: Int8) {
        let z = Zobrist.shared
        let old = cells[sq]
        if old != 0 { hash ^= z.pieces[Int(old) * 64 + sq] }
        if code != 0 { hash ^= z.pieces[Int(code) * 64 + sq] }
        cells[sq] = code
    }

    private mutating func apply(_ move: Move) {
        let from = move.from.index, to = move.to.index
        let code = cells[from]
        guard code != 0 else { return }
        let us = sideToMove
        let kind = code & 7
        let z = Zobrist.shared
        let isCapture = cells[to] != 0 || isEnPassant(move)

        if let ep = enPassant { hash ^= z.enPassant[ep.file] }
        hash ^= z.castling[Int(castling.rawValue)]

        // En passant: the captured pawn is beside the moving pawn, not on the target square.
        if isEnPassant(move) {
            set(to + (us == .white ? -8 : 8), 0)
        }

        // Castling: also move the rook.
        if kind == Code.king, abs(to - from) == 2 {
            let (rookFrom, rookTo) = to > from ? (from + 3, from + 1) : (from - 4, from - 1)
            set(rookTo, cells[rookFrom])
            set(rookFrom, 0)
        }

        let colorBit: Int8 = us == .white ? 0 : Code.black
        set(to, move.promotion.map { $0.code | colorBit } ?? code)
        set(from, 0)
        if kind == Code.king {
            if us == .white { kingIndex.white = to } else { kingIndex.black = to }
        }

        // Moving a king or rook, or capturing a rook on its home square, removes castling rights.
        castling.subtract(Self.castlingMask[from])
        castling.subtract(Self.castlingMask[to])
        hash ^= z.castling[Int(castling.rawValue)]

        enPassant = kind == Code.pawn && abs(to - from) == 16 ? Square(index: (from + to) / 2) : nil
        if let ep = enPassant { hash ^= z.enPassant[ep.file] }

        halfmoveClock = kind == Code.pawn || isCapture ? 0 : halfmoveClock + 1
        if us == .black { fullmoveNumber += 1 }
        sideToMove = us.opponent
        hash ^= z.blackToMove
    }

    /// The position with the turn passed to the opponent (for null-move pruning).
    func makingNullMove() -> Position {
        var next = self
        let z = Zobrist.shared
        if let ep = next.enPassant { next.hash ^= z.enPassant[ep.file] }
        next.enPassant = nil
        next.sideToMove = sideToMove.opponent
        next.hash ^= z.blackToMove
        return next
    }

    private static let castlingMask: [CastlingRights] = {
        var mask = [CastlingRights](repeating: [], count: 64)
        mask[4] = [.whiteKingside, .whiteQueenside]
        mask[0] = .whiteQueenside
        mask[7] = .whiteKingside
        mask[60] = [.blackKingside, .blackQueenside]
        mask[56] = .blackQueenside
        mask[63] = .blackKingside
        return mask
    }()

    private func computeHash() -> UInt64 {
        let z = Zobrist.shared
        var h: UInt64 = 0
        for sq in 0..<64 where cells[sq] != 0 { h ^= z.pieces[Int(cells[sq]) * 64 + sq] }
        if sideToMove == .black { h ^= z.blackToMove }
        h ^= z.castling[Int(castling.rawValue)]
        if let ep = enPassant { h ^= z.enPassant[ep.file] }
        return h
    }

    // MARK: - Draw detection helpers

    /// True when neither side can possibly deliver mate (K v K, K+minor v K, K+B v K+B same colour).
    public var hasInsufficientMaterial: Bool {
        var minors: [(Int8, Int)] = []
        for sq in 0..<64 {
            let kind = cells[sq] & 7
            switch kind {
            case 0, Code.king: continue
            case Code.pawn, Code.rook, Code.queen: return false
            default: minors.append((kind, sq))
            }
        }
        if minors.count <= 1 { return true }
        if minors.allSatisfy({ $0.0 == Code.bishop }) {
            return Set(minors.map { Square(index: $0.1).isLight }).count == 1
        }
        return false
    }

    /// The parts of the position that count for threefold repetition.
    public struct RepetitionKey: Hashable, Sendable {
        let cells: SIMD64<Int8>
        let sideToMove: PieceColor
        let castling: CastlingRights
        let enPassant: Square?
    }

    public var repetitionKey: RepetitionKey {
        // Only count the en-passant square when a capture is actually possible.
        let ep = enPassant.flatMap { ep in
            legalMoves().contains { $0.to == ep && isEnPassant($0) } ? ep : nil
        }
        return RepetitionKey(cells: cells, sideToMove: sideToMove, castling: castling, enPassant: ep)
    }

    /// Whether the side to move has anything besides king and pawns.
    func hasNonPawnMaterial(_ color: PieceColor) -> Bool {
        let bit: Int8 = color == .white ? 0 : Code.black
        for sq in 0..<64 {
            let c = cells[sq]
            if c != 0, c & Code.black == bit, (c & 7) != Code.pawn, (c & 7) != Code.king { return true }
        }
        return false
    }
}

// MARK: - Piece codes

enum Code {
    static let pawn: Int8 = 1, knight: Int8 = 2, bishop: Int8 = 3, rook: Int8 = 4, queen: Int8 = 5, king: Int8 = 6
    static let black: Int8 = 8
}

extension PieceKind {
    var code: Int8 {
        switch self {
        case .pawn: Code.pawn
        case .knight: Code.knight
        case .bishop: Code.bishop
        case .rook: Code.rook
        case .queen: Code.queen
        case .king: Code.king
        }
    }

    init?(code: Int8) {
        switch code {
        case Code.pawn: self = .pawn
        case Code.knight: self = .knight
        case Code.bishop: self = .bishop
        case Code.rook: self = .rook
        case Code.queen: self = .queen
        case Code.king: self = .king
        default: return nil
        }
    }
}

extension Piece {
    var code: Int8 { kind.code | (color == .black ? Code.black : 0) }

    init?(code: Int8) {
        guard code != 0, let kind = PieceKind(code: code & 7) else { return nil }
        self.init(kind, code & Code.black != 0 ? .black : .white)
    }
}

// MARK: - Precomputed tables

/// Target squares per square, computed once.
final class Tables: Sendable {
    static let shared = Tables()

    let knightTargets: [[Int]]
    let kingTargets: [[Int]]
    /// Squares a white/black pawn on a square attacks.
    let whitePawnAttacks: [[Int]]
    let blackPawnAttacks: [[Int]]
    /// rays[direction][square]: squares in that direction, nearest first.
    /// Directions 0–3 are straight (rook), 4–7 diagonal (bishop).
    let rays: [[[Int]]]

    private init() {
        func targets(_ offsets: [(Int, Int)]) -> [[Int]] {
            (0..<64).map { sq in
                offsets.compactMap { df, dr in Square(file: sq % 8 + df, rank: sq / 8 + dr)?.index }
            }
        }
        knightTargets = targets([(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)])
        kingTargets = targets([(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)])
        whitePawnAttacks = targets([(-1, 1), (1, 1)])
        blackPawnAttacks = targets([(-1, -1), (1, -1)])
        let directions = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        rays = directions.map { df, dr in
            (0..<64).map { sq in
                var result: [Int] = []
                var f = sq % 8 + df, r = sq / 8 + dr
                while (0..<8).contains(f), (0..<8).contains(r) {
                    result.append(r * 8 + f)
                    f += df
                    r += dr
                }
                return result
            }
        }
    }
}

/// Random keys for Zobrist hashing (fixed seed, so hashes are reproducible).
final class Zobrist: Sendable {
    static let shared = Zobrist()

    let pieces: [UInt64]      // [code * 64 + square], codes 0…15
    let blackToMove: UInt64
    let castling: [UInt64]    // [rights.rawValue], 16 entries
    let enPassant: [UInt64]   // [file]

    private init() {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            // SplitMix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        pieces = (0..<(16 * 64)).map { _ in next() }
        blackToMove = next()
        castling = [0] + (1..<16).map { _ in next() }
        enPassant = (0..<8).map { _ in next() }
    }
}
