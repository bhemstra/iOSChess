//
//  Dummy.swift
//  MammothChess
//
//  Created by Zebra on 2016-08-27.
//  Copyright © 2016 Mammoth Interactive. All rights reserved.
//

import UIKit

class Dummy: Piece {
    private var xStorage: CGFloat!
    private var yStorage: CGFloat!
    
    var x: CGFloat{
        get{
            return self.xStorage
        }
        set{
            self.xStorage = newValue
        }
    }
    
    var y: CGFloat{
        get{
            return self.yStorage
        }
        set{
            self.yStorage = newValue
        }
    }
    
    init(frame: CGRect) {
        self.xStorage = frame.origin.x
        self.yStorage = frame.origin.y
    }
    
    init() {
        
    }
}
