//
//  BoardIndex.swift
//  MammothChess
//
//  Created by Zebra on 2016-08-27.
//  Copyright © 2016 Mammoth Interactive. All rights reserved.
//

struct BoardIndex: Equatable {
    
    var row: Int
    var col: Int
    
    init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
    
    static func ==(lhs: BoardIndex, rhs: BoardIndex) -> Bool{
        return (lhs.row == rhs.row && lhs.col == rhs.col)
    }
}
