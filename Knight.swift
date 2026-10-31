//
//  Knight.swift
//  MammothChess
//
//  Created by Zebra on 2016-08-27.
//  Copyright © 2016 Mammoth Interactive. All rights reserved.
//

import UIKit

class Knight: UIChessPiece {
    
    init(frame: CGRect, color: UIColor, vc: ViewController) {
        super.init(frame: frame)
        
        if color == #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1){
            self.text = "♞"
        }
        else{
            self.text = "♘"
        }
        
        self.isOpaque = false
        self.textColor = color
        self.isUserInteractionEnabled = true
        self.textAlignment = .center
        self.font = self.font.withSize(36)
        
        vc.chessPieces.append(self)
        vc.view.addSubview(self)
    }
    
    func doesMoveSeemFine(fromIndex source: BoardIndex, toIndex dest: BoardIndex) -> Bool{
    
        let validMoves = [(source.row - 1, source.col + 2), (source.row - 2, source.col + 1), (source.row - 2, source.col - 1), (source.row - 1, source.col - 2), (source.row + 1, source.col - 2), (source.row + 2, source.col - 1), (source.row + 2, source.col + 1), (source.row + 1, source.col + 2)]
        
        for (validRow, validCol) in validMoves{
            if dest.row == validRow && dest.col == validCol{
                return true
            }
        }
        
        return false
    }
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }

}
