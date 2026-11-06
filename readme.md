# iOSChess

Dit projectje heb ik lang geleden via Udemy gestart. Op iOS 10 werkte het, dus was de uitdaging er een nieuwere, modernere versie van te maken die op mijn huidige iOS 27 iPhone werkt. Dat is versie 2: helemaal opnieuw opgezet in SwiftUI. De oude UIKit-code staat nog in de git-geschiedenis.

## Wat zit erin

- **Alle schaakregels**: rokade, en passant, promotie, schaakmat, pat, 50-zettenregel, drievoudige herhaling en onvoldoende materiaal.
- **Computertegenstander** in drie niveaus: makkelijk (kijkt kort vooruit, met wat toeval), gemiddeld (0,7 s per zet) en moeilijk (2,5 s per zet, ruim 10 halve zetten diep). De engine gebruikt PVS met iteratief verdiepen, een transpositietabel, null-move pruning, late-move reductions en een PeSTO-evaluatie. Hij rekent op de achtergrond, dus de app blijft reageren.
- **Twee spelers** op één toestel.
- Tik-om-te-zetten én slepen, mogelijke zetten gemarkeerd, zettenlijst in standaardnotatie, zet terugnemen, bord draaien, donkere modus, iPhone en iPad (staand en liggend).

<img width="266" height="534" alt="Scherm­afbeelding 2026-11-06 om 09 23 38" src="https://github.com/user-attachments/assets/ef36130e-80ba-4eab-9a78-89e9ea10ca2a" />


## Opbouw

```
ChessApp/
├── ChessApp.xcodeproj    Xcode-project
├── ChessApp/             SwiftUI-app (schermen, bord, spelstatus)
└── ChessKit/             Swift-package zonder UIKit: regels, notatie en engine
    └── Tests/            Swift Testing, inclusief perft-tests voor de zettengenerator
```
