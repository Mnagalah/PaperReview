import Foundation
import Testing
@testable import PaperReview

@Test func bundledDownloadManifestKeepsTheCompetitionModelsAndExactTotal() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let files = try ModelDownloadFile.load(root.appendingPathComponent("script/model_downloads.tsv"))
    #expect(files.map(\.id) == ["ocr", "ocr-projector", "jev", "jev-projector", "review", "runtime"])
    #expect(files.map(\.relativePath).contains("weights/MiniCPM-OCR-1_0-F16.gguf"))
    #expect(files.map(\.relativePath).contains("weights/MiniCPM5-2B-Q4_K_M.gguf"))
    #expect(files.reduce(Int64(0)) { $0 + $1.bytes } == 5_940_866_994)
}

@Test func downloadSpeedExcludesCachedAndResumedBytesAndGoesToZeroWhenStalled() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = [downloadFile("cached", bytes: 100), downloadFile("partial", bytes: 400)]
    try Data(repeating: 0, count: 100).write(to: root.appendingPathComponent("cached"))
    try Data(repeating: 0, count: 20).write(to: root.appendingPathComponent("partial.part"))
    var progress = ModelDownloadProgress(files: files, home: root, now: 0)
    #expect(progress.received == 120 && progress.total == 500)
    #expect(progress.bytesPerSecond == 0 && progress.secondsRemaining == nil)
    try Data(repeating: 0, count: 70).write(to: root.appendingPathComponent("partial.part"))
    progress.refresh(now: 2)
    #expect(progress.received == 170 && progress.remaining == 330)
    #expect(progress.bytesPerSecond == 25)
    #expect(progress.secondsRemaining == 13.2)
    progress.refresh(now: 8)
    #expect(progress.bytesPerSecond == 0 && progress.secondsRemaining == nil)
    #expect(progress.waitingForData && progress.title == "等待服务器响应")
}

@Test func failedDownloadsRetainProgressAndRetryStartsWithAFreshSpeedBaseline() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(repeating: 0, count: 50).write(to: root.appendingPathComponent("ocr.part"))
    let files = [downloadFile("ocr", bytes: 100)]
    var progress = ModelDownloadProgress(files: files, home: root, now: 0)
    let event = try #require(ModelDownloadEvent("PR_DOWNLOAD\tocr\tfailed\t6\t连接中断"))
    progress.apply(event); progress.finish(error: "脚本失败")
    #expect(progress.phase == .failed && progress.received == 50 && progress.remaining == 50)
    #expect(progress.failure == "连接中断" && progress.items[0].stage == .failed)
    var retry = ModelDownloadProgress(files: files, home: root, now: 100)
    #expect(retry.received == 50 && retry.bytesPerSecond == 0)
    try FileManager.default.moveItem(at: root.appendingPathComponent("ocr.part"), to: root.appendingPathComponent("ocr"))
    try Data(repeating: 0, count: 100).write(to: root.appendingPathComponent("ocr"))
    retry.refresh(now: 102); retry.finish()
    #expect(retry.phase == .complete && retry.fraction == 1 && retry.remaining == 0)
    #expect(retry.items[0].stage == .complete && retry.bytesPerSecond == 0)
}

@Test func fileEventsSeparateRetryAndInstallationFromTransferCompletion() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var progress = ModelDownloadProgress(files: [downloadFile("runtime", bytes: 100)], home: root, now: 0)
    progress.apply(try #require(ModelDownloadEvent("PR_DOWNLOAD\truntime\tretrying\t2\t超时")))
    #expect(progress.title == "连接中断，正在重试" && progress.items[0].status == "重试 3/6")
    progress.apply(try #require(ModelDownloadEvent("PR_DOWNLOAD\truntime\tinstalling\t0\t")))
    #expect(progress.title == "正在安装运行时" && progress.phase == .downloading)
    #expect(ModelDownloadEvent("curl: connection failed") == nil)
    #expect(ModelDownloadEvent("PR_DOWNLOAD\truntime\tbogus\t1\t") == nil)
    progress.apply(try #require(ModelDownloadEvent("PR_DOWNLOAD\tunknown\tcomplete\t0\t")))
    #expect(progress.items.count == 1 && progress.items[0].stage == .installing)
}

private func downloadFile(_ id: String, bytes: Int64) -> ModelDownloadFile {
    ModelDownloadFile(id: id, title: id, relativePath: id, partialSuffix: ".part", bytes: bytes)
}
