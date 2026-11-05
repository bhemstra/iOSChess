import ChessKit
import SwiftUI

struct GameView: View {
    @State private var model: GameModel
    @State private var showGameOver = false

    init(opponent: Opponent, humanColor: PieceColor, startPosition: Position = .start) {
        _model = State(initialValue: GameModel(opponent: opponent, humanColor: humanColor, startPosition: startPosition))
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let layout = landscape
                ? AnyLayout(HStackLayout(spacing: 16))
                : AnyLayout(VStackLayout(spacing: 12))

            layout {
                if !landscape { statusBar }
                BoardView(model: model)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 4)
                VStack(alignment: .leading, spacing: 12) {
                    if landscape { statusBar }
                    MoveListView(history: model.game.history)
                    if landscape { Spacer(minLength: 0) }
                }
                .frame(maxWidth: landscape ? 260 : .infinity)
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .confirmationDialog("Promoveer pion tot…", isPresented: promotionBinding, titleVisibility: .visible) {
            ForEach(PieceKind.promotionChoices, id: \.self) { kind in
                Button(kind.dutchName) { model.promote(to: kind) }
            }
            Button("Annuleren", role: .cancel) { model.cancelPromotion() }
        }
        .onChange(of: model.game.status) { _, status in
            if status.isOver { showGameOver = true }
        }
        .alert("Einde partij", isPresented: $showGameOver) {
            Button("Nieuw spel") { model.newGame() }
            Button("Bekijk bord", role: .cancel) {}
        } message: {
            Text(model.statusText)
        }
    }

    private var title: String {
        switch model.opponent {
        case .human: "2 spelers"
        case .computer: "Computer"
        }
    }

    private var opponentDetail: String? {
        if case .computer(let level) = model.opponent { return "Niveau: \(level.dutchName)" }
        return nil
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.position.sideToMove == .white ? Color.white : Color.black)
                .overlay(Circle().strokeBorder(.secondary, lineWidth: 1))
                .frame(width: 18, height: 18)
            Text(model.statusText)
                .font(.headline)
                .foregroundStyle(model.position.isCheck || model.game.status.isOver ? .red : .primary)
            Spacer()
            if model.isThinking {
                ProgressView()
            } else if let opponentDetail {
                Text(opponentDetail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .animation(nil, value: model.statusText)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.undo()
            } label: {
                Label("Zet terug", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)

            Button {
                withAnimation { model.isFlipped.toggle() }
            } label: {
                Label("Draai bord", systemImage: "arrow.up.arrow.down")
            }

            Button {
                model.newGame()
            } label: {
                Label("Nieuw spel", systemImage: "arrow.clockwise")
            }
        }
    }

    private var promotionBinding: Binding<Bool> {
        Binding(
            get: { model.pendingPromotion != nil },
            set: { if !$0, model.pendingPromotion != nil { model.cancelPromotion() } }
        )
    }
}

struct MoveListView: View {
    let history: [Game.Record]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if history.isEmpty {
                        Text("Nog geen zetten").foregroundStyle(.secondary)
                    }
                    ForEach(Array(stride(from: 0, to: history.count, by: 2)), id: \.self) { i in
                        HStack(spacing: 4) {
                            Text("\(i / 2 + 1).").foregroundStyle(.secondary)
                            Text(history[i].san)
                            if i + 1 < history.count { Text(history[i + 1].san) }
                        }
                        .id(i)
                    }
                }
                .font(.body.monospaced())
                .padding(.vertical, 8)
            }
            .onChange(of: history.count) {
                withAnimation { proxy.scrollTo(max(0, (history.count - 1) / 2 * 2), anchor: .trailing) }
            }
        }
    }
}

extension Engine.Level {
    var dutchName: String {
        switch self {
        case .easy: "makkelijk"
        case .medium: "gemiddeld"
        case .hard: "moeilijk"
        }
    }
}
