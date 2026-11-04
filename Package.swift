// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PaperReview",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PaperReview", targets: ["PaperReview"]),
        .library(name: "PaperReviewCore", targets: ["PaperReviewCore"])
    ],
    targets: [
        .target(name: "PaperReviewCore"),
        .executableTarget(
            name: "PaperReview",
            dependencies: ["PaperReviewCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "PaperReviewCoreTests", dependencies: ["PaperReviewCore"]),
        .testTarget(name: "PaperReviewMacTests", dependencies: ["PaperReview", "PaperReviewCore"])
    ],
    swiftLanguageModes: [.v6]
)
