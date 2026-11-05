/// Static evaluation: PeSTO's tapered piece-square tables (middlegame and endgame
/// values blended by game phase), plus a bishop-pair bonus and a "mop-up" term that
/// helps convert won endgames by driving the lone king to the edge.
enum Evaluation {
    static func pieceValue(_ kind: PieceKind) -> Int {
        switch kind {
        case .pawn: 100
        case .knight: 320
        case .bishop: 330
        case .rook: 500
        case .queen: 950
        case .king: 20_000
        }
    }

    /// Centipawns from the point of view of the side to move.
    static func evaluate(_ position: Position) -> Int {
        let t = Tables.shared
        var mg = [0, 0], eg = [0, 0]
        var phase = 0
        var bishops = [0, 0]
        var nonPawnMaterial = [0, 0]
        var pawns = [0, 0]

        let cells = position.cells
        for sq in 0..<64 {
            let c = cells[sq]
            if c == 0 { continue }
            let side = c & Code.black == 0 ? 0 : 1
            let kind = Int(c & 7) - 1
            // Tables are laid out with a8 first, from white's point of view.
            let index = side == 0 ? sq ^ 56 : sq
            mg[side] += t.mg[kind][index]
            eg[side] += t.eg[kind][index]
            phase += phaseIncrement[kind]
            switch kind {
            case 0: pawns[side] += 1
            case 2: bishops[side] += 1; nonPawnMaterial[side] += 330
            case 1: nonPawnMaterial[side] += 320
            case 3: nonPawnMaterial[side] += 500
            case 4: nonPawnMaterial[side] += 950
            default: break
            }
        }

        for side in 0..<2 where bishops[side] >= 2 {
            mg[side] += 30
            eg[side] += 50
        }

        let mgPhase = min(phase, 24)
        var score = ((mg[0] - mg[1]) * mgPhase + (eg[0] - eg[1]) * (24 - mgPhase)) / 24

        // Mop-up: with a clear material edge and no enemy pawns, push the enemy king
        // to the edge and bring our king closer.
        for side in 0..<2 {
            let other = 1 - side
            if pawns[other] == 0, nonPawnMaterial[side] - nonPawnMaterial[other] >= 400 {
                let strongKing = side == 0 ? position.kingIndex.white : position.kingIndex.black
                let weakKing = side == 0 ? position.kingIndex.black : position.kingIndex.white
                let wf = weakKing % 8, wr = weakKing / 8
                let centerDistance = max(3 - wf, wf - 4) + max(3 - wr, wr - 4)
                let kingDistance = abs(wf - strongKing % 8) + abs(wr - strongKing / 8)
                let bonus = 10 * centerDistance + 4 * (14 - kingDistance)
                score += side == 0 ? bonus : -bonus
            }
        }

        let tempo = 10
        return (position.sideToMove == .white ? score : -score) + tempo
    }

    private static let phaseIncrement = [0, 1, 1, 2, 4, 0]
}

extension Tables {
    /// PeSTO tables including material, indexed [kind - 1][square], a8 = 0.
    var mg: [[Int]] { PeSTO.mg }
    var eg: [[Int]] { PeSTO.eg }
}

private enum PeSTO {
    static let mgValue = [82, 337, 365, 477, 1025, 0]
    static let egValue = [94, 281, 297, 512, 936, 0]

    static let mg: [[Int]] = zip(mgValue, [mgPawn, mgKnight, mgBishop, mgRook, mgQueen, mgKing]).map { value, table in
        table.map { $0 + value }
    }
    static let eg: [[Int]] = zip(egValue, [egPawn, egKnight, egBishop, egRook, egQueen, egKing]).map { value, table in
        table.map { $0 + value }
    }

