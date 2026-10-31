//
//  Pawn.swift
//  MammothChess
//
//  Created by Zebra on 2016-08-27.
//  Copyright © 2016 Mammoth Interactive. All rights reserved.
//

import UIKit

class Pawn: UIChessPiece {
    var triesToAdvanceBy2: Bool = false
    
    init(frame: CGRect, color: UIColor, vc: ViewController) {
        super.init(frame: frame)
        
        if color == #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1){
            self.text = "♟"
        }
        else{
            self.text = "♙"
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
        
        //check advance by 2
        if source.col == dest.col{
            if (source.row == 1 && dest.row == 3 && color == #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)) || (source.row == 6 && dest.row == 4 && color != #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)){
                triesToAdvanceBy2 = true
                return true
            }
        }
        
        triesToAdvanceBy2 = false
        
        //check advance by 1
        var moveForward = 0
        
        if color == #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1){
            moveForward = 1
        }
        else{
            moveForward = -1
        }
        
        if dest.row == source.row + moveForward{
            if (dest.col == source.col - 1) || (dest.col == source.col) || (dest.col == source.col + 1){
                return true
            }
        }
        
        return false
    }
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }
}
