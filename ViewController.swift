//
//  ViewController.swift
//  MammothChess
//
//  Created by Zebra on 2016-08-26.
//  Copyright © 2016 Mammoth Interactive. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet var lblDisplayTurnOUTLET: UILabel!
    @IBOutlet var panOUTLET: UIPanGestureRecognizer!
    @IBOutlet var lblDisplayCheckOUTLET: UILabel!
    var pieceDragged: UIChessPiece!
    var sourceOrigin: CGPoint!
    var destOrigin: CGPoint!
    static var SPACE_FROM_LEFT_EDGE: Int = 8
    static var SPACE_FROM_TOP_EDGE: Int = 132
    static var TILE_SIZE: Int = 38
    var myChessGame: ChessGame!
    var chessPieces: [UIChessPiece]!
    var isAgainstAI: Bool!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        chessPieces = []
        myChessGame = ChessGame.init(viewController: self)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        pieceDragged = touches.first!.view as? UIChessPiece
     
        if pieceDragged != nil{
            sourceOrigin = pieceDragged.frame.origin
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        if pieceDragged != nil{
            drag(piece: pieceDragged, usingGestureRecognizer: panOUTLET)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if pieceDragged != nil{
            
            let touchLocation = touches.first!.location(in: view)
            
            var x = Int(touchLocation.x)
            var y = Int(touchLocation.y)
            
            x -= ViewController.SPACE_FROM_LEFT_EDGE
            y -= ViewController.SPACE_FROM_TOP_EDGE
            
            x = (x / ViewController.TILE_SIZE) * ViewController.TILE_SIZE
            y = (y / ViewController.TILE_SIZE) * ViewController.TILE_SIZE
            
            x += ViewController.SPACE_FROM_LEFT_EDGE
            y += ViewController.SPACE_FROM_TOP_EDGE
            
            destOrigin = CGPoint(x: x, y: y)
            
            let sourceIndex = ChessBoard.indexOf(origin: sourceOrigin)
            let destIndex = ChessBoard.indexOf(origin: destOrigin)
            
            if myChessGame.isMoveValid(piece: pieceDragged, fromIndex: sourceIndex, toIndex: destIndex){
                
                myChessGame.move(piece: pieceDragged, fromIndex: sourceIndex, toIndex: destIndex, toOrigin: destOrigin)
                
                //check if game's over
                if myChessGame.isGameOver(){
                    displayWinner()
                    return
                }
                
                if shouldPromotePawn(){
                    promptForPawnPromotion()
                }
                else{
                    resumeGame()
                }
            }
            else{
                pieceDragged.frame.origin = sourceOrigin
            }
        }
    }
    
    func resumeGame(){
        //display checks, if any
        displayCheck()
        
        //change the turn
        myChessGame.nextTurn()
        
        //display turn on screen
        updateTurnOnScreen()
        
        //make AI move, if necessary
        if isAgainstAI == true && !myChessGame.isWhiteTurn{
            
            myChessGame.makeAIMove()
            print("AI: ---------------")
            
            if myChessGame.isGameOver(){
                displayWinner()
                return
            }
            
            if shouldPromotePawn(){
                promote(pawn: myChessGame.getPawnToBePromoted()!, into: "Queen")
            }
            
            displayCheck()
            
            myChessGame.nextTurn()
            
            updateTurnOnScreen()
        }
    }
    
    func promote(pawn pawnToBePromoted: Pawn, into pieceName: String){
        
        let pawnColor = pawnToBePromoted.color
        let pawnFrame = pawnToBePromoted.frame
        let pawnIndex = ChessBoard.indexOf(origin: pawnToBePromoted.frame.origin)
        
        myChessGame.theChessBoard.remove(piece: pawnToBePromoted)
        
        switch pieceName {
        case "Queen":
            myChessGame.theChessBoard.board[pawnIndex.row][pawnIndex.col] = Queen(frame: pawnFrame, color: pawnColor, vc: self)
            case "Bishop":
            myChessGame.theChessBoard.board[pawnIndex.row][pawnIndex.col] = Bishop(frame: pawnFrame, color: pawnColor, vc: self)
            case "Knight":
            myChessGame.theChessBoard.board[pawnIndex.row][pawnIndex.col] = Knight(frame: pawnFrame, color: pawnColor, vc: self)
        case "Rook":
            myChessGame.theChessBoard.board[pawnIndex.row][pawnIndex.col] = Rook(frame: pawnFrame, color: pawnColor, vc: self)
        default:
            break
        }
    }
    
    func promptForPawnPromotion(){
        if let pawnToPromote = myChessGame.getPawnToBePromoted(){
            
            let box = UIAlertController(title: "Pawn promotion", message: "Choose piece", preferredStyle: UIAlertControllerStyle.alert)
            
            box.addAction(UIAlertAction(title: "Queen", style: UIAlertActionStyle.default, handler: {
                action in
                self.promote(pawn: pawnToPromote, into: action.title!)
                self.resumeGame()
            }))
            
            box.addAction(UIAlertAction(title: "Bishop", style: UIAlertActionStyle.default, handler: {
                action in
                self.promote(pawn: pawnToPromote, into: action.title!)
                self.resumeGame()
            }))
            
            box.addAction(UIAlertAction(title: "Knight", style: UIAlertActionStyle.default, handler: {
                action in
                self.promote(pawn: pawnToPromote, into: action.title!)
                self.resumeGame()
            }))
            
            box.addAction(UIAlertAction(title: "Rook", style: UIAlertActionStyle.default, handler: {
                action in
                self.promote(pawn: pawnToPromote, into: action.title!)
                self.resumeGame()
            }))
            
            self.present(box, animated: true, completion: nil)
        }
    }
    
    func shouldPromotePawn() -> Bool{
        return (myChessGame.getPawnToBePromoted() != nil)
    }
    
    func displayCheck(){
        let playerChecked = myChessGame.getPlayerChecked()
        
        if playerChecked != nil{
            lblDisplayCheckOUTLET.text = playerChecked! + " is in check!"
        }
        else{
            lblDisplayCheckOUTLET.text = nil
        }
    }
    
    func displayWinner(){
        let box = UIAlertController(title: "Game Over", message: "\(myChessGame.winner!) wins", preferredStyle: UIAlertControllerStyle.alert)
        
        box.addAction(UIAlertAction(title: "Back to main menu", style: UIAlertActionStyle.default, handler: {
            action in self.performSegue(withIdentifier: "backToMainMenu", sender: self)
        }))
        
        box.addAction(UIAlertAction(title: "Rematch", style: UIAlertActionStyle.default, handler: {
            action in
            
            //clear screen, chess pieces array, and board matrix
            for chessPiece in self.chessPieces{
                self.myChessGame.theChessBoard.remove(piece: chessPiece)
            }
            
            //create new game
            self.myChessGame = ChessGame(viewController: self)
            
            //update labels with game status
            self.updateTurnOnScreen()
            self.lblDisplayCheckOUTLET.text = nil
        
        }))
        
        self.present(box, animated: true, completion: nil)
    }
    
    func updateTurnOnScreen(){
        lblDisplayTurnOUTLET.text = myChessGame.isWhiteTurn ? "White's turn" : "Black's turn"
        lblDisplayTurnOUTLET.textColor = myChessGame.isWhiteTurn ? #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1) : #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
    }
    
    func drag(piece: UIChessPiece, usingGestureRecognizer gestureRecognizer: UIPanGestureRecognizer){
        
        let translation = gestureRecognizer.translation(in: view)
        
        piece.center = CGPoint(x: translation.x + piece.center.x, y: translation.y + piece.center.y)
        
        gestureRecognizer.setTranslation(CGPoint.zero, in: view)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
}

