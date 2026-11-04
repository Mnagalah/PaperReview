import Foundation
import Testing
@testable import PaperReview

@Test func modelRemovalInventoryIncludesOnlyCurrentWeightsPartialsAndMarkers() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try makeRemovalFixture(root)
    defer { try? FileManager.default.removeItem(at: root) }
    let plan = try ModelRemovalPlan(home: root, files: removalFiles)
    #expect(Set(plan.relativePaths) == ["weights/ocr.gguf", "weights/ocr.gguf.modelscope.part", "models-ready", "ocr-model"])
    #expect(plan.bytes == 16)
    #expect(!plan.relativePaths.contains("Assignments/student.png"))
    #expect(!plan.relativePaths.contains("runtime/server"))
    #expect(!plan.relativePaths.contains("weights/unrelated.gguf"))
}

@Test func deletingAnOpenModelIsBlockedWithoutTouchingAnyFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try makeRemovalFixture(root)
    defer { try? FileManager.default.removeItem(at: root) }
    let handle = try FileHandle(forReadingFrom: root.appendingPathComponent("weights/ocr.gguf"))
    defer { try? handle.close() }
    let plan = try ModelRemovalPlan(home: root, files: removalFiles)
    do { _ = try await plan.moveToTrash(); Issue.record("An open model must not be moved") }
    catch let error as ModelRemovalError { #expect(error == .inUse) }
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("weights/ocr.gguf").path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("models-ready").path))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAPERREVIEW_MODEL_TRASH_TEST"] == "1"))
func modelRemovalMovesOnlySyntheticWeightsToTrashAndCanRestoreThem() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try makeRemovalFixture(root)
    defer { try? fm.removeItem(at: root) }
    let plan = try ModelRemovalPlan(home: root, files: removalFiles)
    let trash = try #require(try await plan.moveToTrash())
    #expect(!fm.fileExists(atPath: root.appendingPathComponent("weights/ocr.gguf").path))
    #expect(!fm.fileExists(atPath: root.appendingPathComponent("models-ready").path))
    for relative in ["runtime/server", "Assignments/student.png", "weights/unrelated.gguf"] {
        #expect(try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8) == "keep")
    }
    let restored = root.appendingPathComponent("restored")
    try fm.moveItem(at: trash, to: restored)
    #expect(try String(contentsOf: restored.appendingPathComponent("weights/ocr.gguf"), encoding: .utf8) == "test")
}

@Test @MainActor func savingTheModelDirectoryPersistsItAndRejectsRelativePaths() throws {
    let defaults = UserDefaults.standard
    let old = defaults.object(forKey: "modelHome")
    defer { if let old { defaults.set(old, forKey: "modelHome") } else { defaults.removeObject(forKey: "modelHome") } }
    let controller = ModelProcessController(modelHome: "relative/path")
    #expect(throws: (any Error).self) { try controller.saveModelHome() }
    controller.modelHome = " /tmp/PaperReview-model directory "
    try controller.saveModelHome()
    #expect(defaults.string(forKey: "modelHome") == "/tmp/PaperReview-model directory")
}

private let removalFiles = [
    ModelDownloadFile(id: "ocr", title: "OCR", relativePath: "weights/ocr.gguf", partialSuffix: ".modelscope.part", bytes: 4),
    ModelDownloadFile(id: "runtime", title: "runtime", relativePath: "runtime/server", partialSuffix: ".part", bytes: 4)
]
private func makeRemovalFixture(_ root: URL) throws {
    for relative in ["weights/ocr.gguf", "weights/ocr.gguf.modelscope.part", "models-ready", "ocr-model",
                     "runtime/server", "Assignments/student.png", "weights/unrelated.gguf"] {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = ["runtime/server", "Assignments/student.png", "weights/unrelated.gguf"].contains(relative) ? "keep" : "test"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
