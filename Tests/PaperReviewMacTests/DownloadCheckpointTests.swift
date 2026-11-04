import Foundation
import Testing
@testable import PaperReview

@Test @MainActor func reopeningRestoresThePausedSnapshotWithoutReadingTheModelDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let resources = root.appendingPathComponent("Resources"), home = root.appendingPathComponent("models")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = "ocr\tOCR\tocr.gguf\t.part\t1000\thttps://example.invalid/ocr\n"
    try manifest.write(to: resources.appendingPathComponent("model_downloads.tsv"), atomically: true, encoding: .utf8)
    let files = try ModelDownloadFile.load(resources.appendingPathComponent("model_downloads.tsv"))
    try Data(repeating: 1, count: 280).write(to: home.appendingPathComponent("ocr.gguf.part"))
    let progress = ModelDownloadProgress(files: files, home: home, now: 0)
    let store = DownloadCheckpointStore(url: root.appendingPathComponent("state.json"))
    try store.save(progress)
    try FileManager.default.moveItem(at: home, to: root.appendingPathComponent("unavailable-models"))
    let controller = ModelProcessController(modelHome: home.path, scriptDirectory: resources, checkpointURL: store.url)
    #expect(controller.download?.phase == .paused)
    #expect(controller.download?.received == 280)
    #expect(controller.download?.bytesPerSecond == 0 && controller.download?.secondsRemaining == nil)
    #expect(!controller.busy && !controller.isDownloadActive)
    #expect(!FileManager.default.fileExists(atPath: home.path))
}

@Test func pausingKeepsBytesButClearsRateAndAChangedManifestCannotReuseWrongCounters() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = ModelDownloadFile(id: "ocr", title: "OCR", relativePath: "ocr", partialSuffix: ".part", bytes: 1000)
    var progress = ModelDownloadProgress(files: [file], home: root, now: 0)
    try Data(repeating: 0, count: 500).write(to: root.appendingPathComponent("ocr.part"))
    progress.refresh(now: 1)
    #expect(progress.bytesPerSecond == 500)
    progress.beginPausing(); progress.pause()
    #expect(progress.phase == .paused && progress.received == 500 && progress.bytesPerSecond == 0)
    #expect(progress.items[0].stage == .paused && progress.secondsRemaining == nil)
    let changed = ModelDownloadFile(id: "ocr", title: "OCR", relativePath: "new-ocr", partialSuffix: ".part", bytes: 2000)
    let restored = ModelDownloadProgress(files: [changed], home: root, checkpoint: DownloadCheckpoint(progress), now: 2)
    #expect(restored.received == 0 && restored.phase == .paused)
}

@Test @MainActor func completedAndOtherDirectoryCheckpointsDoNotCreateAResumeTask() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = ModelDownloadFile(id: "ocr", title: "OCR", relativePath: "ocr", partialSuffix: ".part", bytes: 1)
    var progress = ModelDownloadProgress(files: [file], home: root, now: 0)
    let store = DownloadCheckpointStore(url: root.appendingPathComponent("state.json"))
    try store.save(progress)
    let other = ModelProcessController(modelHome: "/different-model-location", checkpointURL: store.url)
    #expect(other.download == nil)
    try store.clear(home: URL(fileURLWithPath: "/different-model-location"))
    #expect(try store.load() != nil)
    progress.finish(); try store.save(progress)
    let complete = ModelProcessController(modelHome: root.path, checkpointURL: store.url)
    #expect(complete.download == nil)
    try store.clear(home: root)
    #expect(try store.load() == nil)
}
