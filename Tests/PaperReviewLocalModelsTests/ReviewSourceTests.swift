import Foundation
import Testing
import PaperReviewCore
@testable import PaperReviewLocalModels

@Test func reviewLineIDsStayOutsideTheStudentTextField() throws {
    let body = "I have 2 cats.\nIn 2024 I goed home.\nMy freind came."
    let source = try ModelClient.reviewSource(LineAlignment.fallback(body))
    let rows = try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]])
    #expect(rows.count == 3)
    #expect(rows[0]["id"] as? Int == 1)
    #expect(rows[0]["text"] as? String == "I have 2 cats.\n")
    #expect((rows[1]["text"] as? String)?.contains("2024 I goed") == true)
    #expect(!source.contains("Student's Writing"))
}
