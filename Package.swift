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
        .target(name: "PaperReviewLocalModels", dependencies: ["PaperReviewCore"]),
        .executableTarget(
            name: "PaperReview",
            dependencies: ["PaperReviewCore", "PaperReviewLocalModels"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "PaperReviewCoreTests", dependencies: ["PaperReviewCore"]),
        .testTarget(name: "PaperReviewLocalModelsTests", dependencies: ["PaperReviewLocalModels", "PaperReviewCore"]),
        .testTarget(name: "PaperReviewMacTests", dependencies: ["PaperReview", "PaperReviewCore", "PaperReviewLocalModels"])
    ],
    swiftLanguageModes: [.v6]
)
