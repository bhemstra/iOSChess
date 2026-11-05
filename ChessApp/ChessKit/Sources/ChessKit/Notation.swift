extension Position {
    /// Standard algebraic notation for a legal move, e.g. "Nbd7", "exd6", "O-O", "e8=Q#".
    public func san(for move: Move) -> String {
        guard let piece = self[move.from] else { return move.uci }

        var text: String
        if isCastling(move) {
            text = move.to.file == 6 ? "O-O" : "O-O-O"
        } else {
            let isCapture = capturedPiece(by: move) != nil
            text = piece.kind.sanLetter

            if piece.kind == .pawn {
                if isCapture { text += String(move.from.name.first!) }
            } else {
                // Disambiguate when another piece of the same kind can reach the same square.
                let rivals = legalMoves().filter {
                    $0.to == move.to && $0.from != move.from && self[$0.from] == piece
                }
                if !rivals.isEmpty {
                    let sameFile = rivals.contains { $0.from.file == move.from.file }
                    let sameRank = rivals.contains { $0.from.rank == move.from.rank }
                    if !sameFile {
                        text += String(move.from.name.first!)
                    } else if !sameRank {
                        text += String(move.from.name.last!)
                    } else {
                        text += move.from.name
                    }
                }
            }
            if isCapture { text += "x" }
            text += move.to.name
            if let promotion = move.promotion { text += "=" + promotion.sanLetter }
        }

        let after = making(move)
        if after.isCheck {
            text += after.legalMoves().isEmpty ? "#" : "+"
        }
        return text
    }

    /// Finds the legal move matching a SAN string (handy for tests).
    public func move(fromSAN san: String) -> Move? {
        let cleaned = san.filter { !"+#!?".contains($0) }
        return legalMoves().first { self.san(for: $0).filter { !"+#".contains($0) } == cleaned }
    }
}
