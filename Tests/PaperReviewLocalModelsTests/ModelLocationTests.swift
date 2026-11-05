import Foundation
import Testing
@testable import PaperReviewLocalModels

@Test @MainActor func releaseModelsUseApplicationSupportAndDevelopmentModelsKeepTheirExistingLocation() {
    let home = ModelProcessController.defaultModelHome(projectRoot: "")
    #expect(home == FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PaperReview/Models", isDirectory: true).path)
    #expect(!home.contains("/Documents/"))
    #expect(ModelProcessController.defaultModelHome(projectRoot: "/workspace/PaperReview") == "/workspace/PaperReview/.local-models")
}
