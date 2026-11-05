import Foundation
import Testing
@testable import PaperReviewCore

private let numberBoxes = (0..<5).map { index in
    PageRect(x: 0.08, y: 0.12 + Double(index) * 0.14, width: 0.045, height: 0.08)
}
private func formFragments() -> [TextHint] {
    [.init(text: "Student's Writing", rect: .init(x: 0.08, y: 0.02, width: 0.22, height: 0.04))]
        + (0..<4).map { index in .init(text: "My freind go home in 2024 with 2 cats.",
            rect: .init(x: 0.16, y: 0.12 + Double(index) * 0.14, width: 0.65, height: 0.07)) }
}

@Test func repeatedWorkbookBoxesAreMetadataEvenIfVisionCannotReadTheDigits() {
    let annotations = PageScaffolding.annotations(fragments: formFragments(), rectangles: numberBoxes, aspectRatio: 1.78)
    #expect(annotations.filter { $0.kind == .lineNumber }.count == 5)
    #expect(annotations.filter { $0.kind == .formLabel }.count == 1)
    #expect(annotations.filter { $0.kind == .lineNumber }.allSatisfy { $0.text == nil })
    #expect(!annotations.contains { PageScaffolding.covers(formFragments()[1].rect, with: $0) })
}

@Test func ordinaryEssayNumbersAndUnprovenBoxesStayInTheContent() {
    let prose = [TextHint(text: "In 2024 I have 2 cats and 3 dogs.", rect: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.1))]
    #expect(PageScaffolding.annotations(fragments: prose, rectangles: numberBoxes, aspectRatio: 1.78).isEmpty)
    let raw = "1 I have 2 cats.\n2 In 2024 I went home.\n3 My freind came."
    #expect(PageScaffolding.bodyText(raw, annotations: []) == raw)
}

@Test func workbookCleanupRemovesOnlyRowLabelsAndKeepsStudentErrorsNumbersAndCase() {
    let annotations = PageScaffolding.annotations(fragments: formFragments(), rectangles: numberBoxes, aspectRatio: 1.78)
    let raw = "Student's Writing\n1I have 2 cats.\n2 In 2024 I goed home.\n3 My freind came.\n4 they was happy.\n5"
    let body = PageScaffolding.bodyText(raw, annotations: annotations)
    #expect(body == "I have 2 cats.\nIn 2024 I goed home.\nMy freind came.\nthey was happy.\n")
    #expect(raw.hasPrefix("Student's Writing\n1I"))
}

@Test func studentListsAndNonSequentialNumbersAreNotBlindlyRemoved() {
    let annotations = PageScaffolding.annotations(fragments: formFragments(), rectangles: numberBoxes, aspectRatio: 1.78)
    let list = "1. I like apples.\n2. I like pears.\n3. I like cats."
    let years = "2022 I came.\n2023 I left.\n2024 I returned."
    let irregular = "1 I came.\n4 I left.\n7 I returned."
    #expect(PageScaffolding.bodyText(list, annotations: annotations) == list)
    #expect(PageScaffolding.bodyText(years, annotations: annotations) == years)
    #expect(PageScaffolding.bodyText(irregular, annotations: annotations) == irregular)
}

@Test func isolatedMarginRectangleDoesNotAuthorizeContentRemoval() {
    #expect(PageScaffolding.annotations(fragments: formFragments(), rectangles: [numberBoxes[0]], aspectRatio: 1.78).isEmpty)
}

@Test func slightlySkewedMarginStillIncludesTheFirstNumberBox() {
    let boxes = (0..<5).map { index in PageRect(x: 0.078 - Double(index) * 0.005,
        y: 0.12 + Double(index) * 0.14, width: 0.059, height: 0.10) }
    let annotations = PageScaffolding.annotations(fragments: formFragments(), rectangles: boxes, aspectRatio: 1.78)
    #expect(annotations.filter { $0.kind == .lineNumber }.count == 5)
    #expect(annotations.contains { $0.rect == boxes[0] })
}

@Test func worksheetPromptMetadataCannotCoverTheHigherRightPageContinuation() {
    let fragments: [TextHint] = [
        .init(text: "Reflection Checklist:", rect: .init(x: 0.1, y: 0.10, width: 0.25, height: 0.03)),
        .init(text: "Does your response include clear examples?", rect: .init(x: 0.1, y: 0.16, width: 0.30, height: 0.03)),
        .init(text: "Student's Writing", rect: .init(x: 0.1, y: 0.30, width: 0.25, height: 0.03)),
        .init(text: "We try to prevent", rect: .init(x: 0.1, y: 0.50, width: 0.30, height: 0.04)),
        .init(text: "it and nobody makes it.", rect: .init(x: 0.55, y: 0.02, width: 0.30, height: 0.04)),
        .init(text: "We are drops of water.", rect: .init(x: 0.55, y: 0.09, width: 0.30, height: 0.04)),
        .init(text: "Let's start by saving food.", rect: .init(x: 0.55, y: 0.16, width: 0.32, height: 0.04))
    ]
    let annotations = PageScaffolding.annotations(fragments: fragments, rectangles: [], aspectRatio: 1.78)
    #expect(annotations.count == 3)
    #expect(!annotations.contains { PageScaffolding.covers(fragments[4].rect, with: $0) })
    #expect(!annotations.contains { PageScaffolding.covers(fragments[3].rect, with: $0) })
}

@Test func legacyHeadingAttachedToTheFirstBodyLineRemainsMetadata() {
    let annotations = PageScaffolding.annotations(fragments: formFragments(), rectangles: numberBoxes, aspectRatio: 1.78)
    let text = "Student's Writing My first film is good.\n2 I like it.\n3 It was funny.\n4 I was happy.\n5"
    #expect(PageScaffolding.bodyText(text, annotations: annotations) == "My first film is good.\nI like it.\nIt was funny.\nI was happy.\n")
}
