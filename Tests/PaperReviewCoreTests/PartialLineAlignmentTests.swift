import Foundation
import Testing
@testable import PaperReviewCore

private let rows = ["My first film is funny.", "A rabbit and a fox are friends.", "They help everyone in the city.", "They appear."]
private func rowHints(_ texts: [String], x: Double = 0.12) -> [TextHint] {
    texts.enumerated().map { i, text in
        .init(text: text, rect: .init(x: x, y: 0.18 + Double(i) * 0.17, width: 0.36, height: 0.07))
    }
}

@Test func oneUnreadableRowDoesNotDiscardTheOtherRowsOrInventAWordAnchor() {
    let text = rows.joined(separator: "\n")
    let hints = rowHints(Array(rows.prefix(3)) + ["zzzz qqqq xxxx"])
    let transcript = LineAlignment.makeTranscript(text: text, hints: hints)
    #expect(transcript.isAligned && !transcript.isFullyAligned)
    #expect(transcript.lines.map(\.hasGeometry) == [true, true, true, false])
    #expect(transcript.lines.map(\.rect.y) == hints.map(\.rect.y))
    #expect(transcript.lines.map { transcript.text(in: $0) }.joined() == text)
    let words = hints.enumerated().map { i, hint in
        WordHint(lineID: i + 1, text: i == 3 ? "appear" : "My", rect: hint.rect, confidence: 1)
    }
    let inventory = WordAlignment.inventory(transcript, hints: words)
    #expect(inventory.regions.filter { $0.lineID == 4 }.allSatisfy { $0.range == nil })
}

@Test func rowCountAndUnrelatedOrShiftedTextCannotInventCorrespondence() {
    let text = rows.joined(separator: "\n")
    #expect(!LineAlignment.makeTranscript(text: text, hints: rowHints(Array(repeating: "zzzz qqqq xxxx", count: 4))).isAligned)
    let shifted = rowHints([rows[1], rows[2], rows[0], "zzzz qqqq xxxx"])
    let result = LineAlignment.makeTranscript(text: text, hints: shifted)
    #expect(!result.isAligned)
    #expect(result.text == text)
}

@Test func partialRowsRetainEmojiBlankLinesAndOriginalPunctuation() {
    let text = "😀 " + rows[0] + "\n\n" + rows.dropFirst().joined(separator: "\n") + "\n"
    let result = LineAlignment.makeTranscript(text: text, hints: rowHints(Array(rows.prefix(3)) + ["zzzz qqqq xxxx"]))
    #expect(result.isAligned && result.lines.count == 4)
    #expect(result.lines.map { result.text(in: $0) }.joined() == text)
    #expect(result.text(in: result.lines[0]).hasSuffix("\n\n"))
    #expect(result.lines.last?.hasGeometry == false)
}

@Test func partialRowSlotsOnTheRightPageAreNotTransformedTwice() {
    let left = rows.joined(separator: "\n"), right = rows.joined(separator: "\n")
    let regions = [PageRect(x: 0, y: 0, width: 0.5, height: 1), PageRect(x: 0.5, y: 0, width: 0.5, height: 1)]
    let leftHints = rowHints(rows, x: 0.06)
    let rightHints = rowHints(Array(rows.prefix(3)) + ["zzzz qqqq xxxx"], x: 0.56)
    let result = ReadingOrder.transcript(texts: [left, right], hints: leftHints + rightHints, regions: regions)
    #expect(result.isAligned && !result.isFullyAligned)
    #expect(result.lines.last?.rect == rightHints.last?.rect)
    #expect(result.lines.last?.hasGeometry == false)
    #expect(result.text == left + "\n" + right)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_ALIGNMENT_RECORD"] != nil))
func inspectSavedPartialRowAlignment() throws {
    let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PAPERREVIEW_ALIGNMENT_RECORD"]))
    struct Record: Decodable { let transcript: Transcript }
    let decoder = JSONDecoder()
    let old = try decoder.decode(Record.self, from: Data(contentsOf: root.appendingPathComponent("record.json"))).transcript
    let hints = try decoder.decode([TextHint].self, from: Data(contentsOf: root.appendingPathComponent("line-geometry.json")))
    let result = LineAlignment.makeTranscript(text: old.text, hints: hints)
    #expect(result.text == old.text)
    #expect(result.isAligned && !result.isFullyAligned)
    #expect(result.lines.map(\.hasGeometry) == [true, true, true, false])
    #expect(result.lines.map(\.rect.y) == hints.map(\.rect.y))
}
