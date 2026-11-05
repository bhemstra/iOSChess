# iOSChess

Dit projectje heb ik lang geleden via Udemy gestart. Op iOS 10 werkte het, dus was de uitdaging er een nieuwere, modernere versie van te maken die op mijn huidige iOS 27 iPhone werkt. Dat is versie 2: helemaal opnieuw opgezet in SwiftUI. De oude UIKit-code staat nog in de git-geschiedenis.

## Wat zit erin

- **Alle schaakregels**: rokade, en passant, promotie, schaakmat, pat, 50-zettenregel, drievoudige herhaling en onvoldoende materiaal.
- **Computertegenstander** in drie niveaus: makkelijk (kijkt kort vooruit, met wat toeval), gemiddeld (0,7 s per zet) en moeilijk (2,5 s per zet, ruim 10 halve zetten diep). De engine gebruikt PVS met iteratief verdiepen, een transpositietabel, null-move pruning, late-move reductions en een PeSTO-evaluatie. Hij rekent op de achtergrond, dus de app blijft reageren.
- **Twee spelers** op één toestel.
- Tik-om-te-zetten én slepen, mogelijke zetten gemarkeerd, zettenlijst in standaardnotatie, zet terugnemen, bord draaien, donkere modus, iPhone en iPad (staand en liggend).

## Opbouw

```
ChessApp/
├── ChessApp.xcodeproj    Xcode-project
├── ChessApp/             SwiftUI-app (schermen, bord, spelstatus)
└── ChessKit/             Swift-package zonder UIKit: regels, notatie en engine
    └── Tests/            Swift Testing, inclusief perft-tests voor de zettengenerator
```

## Bouwen en testen

Open `ChessApp/ChessApp.xcodeproj` in Xcode en druk op Run. Voor je eigen iPhone kies je onder *Signing & Capabilities* je eigen Team.

De regels en de engine test je zo:

```bash
cd ChessApp/ChessKit && swift test
```

Met `CHESS_BENCH=1` draait ook een benchmark, die laat zien hoe diep en hoe snel de engine zoekt.

In debug-builds kun je de app direct in een partij laten starten (handig in de Simulator):

- `-startAsBlack` start een partij tegen de computer, waarin jij zwart speelt.
- `-debugFEN "<fen>"` start een tweespelerspartij vanuit die stelling.
