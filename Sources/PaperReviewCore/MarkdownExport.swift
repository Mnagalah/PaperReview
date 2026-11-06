import Foundation

public enum MarkdownExport {
    /// Reconstruct source line/paragraph breaks without changing any transcribed word.
    public static func original(_ transcript: Transcript) -> String {
        guard transcript.isAligned, !transcript.lines.isEmpty else { return transcript.text }
        let lines = transcript.lines
        let spacings = zip(lines, lines.dropFirst()).map { $1.rect.y - $0.rect.y }.filter { $0 > 0 }.sorted()
        let typical = spacings.isEmpty ? 0.05 : spacings[(spacings.count - 1) / 2]
        var result = ""
        for (index, line) in lines.enumerated() {
            result += transcript.text(in: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if index + 1 < lines.count {
                result += lines[index + 1].rect.y - line.rect.y > typical * 1.5 ? "\n\n" : "  \n"
            }
        }
        return result + "\n"
    }

    /// Corrections remain appended suggestions; the original section is never edited.
    public static func annotated(_ transcript: Transcript, issues: [ReviewIssue], humanConfirmed: Bool, teacherReview: TeacherReview? = nil, uncertainIssueIDs: Set<UUID> = []) -> String {
        if let teacherReview { return teacherAnnotated(transcript, issues: issues, review: teacherReview, uncertainIssueIDs: uncertainIssueIDs) }
        var output = original(transcript)
        output += "\n\n---\n\n## 基础审核批注\n\n"
        output += humanConfirmed ? "原文已由老师核对。\n\n" : "以下为模型建议，请老师确认。\n\n"
        let valid = issues.filter { !$0.dismissed && $0.revision == transcript.revision }
        if valid.isEmpty { output += "未记录基础错误建议。\n" }
        for (index, issue) in valid.enumerated() {
            output += "\(index + 1). **\(issue.kind.title)** · L\(issue.lineID)：\(code(issue.quote))\n"
            if uncertainIssueIDs.contains(issue.id) { output += "   可能识别有误，请结合原稿核对。\n" }
            output += "   建议：\(code(issue.suggestion))。\(issue.explanation.replacingOccurrences(of: "\n", with: " "))\n\n"
        }
        return output
    }
    private static func teacherAnnotated(_ transcript: Transcript, issues: [ReviewIssue], review: TeacherReview, uncertainIssueIDs: Set<UUID>) -> String {
        var output = original(transcript) + "\n\n---\n\n## 批注\n\n"
        let annotations = review.confirmed
        if annotations.isEmpty { output += "暂无批注。\n" }
        for (index, decision) in annotations.enumerated() {
            output += "\(index + 1). **\(decision.issue.kind.title)**：\(code(decision.issue.quote))\n"
            if !decision.isAnchored(in: transcript) { output += "   位置待确认（对应较早版本的识别稿）。\n" }
            output += "   建议：\(code(decision.suggestion))。\(decision.explanation.replacingOccurrences(of: "\n", with: " "))\n\n"
        }
        let pending = review.pending(issues)
        if !pending.isEmpty {
            output += "\n## 待确认批注\n\n"
            for issue in pending {
                let warning = uncertainIssueIDs.contains(issue.id) ? "（可能识别有误）" : ""
                output += "- \(code(issue.quote)) → \(code(issue.suggestion))\(warning)：\(issue.explanation)\n"
            }
        }
        let kept = review.discarded
        if !kept.isEmpty {
            output += "\n## 已放弃的建议\n\n"
            for decision in kept { output += "- \(code(decision.issue.quote)) → \(code(decision.suggestion))\n" }
        }
        if !review.comment.isEmpty { output += "\n## 评语\n\n" + review.comment + "\n" }
        return output
    }

    private static func code(_ value: String) -> String {
        var fence = "`"
        while value.contains(fence) { fence += "`" }
        return "\(fence) \(value) \(fence)"
    }
}
