// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChessKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ChessKit", targets: ["ChessKit"])
    ],
    targets: [
        .target(name: "ChessKit"),
        .testTarget(name: "ChessKitTests", dependencies: ["ChessKit"])
    ]
)
