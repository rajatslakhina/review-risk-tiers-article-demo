// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReviewTiers",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReviewTiers", targets: ["ReviewTiers"])
    ],
    targets: [
        .target(name: "ReviewTiers"),
        .testTarget(name: "ReviewTiersTests", dependencies: ["ReviewTiers"])
    ]
)
