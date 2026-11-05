import ChessKit
import SwiftUI

/// The 8×8 board. Scales to whatever square space it gets; supports tap-to-move
/// and drag-and-drop with one gesture.
struct BoardView: View {
    let model: GameModel

    @State private var dragFrom: Square?
    @State private var dragOffset: CGSize = .zero

    private let lightColor = Color(red: 0.93, green: 0.87, blue: 0.75)
    private let darkColor = Color(red: 0.71, green: 0.53, blue: 0.39)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 8

            ZStack(alignment: .topLeading) {
                ForEach(Square.all) { square in
                    squareView(square, cell: cell)
                        .frame(width: cell, height: cell)
                        .position(center(of: square, cell: cell))
                }

                ForEach(model.pieces) { item in
                    let isDragged = item.square == dragFrom
                    PieceView(piece: item.piece, size: cell)
                        .scaleEffect(isDragged ? 1.25 : 1)
                        .position(center(of: item.square, cell: cell))
                        .offset(isDragged ? dragOffset : .zero)
                        .zIndex(isDragged ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(boardGesture(cell: cell))
            .animation(.snappy(duration: 0.25), value: model.game.history.count)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: model.game.history.count)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Squares

    @ViewBuilder
    private func squareView(_ square: Square, cell: CGFloat) -> some View {
        let isTarget = model.targets.contains(square)
        let lastMove = model.game.lastMove
        ZStack {
            Rectangle().fill(square.isLight ? lightColor : darkColor)

            if square == lastMove?.from || square == lastMove?.to {
                Rectangle().fill(Color.yellow.opacity(0.35))
            }
            if square == model.selected {
                Rectangle().fill(Color.green.opacity(0.4))
            }
            if square == model.checkedKing {
                RadialGradient(colors: [.red, .red.opacity(0)], center: .center,
                               startRadius: 0, endRadius: cell * 0.7)
            }
            if isTarget {
                if model.position[square] != nil {
                    Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: cell * 0.08)
                } else {
                    Circle().fill(Color.black.opacity(0.25)).frame(width: cell * 0.3)
                }
            }
            coordinateLabels(for: square, cell: cell)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel(for: square))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tap(square) }
    }

    @ViewBuilder
    private func coordinateLabels(for square: Square, cell: CGFloat) -> some View {
        let (col, row) = cellPosition(of: square)
        let color = square.isLight ? darkColor : lightColor
        if row == 7 {
            Text(String(square.name.first!))
                .font(.system(size: cell * 0.2, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(cell * 0.05)
        }
        if col == 0 {
            Text(String(square.rank + 1))
                .font(.system(size: cell * 0.2, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(cell * 0.05)
        }
    }

    private func accessibilityLabel(for square: Square) -> String {
        guard let piece = model.position[square] else { return square.name }
        let colour = piece.color == .white ? "witte" : "zwarte"
        return "\(square.name), \(colour) \(piece.kind.dutchName.lowercased())"
    }

    // MARK: - Geometry

    /// Screen column/row (0 = left/top) for a square, honouring board flip.
    private func cellPosition(of square: Square) -> (col: Int, row: Int) {
        model.isFlipped ? (7 - square.file, square.rank) : (square.file, 7 - square.rank)
    }

    private func center(of square: Square, cell: CGFloat) -> CGPoint {
        let (col, row) = cellPosition(of: square)
        return CGPoint(x: (CGFloat(col) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
    }

    private func square(at point: CGPoint, cell: CGFloat) -> Square? {
        guard point.x >= 0, point.y >= 0 else { return nil }
        let col = Int(point.x / cell)
        let row = Int(point.y / cell)
        guard col < 8, row < 8 else { return nil }
        return model.isFlipped ? Square(file: 7 - col, rank: row) : Square(file: col, rank: 7 - row)
    }

    // MARK: - Gesture

    private func boardGesture(cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if dragFrom == nil, distance > cell * 0.15,
                   let start = square(at: value.startLocation, cell: cell),
                   model.beginDrag(at: start) {
                    dragFrom = start
                }
                if dragFrom != nil { dragOffset = value.translation }
            }
            .onEnded { value in
                if let from = dragFrom {
                    let to = square(at: value.location, cell: cell)
                    // Drop without animation so the piece doesn't fly back first.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        dragFrom = nil
                        dragOffset = .zero
                        model.endDrag(from: from, to: to)
                    }
                } else if let tapped = square(at: value.location, cell: cell) {
                    model.tap(tapped)
                }
            }
    }
}

struct PieceView: View {
    let piece: Piece
    let size: CGFloat

    var body: some View {
        // The filled glyph is used for both colours; white pieces get the outline glyph on top.
        // U+FE0E forces text (not emoji) presentation.
        ZStack {
            Text(glyph(filled: true))
                .foregroundStyle(piece.color == .white ? Color.white : Color.black)
            if piece.color == .white {
                Text(glyph(filled: false)).foregroundStyle(Color.black)
            }
        }
        .font(.system(size: size * 0.78))
        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        .frame(width: size, height: size)
    }

    private func glyph(filled: Bool) -> String {
        let outline: [PieceKind: String] = [.king: "♔", .queen: "♕", .rook: "♖", .bishop: "♗", .knight: "♘", .pawn: "♙"]
        let solid: [PieceKind: String] = [.king: "♚", .queen: "♛", .rook: "♜", .bishop: "♝", .knight: "♞", .pawn: "♟"]
        return (filled ? solid : outline)[piece.kind]! + "\u{FE0E}"
    }
}