    static let mgPawn = [
          0,   0,   0,   0,   0,   0,  0,   0,
         98, 134,  61,  95,  68, 126, 34, -11,
         -6,   7,  26,  31,  65,  56, 25, -20,
        -14,  13,   6,  21,  23,  12, 17, -23,
        -27,  -2,  -5,  12,  17,   6, 10, -25,
        -26,  -4,  -4, -10,   3,   3, 33, -12,
        -35,  -1, -20, -23, -15,  24, 38, -22,
          0,   0,   0,   0,   0,   0,  0,   0,
    ]
    static let egPawn = [
          0,   0,   0,   0,   0,   0,   0,   0,
        178, 173, 158, 134, 147, 132, 165, 187,
         94, 100,  85,  67,  56,  53,  82,  84,
         32,  24,  13,   5,  -2,   4,  17,  17,
         13,   9,  -3,  -7,  -7,  -8,   3,  -1,
          4,   7,  -6,   1,   0,  -5,  -1,  -8,
         13,   8,   8,  10,  13,   0,   2,  -7,
          0,   0,   0,   0,   0,   0,   0,   0,
    ]
    static let mgKnight = [
        -167, -89, -34, -49,  61, -97, -15, -107,
         -73, -41,  72,  36,  23,  62,   7,  -17,
         -47,  60,  37,  65,  84, 129,  73,   44,
          -9,  17,  19,  53,  37,  69,  18,   22,
         -13,   4,  16,  13,  28,  19,  21,   -8,
         -23,  -9,  12,  10,  19,  17,  25,  -16,
         -29, -53, -12,  -3,  -1,  18, -14,  -19,
        -105, -21, -58, -33, -17, -28, -19,  -23,
    ]
    static let egKnight = [
        -58, -38, -13, -28, -31, -27, -63, -99,
        -25,  -8, -25,  -2,  -9, -25, -24, -52,
        -24, -20,  10,   9,  -1,  -9, -19, -41,
        -17,   3,  22,  22,  22,  11,   8, -18,
        -18,  -6,  16,  25,  16,  17,   4, -18,
        -23,  -3,  -1,  15,  10,  -3, -20, -22,
        -42, -20, -10,  -5,  -2, -20, -23, -44,
        -29, -51, -23, -15, -22, -18, -50, -64,
    ]
    static let mgBishop = [
        -29,   4, -82, -37, -25, -42,   7,  -8,
        -26,  16, -18, -13,  30,  59,  18, -47,
        -16,  37,  43,  40,  35,  50,  37,  -2,
         -4,   5,  19,  50,  37,  37,   7,  -2,
         -6,  13,  13,  26,  34,  12,  10,   4,
          0,  15,  15,  15,  14,  27,  18,  10,
          4,  15,  16,   0,   7,  21,  33,   1,
        -33,  -3, -14, -21, -13, -12, -39, -21,
    ]
    static let egBishop = [
        -14, -21, -11,  -8,  -7,  -9, -17, -24,
         -8,  -4,   7, -12,  -3, -13,  -4, -14,
          2,  -8,   0,  -1,  -2,   6,   0,   4,
         -3,   9,  12,   9,  14,  10,   3,   2,
         -6,   3,  13,  19,   7,  10,  -3,  -9,
        -12,  -3,   8,  10,  13,   3,  -7, -15,
        -14, -18,  -7,  -1,   4,  -9, -15, -27,
        -23,  -9, -23,  -5,  -9, -16,  -5, -17,
    ]
    static let mgRook = [
         32,  42,  32,  51,  63,   9,  31,  43,
         27,  32,  58,  62,  80,  67,  26,  44,
         -5,  19,  26,  36,  17,  45,  61,  16,
        -24, -11,   7,  26,  24,  35,  -8, -20,
        -36, -26, -12,  -1,   9,  -7,   6, -23,
        -45, -25, -16, -17,   3,   0,  -5, -33,
        -44, -16, -20,  -9,  -1,  11,  -6, -71,
        -19, -13,   1,  17,  16,   7, -37, -26,
    ]
    static let egRook = [
        13,  10,  18,  15,  12,  12,   8,   5,
        11,  13,  13,  11,  -3,   3,   8,   3,
         7,   7,   7,   5,   4,  -3,  -5,  -3,
         4,   3,  13,   1,   2,   1,  -1,   2,
         3,   5,   8,   4,  -5,  -6,  -8, -11,
        -4,   0,  -5,  -1,  -7, -12,  -8, -16,
        -6,  -6,   0,   2,  -9,  -9, -11,  -3,
        -9,   2,   3,  -1,  -5, -13,   4, -20,
    ]
    static let mgQueen = [
        -28,   0,  29,  12,  59,  44,  43,  45,
        -24, -39,  -5,   1, -16,  57,  28,  54,
        -13, -17,   7,   8,  29,  56,  47,  57,
        -27, -27, -16, -16,  -1,  17,  -2,   1,
         -9, -26,  -9, -10,  -2,  -4,   3,  -3,
        -14,   2, -11,  -2,  -5,   2,  14,   5,
        -35,  -8,  11,   2,   8,  15,  -3,   1,
         -1, -18,  -9,  10, -15, -25, -31, -50,
    ]
    static let egQueen = [
         -9,  22,  22,  27,  27,  19,  10,  20,
        -17,  20,  32,  41,  58,  25,  30,   0,
        -20,   6,   9,  49,  47,  35,  19,   9,
          3,  22,  24,  45,  57,  40,  57,  36,
        -18,  28,  19,  47,  31,  34,  39,  23,
        -16, -27,  15,   6,   9,  17,  10,   5,
        -22, -23, -30, -16, -16, -23, -36, -32,
        -33, -28, -22, -43,  -5, -32, -20, -41,
    ]
    static let mgKing = [
        -65,  23,  16, -15, -56, -34,   2,  13,
         29,  -1, -20,  -7,  -8,  -4, -38, -29,
         -9,  24,   2, -16, -20,   6,  22, -22,
        -17, -20, -12, -27, -30, -25, -14, -36,
        -49,  -1, -27, -39, -46, -44, -33, -51,
        -14, -14, -22, -46, -44, -30, -15, -27,
          1,   7,  -8, -64, -43, -16,   9,   8,
        -15,  36,  12, -54,   8, -28,  24,  14,
    ]
    static let egKing = [
        -74, -35, -18, -18, -11,  15,   4, -17,
        -12,  17,  14,  17,  17,  38,  23,  11,
         10,  17,  23,  15,  20,  45,  44,  13,
         -8,  22,  24,  27,  26,  33,  26,   3,
        -18,  -4,  21,  24,  27,  23,   9, -11,
        -19,  -3,  11,  21,  23,  16,   7,  -9,
        -27, -11,   4,  13,  14,   4,  -5, -17,
        -53, -34, -21, -11, -28, -14, -24, -43,
    ]
}
