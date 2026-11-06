import Foundation

nonisolated struct ReadingState: Codable, Equatable, Sendable {
    var presentation = "sideBySide"
    var zoom = 1.0
    var offsetX = 0.0
    var offsetY = 0.0
    var readingOffsetY = 0.0
    enum CodingKeys: String, CodingKey { case presentation, zoom, offsetX, offsetY, readingOffsetY, selectedIssueID }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        presentation = try values.decodeIfPresent(String.self, forKey: .presentation) ?? "sideBySide"
        zoom = min(2, max(0.75, try values.decodeIfPresent(Double.self, forKey: .zoom) ?? 1))
        offsetX = try values.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try values.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
        readingOffsetY = try values.decodeIfPresent(Double.self, forKey: .readingOffsetY) ?? 0
        selectedIssueID = try values.decodeIfPresent(UUID.self, forKey: .selectedIssueID)
    }
    var selectedIssueID: UUID?
}

enum AssignmentFilter: String, CaseIterable, Identifiable {
    case all, pending, completed
    var id: Self { self }
    var title: String { switch self { case .all: "全部作业"; case .pending: "待批阅"; case .completed: "已批阅" } }
    var symbol: String { switch self { case .all: "tray"; case .pending: "clock"; case .completed: "checkmark.circle" } }
    func includes(_ job: Assignment) -> Bool {
        self == .all || (self == .completed) == job.isReviewed
    }
}
