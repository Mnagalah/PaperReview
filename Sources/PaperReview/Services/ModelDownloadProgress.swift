import Foundation

nonisolated struct ModelDownloadFile: Identifiable, Sendable {
    let id: String
    let title: String
    let relativePath: String
    let partialSuffix: String
    let bytes: Int64

    static func load(_ url: URL) throws -> [Self] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6, let bytes = Int64(fields[4]), bytes > 0 else {
                throw NSError(domain: "PaperReview.Download", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "下载清单无效，请重新安装应用。"])
            }
            return Self(id: fields[0], title: fields[1], relativePath: fields[2], partialSuffix: fields[3], bytes: bytes)
        }
    }
}

nonisolated struct ModelDownloadEvent: Sendable {
    let id: String
    let stage: ModelDownloadProgress.FileStage
    let attempt: Int
    let message: String

    init?(_ line: String) {
        let fields = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 5, fields[0] == "PR_DOWNLOAD",
              let stage = ModelDownloadProgress.FileStage(rawValue: fields[2]), let attempt = Int(fields[3]) else { return nil }
        id = fields[1]; self.stage = stage; self.attempt = attempt; message = fields[4]
    }
}

nonisolated struct ModelDownloadProgress: Sendable {
    enum Phase: Sendable { case downloading, failed, complete }
    enum FileStage: String, Sendable { case waiting, downloading, retrying, installing, complete, failed }
    struct Item: Identifiable, Sendable {
        let file: ModelDownloadFile
        var received: Int64 = 0
        var stage = FileStage.waiting
        var attempt = 0
        var message = ""
        var id: String { file.id }
        var fraction: Double { Double(received) / Double(file.bytes) }
        var status: String {
            switch stage {
            case .waiting: "等待"
            case .downloading: attempt > 1 ? "续传 \(attempt)/6" : "下载中"
            case .retrying: "重试 \(min(attempt + 1, 6))/6"
            case .installing: "安装中"
            case .complete: "已完成"
            case .failed: "失败"
            }
        }
    }
    let home: URL
    private(set) var items: [Item]
    private(set) var phase = Phase.downloading
    private(set) var bytesPerSecond = 0.0
    private(set) var waitingForData = false
    private(set) var failure = ""
    private var samples: [(time: TimeInterval, bytes: Int64)] = []
    private var lastProgress: TimeInterval
    var received: Int64 { items.reduce(0) { $0 + $1.received } }
    var total: Int64 { items.reduce(0) { $0 + $1.file.bytes } }
    var remaining: Int64 { max(0, total - received) }
    var fraction: Double { total > 0 ? Double(received) / Double(total) : 0 }
    var secondsRemaining: TimeInterval? {
        phase == .downloading && bytesPerSecond > 0 && remaining > 0 ? Double(remaining) / bytesPerSecond : nil
    }
    var title: String {
        switch phase {
        case .complete: "下载完成"
        case .failed: "下载未完成，进度已保留"
        case .downloading:
            if items.contains(where: { $0.stage == .installing }) { "正在安装运行时" }
            else if items.contains(where: { $0.stage == .retrying }) { "连接中断，正在重试" }
            else if waitingForData { "等待服务器响应" }
            else { "正在下载模型" }
        }
    }

    init(files: [ModelDownloadFile], home: URL, now: TimeInterval) {
        self.home = home; items = files.map { Item(file: $0) }; lastProgress = now
        refresh(now: now)
    }
    mutating func apply(_ event: ModelDownloadEvent) {
        guard let index = items.firstIndex(where: { $0.id == event.id }) else { return }
        items[index].stage = event.stage; items[index].attempt = event.attempt; items[index].message = event.message
    }
    mutating func refresh(now: TimeInterval) {
        for index in items.indices {
            let file = items[index].file
            let dest = home.appendingPathComponent(file.relativePath)
            let completeSize = Self.size(dest)
            let runtime = file.id == "runtime" && Self.hasRuntime(home)
            if items[index].stage == .complete || completeSize == file.bytes || runtime {
                items[index].received = file.bytes
            } else {
                items[index].received = min(file.bytes, Self.size(URL(fileURLWithPath: dest.path + file.partialSuffix)))
            }
        }
        if let last = samples.last {
            if received > last.bytes { lastProgress = now }
            if received < last.bytes { samples.removeAll() }
        }
        samples.removeAll { $0.time < now - 5 }
        samples.append((now, received))
        if let first = samples.first, now - first.time >= 0.5 {
            bytesPerSecond = max(0, Double(received - first.bytes) / (now - first.time))
        } else { bytesPerSecond = 0 }
        waitingForData = now - lastProgress >= 5 && remaining > 0
    }
    mutating func finish(error: String? = nil) {
        bytesPerSecond = 0; waitingForData = false
        if let error {
            phase = .failed
            failure = items.first(where: { $0.stage == .failed })?.message ?? error
        } else {
            phase = .complete
            for index in items.indices { items[index].received = items[index].file.bytes; items[index].stage = .complete }
        }
    }
    private static func size(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }
    private static func hasRuntime(_ home: URL) -> Bool {
        guard let path = try? String(contentsOf: home.appendingPathComponent("runtime.path"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }
}
