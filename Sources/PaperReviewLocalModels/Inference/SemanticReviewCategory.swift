import Foundation
import PaperReviewCore

/// MiniCPM chooses the linguistic category after reading the complete source.
/// Fixed Chinese copy avoids fabricated subjects and explanation-language drift.
/// It is a localized category description, not a model quotation or proof.
enum SemanticReviewCategory: String, Codable, CaseIterable {
    case tense, agreement, pronoun_case, word_usage, spelling, capitalization, punctuation, not_an_error

    var kind: IssueKind {
        switch self {
        case .spelling: .spelling
        case .capitalization: .capitalization
        case .punctuation: .punctuation
        default: .grammar
        }
    }
    var explanation: String {
        switch self {
        case .tense: "动词形式应与上下文的时间背景一致。"
        case .agreement: "动词形式应与对应主语的人称和数一致。"
        case .pronoun_case: "代词形式应符合它在句中的主语或宾语位置。"
        case .word_usage: "结合上下文，此处用词或词形不当。"
        case .spelling: "原词存在拼写错误。"
        case .capitalization: "此处字母大小写有误。"
        case .punctuation: "此处标点使用不当。"
        case .not_an_error: "保留原文。"
        }
    }
}
