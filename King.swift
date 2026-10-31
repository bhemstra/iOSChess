//
//  King.swift
//  MammothChess
//
//  Created by Zebra on 2016-08-27.
//  Copyright © 2016 Mammoth Interactive. All rights reserved.
//

import UIKit

class King: UIChessPiece {
    
    init(frame: CGRect, color: UIColor, vc: ViewController) {
        super.init(frame: frame)
        
        if color == #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1){
            self.text = "♚"
        }
        else{
            self.text = "♔"
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
        
        let differenceInRows = abs(dest.row - source.row)
        let differenceInCols = abs(dest.col - source.col)
        
        if case 0...1 = differenceInRows{
            if case 0...1 = differenceInCols{
                return true
            }
        }
        
        return false
    }
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }

}
