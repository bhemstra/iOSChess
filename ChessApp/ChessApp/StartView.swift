import ChessKit
import SwiftUI

struct GameSetup: Hashable {
    let opponent: Opponent
    let humanColor: PieceColor
    var startPosition: Position = .start
}

struct StartView: View {
    @State private var level: Engine.Level = .medium
    @State private var humanColor: PieceColor = .white
    @State private var path: [GameSetup] = []

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    VStack(spacing: 4) {
                        Text("♞\u{FE0E}").font(.system(size: 72))
                        Text("Schaak").font(.largeTitle.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Tegen de computer") {
                    Picker("Niveau", selection: $level) {
                        ForEach(Engine.Level.allCases) { Text($0.dutchName.capitalized).tag($0) }
                    }
                    Picker("Jij speelt met", selection: $humanColor) {
                        Text("Wit").tag(PieceColor.white)
                        Text("Zwart").tag(PieceColor.black)
                    }
                    Button("Start partij") {
                        path.append(GameSetup(opponent: .computer(level), humanColor: humanColor))
                    }
                    .bold()
                }

                Section("Twee spelers op één toestel") {
                    Button("Start partij") {
                        path.append(GameSetup(opponent: .human, humanColor: .white))
                    }
                    .bold()
                }
            }
            .navigationDestination(for: GameSetup.self) { setup in
                GameView(opponent: setup.opponent, humanColor: setup.humanColor, startPosition: setup.startPosition)
            }
        }
        #if DEBUG
        .onAppear {
            // Debug aids for testing in the Simulator:
            //   -startAsBlack        opens a game against the computer, playing black
            //   -debugFEN "<fen>"    opens a two-player game from that position
            guard path.isEmpty else { return }
            if ProcessInfo.processInfo.arguments.contains("-startAsBlack") {
                path.append(GameSetup(opponent: .computer(.medium), humanColor: .black))
            } else if let fen = UserDefaults.standard.string(forKey: "debugFEN"), let position = Position(fen: fen) {
                path.append(GameSetup(opponent: .human, humanColor: .white, startPosition: position))
            }
        }
        #endif
    }
}

#Preview {
    StartView()
}
