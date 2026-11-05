// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChessKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ChessKit", targets: ["ChessKit"])
    ],
    targets: [
        .target(
            name: "ChessKit",
            swiftSettings: [
                // The engine is useless without optimisation, so optimise it even in Debug
                // builds (e.g. when running from Xcode on a device).
                .unsafeFlags(["-O"], .when(configuration: .debug))
            ]
        ),
        .testTarget(name: "ChessKitTests", dependencies: ["ChessKit"])
    ]
)
