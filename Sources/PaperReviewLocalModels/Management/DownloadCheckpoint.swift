import Foundation

nonisolated struct DownloadCheckpoint: Codable, Sendable {
    struct File: Codable, Sendable {
        let id: String
        let relativePath: String
        let bytes: Int64
        let received: Int64
        let complete: Bool
    }
    let home: String
    let state: String
    let failure: String
    let files: [File]
    init(_ progress: ModelDownloadProgress) {
        home = progress.home.path
        state = progress.phase.rawValue
        failure = progress.failure
        files = progress.items.map { File(id: $0.id, relativePath: $0.file.relativePath, bytes: $0.file.bytes,
            received: $0.received, complete: $0.stage == .complete) }
    }
}

nonisolated struct DownloadCheckpointStore: Sendable {
    let url: URL
    static var applicationDefault: Self {
        let domain = Bundle.main.bundleIdentifier ?? "local.paperreview.mac"
        let name = domain == "local.paperreview.mac" ? "download.json" : "download-\(domain).json"
        return Self(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperReview/Downloads", isDirectory: true).appendingPathComponent(name))
    }
    func load() throws -> DownloadCheckpoint? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(DownloadCheckpoint.self, from: Data(contentsOf: url))
    }
    func save(_ progress: ModelDownloadProgress) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(DownloadCheckpoint(progress)).write(to: url, options: .atomic)
    }
    func clear(home: URL) throws {
        if let checkpoint = try load(), checkpoint.home == home.path { try FileManager.default.removeItem(at: url) }
    }
}
