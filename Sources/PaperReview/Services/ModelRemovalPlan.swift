import Foundation

nonisolated struct ModelRemovalPlan: Sendable {
    let home: URL
    let relativePaths: [String]
    let bytes: Int64

    init(home: URL, files: [ModelDownloadFile]) throws {
        self.home = home
        let names = files.filter { $0.id != "runtime" }.flatMap { [$0.relativePath, $0.relativePath + $0.partialSuffix] }
            + ["models-ready", "ocr-model"]
        relativePaths = names.filter { FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path) }
        bytes = try relativePaths.reduce(Int64(0)) { sum, path in
            let attributes = try FileManager.default.attributesOfItem(atPath: home.appendingPathComponent(path).path)
            return sum + ((attributes[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    @concurrent func checkNotInUse() async throws {
        let paths = relativePaths.map { home.appendingPathComponent($0).path }
        guard !paths.isEmpty else { return }
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.arguments = ["-nP", "-t", "--"] + paths
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let pids = output.fileHandleForReading.readDataToEndOfFile()
        let error = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if !pids.isEmpty { throw ModelRemovalError.inUse }
        guard process.terminationStatus == 1 && error.isEmpty else { throw ModelRemovalError.cannotCheck }
    }

    @concurrent func moveToTrash() async throws -> URL? {
        try await checkNotInUse()
        let fm = FileManager.default
        let stage = home.appendingPathComponent("待删除模型-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        var moved: [String] = []
        do {
            for relative in relativePaths {
                let destination = stage.appendingPathComponent(relative)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: home.appendingPathComponent(relative), to: destination)
                moved.append(relative)
            }
            var result: NSURL?
            try fm.trashItem(at: stage, resultingItemURL: &result)
            return result as URL?
        } catch {
            for relative in moved.reversed() {
                do { try fm.moveItem(at: stage.appendingPathComponent(relative), to: home.appendingPathComponent(relative)) }
                catch { throw ModelRemovalError.recovery(stage.path) }
            }
            try? fm.removeItem(at: stage) // Empty staging folder only; model files were restored.
            throw error
        }
    }
}

nonisolated enum ModelRemovalError: LocalizedError, Equatable {
    case inUse, cannotCheck, recovery(String)
    var errorDescription: String? {
        switch self {
        case .inUse: "模型文件正在使用。请先停止模型，或等待下载结束后重试。"
        case .cannotCheck: "无法确认模型是否已停止，暂未删除。请稍后重试。"
        case .recovery(let path): "删除未完成，文件保留在：\(path)"
        }
    }
}
