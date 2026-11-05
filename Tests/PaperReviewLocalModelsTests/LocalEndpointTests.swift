import Foundation
import Testing
import PaperReviewCore
@testable import PaperReviewLocalModels

@Test(arguments: ["https://example.com", "http://192.168.1.8:8000", "http://localhost.evil.test:8000", "http://user@localhost", "http://localhost/v1", "http://localhost?token=x"])
func studentDataCannotLeaveLoopback(_ url: String) {
    #expect(throws: ModelError.self) { try LocalEndpoint.base(url) }
}

@Test(arguments: ["http://127.0.0.1:18499", "http://localhost:18500/", "http://[::1]:18501"])
func localAddressesAreAccepted(_ url: String) throws { _ = try LocalEndpoint.base(url) }

@Test func invalidReviewJSONIsAnErrorNotAnEmptyPass() {
    #expect(throws: ModelError.self) { try ModelClient.decodeReview("Everything looks great!") }
}
