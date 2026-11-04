import Foundation
import Testing
@testable import PaperReviewCore

private func spreadHints() -> [TextHint] {
    [
        .init(text: "Left page begins down here.", rect: .init(x: 0.06, y: 0.45, width: 0.36, height: 0.04)),
        .init(text: "The second line has more words.", rect: .init(x: 0.06, y: 0.54, width: 0.37, height: 0.04)),
        .init(text: "We want to prevent", rect: .init(x: 0.06, y: 0.65, width: 0.35, height: 0.04)),
        .init(text: "it and nobody makes it.", rect: .init(x: 0.52, y: 0.02, width: 0.31, height: 0.04)),
        .init(text: "We are small drops of water.", rect: .init(x: 0.52, y: 0.09, width: 0.35, height: 0.04)),
        .init(text: "Let's start by saving food!", rect: .init(x: 0.52, y: 0.16, width: 0.33, height: 0.04))
    ]
}

@Test func rightPageHigherThanLeftStillFollowsTheWholeLeftPage() throws {
    let hints = spreadHints()
    let regions = ReadingOrder.regions(hints: hints, aspectRatio: 1.78)
    #expect(regions.count == 2)
    #expect(ReadingOrder.rowGroups(hints: hints, regions: regions) == [[0], [1], [2], [3], [4], [5]])
    let left = hints.prefix(3).map(\.text).joined(separator: "\n")
    let right = hints.suffix(3).map(\.text).joined(separator: "\n")
    let transcript = ReadingOrder.transcript(texts: [left, right], hints: hints, regions: regions)
    #expect(transcript.text == left + "\n" + right)
    #expect(transcript.lines.map { transcript.text(in: $0) }.joined() == transcript.text)
    #expect(transcript.lines.map(\.sourceRowID) == [1, 2, 3, 4, 5, 6])
    #expect(transcript.lines[3].rect.y < transcript.lines[0].rect.y)
    #expect(transcript.lines[0].readingRegion == regions[0])
    #expect(transcript.lines[3].readingRegion == regions[1])
    let pages = ReadingOrder.pageTranscripts(transcript)
    #expect(pages.count == 2)
    #expect(pages[0].transcript.text == left + "\n")
    #expect(pages[1].transcript.text == right)
}

@Test func spreadRowsAtTheSameHeightNeverMergeAcrossTheGutter() {
    var hints = spreadHints()
    hints[3] = .init(text: hints[3].text, rect: .init(x: 0.52, y: 0.45, width: 0.31, height: 0.04))
    let regions = ReadingOrder.regions(hints: hints, aspectRatio: 1.78)
    #expect(regions.count == 2)
    let groups = ReadingOrder.rowGroups(hints: hints, regions: regions)
    #expect(!groups.contains { $0.contains(0) && $0.contains(3) })
    #expect(groups.first == [0])
}

@Test func longRowsAndRaggedSinglePageFragmentsAreNotSplitIntoPages() {
    let hints = (0..<6).map { index in
        TextHint(text: "A single-page essay has ordinary words on every line.",
            rect: .init(x: 0.06, y: Double(index) * 0.1, width: index % 2 == 0 ? 0.84 : 0.50, height: 0.04))
    }
    #expect(ReadingOrder.regions(hints: hints, aspectRatio: 1.5) == [ReadingOrder.fullPage])
    #expect(ReadingOrder.regions(hints: spreadHints(), aspectRatio: 0.75) == [ReadingOrder.fullPage])
}

@Test func firstPageCanAppearBeforeTheSecondPageAndBadAlignmentStaysLocal() {
    let hints = spreadHints(), regions = ReadingOrder.regions(hints: spreadHints(), aspectRatio: 1.78)
    let left = hints.prefix(3).map(\.text).joined(separator: "\n")
    let partial = ReadingOrder.transcript(texts: [left], hints: hints, regions: regions)
    #expect(partial.text == left)
    #expect(partial.lines.allSatisfy { $0.readingRegion == regions[0] })
    let complete = ReadingOrder.transcript(texts: [left, "Unreadable different content."], hints: hints, regions: regions)
    #expect(complete.isAligned)
    #expect(!complete.isFullyAligned)
    #expect(complete.lines.prefix(3).allSatisfy { $0.hasGeometry })
    #expect(complete.lines.last?.hasGeometry == false)
    #expect(complete.lines.last?.readingRegion == regions[1])
}

@Test func wordRepairDoesNotMoveTextAcrossPageBoundaries() {
    let hints = spreadHints(), regions = ReadingOrder.regions(hints: spreadHints(), aspectRatio: 1.78)
    let left = hints.prefix(3).map(\.text).joined(separator: "\n")
    let right = hints.suffix(3).map(\.text).joined(separator: "\n")
    let original = ReadingOrder.transcript(texts: [left, right], hints: hints, regions: regions)
    let range = (original.text as NSString).range(of: "second")
    let repaired = ReadingOrder.replacing([(range, "secondd")], in: original)
    #expect(repaired.text == original.text.replacingOccurrences(of: "second", with: "secondd"))
    #expect(repaired.lines[3].start == original.lines[3].start + 1)
    #expect(repaired.lines[3].readingRegion == regions[1])
    #expect(repaired.lines.map { repaired.text(in: $0) }.joined() == repaired.text)
    #expect(repaired.lines.map(\.sourceRowID) == original.lines.map(\.sourceRowID))
}
