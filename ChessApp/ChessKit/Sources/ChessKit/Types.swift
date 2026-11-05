/// The two sides in a game of chess.
public enum PieceColor: String, Sendable, Hashable, CaseIterable {
    case white, black

    public var opponent: PieceColor { self == .white ? .black : .white }

    /// The direction in which this side's pawns advance (+1 for white, -1 for black).
    var pawnDirection: Int { self == .white ? 1 : -1 }

    /// The rank (0-based) of this side's back row.
    var homeRank: Int { self == .white ? 0 : 7 }
}

public enum PieceKind: Character, Sendable, Hashable, CaseIterable {
    case pawn = "p", knight = "n", bishop = "b", rook = "r", queen = "q", king = "k"

    /// Pieces a pawn may promote to, best first.
    public static let promotionChoices: [PieceKind] = [.queen, .rook, .bishop, .knight]

    /// Letter used in standard algebraic notation (empty for pawns).
    public var sanLetter: String {
        self == .pawn ? "" : String(rawValue).uppercased()
    }
}

public struct Piece: Sendable, Hashable {
    public let kind: PieceKind
    public let color: PieceColor

    public init(_ kind: PieceKind, _ color: PieceColor) {
        self.kind = kind
        self.color = color
    }

    /// FEN character: uppercase for white, lowercase for black.
    public var fenCharacter: Character {
        let c = kind.rawValue
        return color == .white ? Character(c.uppercased()) : c
    }

    public init?(fenCharacter c: Character) {
        guard let kind = PieceKind(rawValue: Character(c.lowercased())) else { return nil }
        self.init(kind, c.isUppercase ? .white : .black)
    }
}

/// A square on the board. File 0 = a, rank 0 = 1 (white's back rank).
public struct Square: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let index: Int

    public init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        index = rank * 8 + file
    }

    public init(index: Int) {
        precondition((0..<64).contains(index), "Square index out of range")
        self.index = index
    }

    /// Parses a name such as "e4".
    public init?(_ name: String) {
        let chars = Array(name)
        guard chars.count == 2,
              let fileAscii = chars[0].asciiValue, let rankDigit = chars[1].wholeNumberValue,
              fileAscii >= 97 else { return nil }
        self.init(file: Int(fileAscii) - 97, rank: rankDigit - 1)
    }

    public var file: Int { index % 8 }
    public var rank: Int { index / 8 }

    public var name: String {
        let fileChar = Character(UnicodeScalar(UInt8(97 + file)))
        return "\(fileChar)\(rank + 1)"
    }

    public var description: String { name }

    public var isLight: Bool { (file + rank) % 2 == 1 }

    /// The square shifted by the given number of files and ranks, if still on the board.
    public func offset(_ df: Int, _ dr: Int) -> Square? {
        Square(file: file + df, rank: rank + dr)
    }

    public static func < (lhs: Square, rhs: Square) -> Bool { lhs.index < rhs.index }

    public static let all: [Square] = (0..<64).map(Square.init(index:))
}

public struct Move: Sendable, Hashable, CustomStringConvertible {
    public let from: Square
    public let to: Square
    public let promotion: PieceKind?

    public init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    /// Parses UCI notation such as "e2e4" or "e7e8q".
    public init?(uci: String) {
        let s = Array(uci)
        guard s.count == 4 || s.count == 5,
              let from = Square(String(s[0...1])),
              let to = Square(String(s[2...3])) else { return nil }
        var promotion: PieceKind?
        if s.count == 5 {
            guard let p = PieceKind(rawValue: s[4]), p != .pawn, p != .king else { return nil }
            promotion = p
        }
        self.init(from: from, to: to, promotion: promotion)
    }

    public var uci: String {
        from.name + to.name + (promotion.map { String($0.rawValue) } ?? "")
    }

    public var description: String { uci }
}

public struct CastlingRights: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let whiteKingside = CastlingRights(rawValue: 1)
    public static let whiteQueenside = CastlingRights(rawValue: 2)
    public static let blackKingside = CastlingRights(rawValue: 4)
    public static let blackQueenside = CastlingRights(rawValue: 8)
    public static let all: CastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]

    static func kingside(_ color: PieceColor) -> CastlingRights {
        color == .white ? .whiteKingside : .blackKingside
    }

    static func queenside(_ color: PieceColor) -> CastlingRights {
        color == .white ? .whiteQueenside : .blackQueenside
    }
}

extension Square: Identifiable {
    public var id: Int { index }
}
