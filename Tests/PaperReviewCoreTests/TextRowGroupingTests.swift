import Testing
@testable import PaperReviewCore

@Test func slantedFragmentsAreReadLeftToRightWithinTheSameRow() {
    let fragments: [TextHint] = [
        .init(text: "right", rect: .init(x: 0.48, y: 0.02, width: 0.4, height: 0.13)),
        .init(text: "left", rect: .init(x: 0.19, y: 0.06, width: 0.25, height: 0.08)),
        .init(text: "next right", rect: .init(x: 0.67, y: 0.135, width: 0.18, height: 0.09)),
        .init(text: "next middle", rect: .init(x: 0.21, y: 0.157, width: 0.43, height: 0.087)),
        .init(text: "next left", rect: .init(x: 0.08, y: 0.194, width: 0.09, height: 0.052))
    ]
    let groups = TextRowGrouping.groups(fragments)
    #expect(groups == [[1, 0], [4, 3, 2]])
    #expect(TextRowGrouping.merged(groups[0], hints: fragments).text == "left right")
}

@Test func verticallyOverlappingFullRowsAreNotMerged() {
    let fragments: [TextHint] = [
        .init(text: "first", rect: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.15)),
        .init(text: "second", rect: .init(x: 0.1, y: 0.16, width: 0.8, height: 0.15))
    ]
    #expect(TextRowGrouping.groups(fragments) == [[0], [1]])
}
