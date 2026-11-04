import Foundation

/// Vision can split one slanted handwriting row into several observations.
/// Group geometrically compatible, horizontally separate fragments before ordering.
public enum TextRowGrouping {
    public static func groups(_ hints: [TextHint]) -> [[Int]] {
        var rows: [[Int]] = []
        for index in hints.indices.sorted(by: { hints[$0].rect.y + hints[$0].rect.height / 2 < hints[$1].rect.y + hints[$1].rect.height / 2 }) {
            let box = hints[index].rect
            let candidates = rows.indices.filter { row in
                // Overlapping x ranges normally mean different written rows.
                let separated = rows[row].allSatisfy { other in
                    let rect = hints[other].rect
                    let overlap = max(0, min(box.x + box.width, rect.x + rect.width) - max(box.x, rect.x))
                    return overlap <= min(box.width, rect.width) * 0.08
                }
                let sameBand = rows[row].contains { other in
                    let rect = hints[other].rect
                    let overlap = max(0, min(box.y + box.height, rect.y + rect.height) - max(box.y, rect.y))
                    return overlap >= min(box.height, rect.height) * 0.5
                }
                return separated && sameBand
            }
            if let row = candidates.min(by: { a, b in
                func mid(_ row: Int) -> Double { rows[row].map { hints[$0].rect.y + hints[$0].rect.height / 2 }.reduce(0, +) / Double(rows[row].count) }
                return abs(mid(a) - box.y - box.height / 2) < abs(mid(b) - box.y - box.height / 2)
            }) { rows[row].append(index) }
            else { rows.append([index]) }
        }
        return rows.sorted { a, b in
            let ay = a.map { hints[$0].rect.y + hints[$0].rect.height / 2 }.reduce(0, +) / Double(a.count)
            let by = b.map { hints[$0].rect.y + hints[$0].rect.height / 2 }.reduce(0, +) / Double(b.count)
            return ay < by
        }.map { $0.sorted { hints[$0].rect.x < hints[$1].rect.x } }
    }

    public static func merged(_ group: [Int], hints: [TextHint]) -> TextHint {
        let row = group.map { hints[$0] }
        let x = row.map(\.rect.x).min()!, y = row.map(\.rect.y).min()!
        return TextHint(text: row.map(\.text).joined(separator: " "), rect: PageRect(x: x, y: y,
            width: row.map { $0.rect.x + $0.rect.width }.max()! - x,
            height: row.map { $0.rect.y + $0.rect.height }.max()! - y), confidence: row.map(\.confidence).min() ?? 0)
    }
}
