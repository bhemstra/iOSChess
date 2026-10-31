//
//  StartScreen.swift
//  MammothChess
//
//  Created by Zebra on 2016-09-01.
//  Copyright © 2016 Mammoth Interactive. All rights reserved.
//

import UIKit

class StartScreen: UIViewController {
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        let destVC = segue.destination as! ViewController
        
        if segue.identifier == "singleplayer"{
            destVC.isAgainstAI = true
        }
        
        if segue.identifier == "multiplayer"{
            destVC.isAgainstAI = false
        }
    }
    
    @IBAction func unwind(segue: UIStoryboardSegue){
        
    }
}
