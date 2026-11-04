import Foundation
import Observation

@Observable final class ModelProcessController {
    var busy = false
    var output = ""
    var download: ModelDownloadProgress?
    var removal: ModelRemovalPlan?
    var modelHome: String {
        didSet { if modelHome != oldValue && !busy { download = nil; removal = nil; output = "" } }
    }
    private let scriptDirectory: URL?
    init(modelHome: String? = nil, scriptDirectory: URL? = Bundle.main.resourceURL) {
        let project = Bundle.main.object(forInfoDictionaryKey: "PaperReviewProjectRoot") as? String ?? ""
        self.modelHome = modelHome ?? UserDefaults.standard.string(forKey: "modelHome") ?? Self.defaultModelHome(projectRoot: project)
        self.scriptDirectory = scriptDirectory
    }
    static func defaultModelHome(projectRoot: String) -> String {
        if !projectRoot.isEmpty { return projectRoot + "/.local-models" }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperReview/Models", isDirectory: true).path
    }
    func saveModelHome() throws {
        let path = (modelHome.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else {
            throw NSError(domain: "PaperReview.ModelControl", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "请选择模型目录，或填写完整路径。"])
        }
        modelHome = path
        UserDefaults.standard.set(path, forKey: "modelHome")
    }
    func prepareRemoval() {
        guard !busy else { return }
        busy = true; download = nil; output = ""
        Task {
            defer { busy = false }
            do {
                try saveModelHome()
                guard let manifest = scriptDirectory?.appendingPathComponent("model_downloads.tsv") else { throw ModelRemovalError.cannotCheck }
                let plan = try ModelRemovalPlan(home: URL(fileURLWithPath: modelHome), files: ModelDownloadFile.load(manifest))
                guard !plan.relativePaths.isEmpty else { output = "没有可删除的模型。"; return }
                try await plan.checkNotInUse()
                removal = plan
            } catch { output = error.localizedDescription }
        }
    }
    func removeModels(_ plan: ModelRemovalPlan) {
        guard !busy else { return }
        busy = true; download = nil; removal = nil; output = "正在移到废纸篓…"
        Task {
            defer { busy = false }
            do {
                _ = try await plan.moveToTrash()
                output = "模型已移到废纸篓。运行时和作业已保留。"
            } catch { output = error.localizedDescription }
        }
    }
    func run(_ name: String, store: WorkspaceStore) {
        guard !busy else { return }
        guard let script = scriptDirectory?.appendingPathComponent(name),
              FileManager.default.fileExists(atPath: script.path) else { output = "未找到模型管理脚本。请使用项目的 build_and_run.sh 构建完整应用。"; return }
        do { try saveModelHome() } catch { output = error.localizedDescription; return }
        let downloading = name == "setup_models_modelscope.sh"
        if downloading {
            do {
                let files = try ModelDownloadFile.load(script.deletingLastPathComponent().appendingPathComponent("model_downloads.tsv"))
                download = ModelDownloadProgress(files: files, home: URL(fileURLWithPath: modelHome), now: ProcessInfo.processInfo.systemUptime)
            } catch { download = nil; output = error.localizedDescription; return }
        } else { download = nil }
        busy = true
        switch name {
        case "setup_models_modelscope.sh": output = "正在下载模型，支持断点续传…"
        case "start_models.sh": output = "正在启动本机模型…"
        default: output = "正在停止本项目的模型…"
        }
        let home = modelHome
        Task {
            let polling = downloading ? Task {
                while !Task.isCancelled {
                    download?.refresh(now: ProcessInfo.processInfo.systemUptime)
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                }
            } : nil
            defer { polling?.cancel(); busy = false }
            do {
                let result = try await Self.execute(script: script, home: home) { [weak self] line in
                    await self?.receive(line)
                }
                output = result
                polling?.cancel()
                if downloading {
                    download?.refresh(now: ProcessInfo.processInfo.systemUptime)
                    download?.finish()
                }
                // The startup script now waits for each model's health response.
                // Also check the user's configured endpoints, which can differ.
                await store.checkModels()
                if name == "start_models.sh" && !store.allModelsReady { output += "\n当前设置的服务地址未全部连接，请检查高级设置。" }
            } catch {
                polling?.cancel()
                output = error.localizedDescription
                if downloading {
                    download?.refresh(now: ProcessInfo.processInfo.systemUptime)
                    download?.finish(error: error.localizedDescription)
                }
                await store.checkModels()
            }
        }
    }
    private func receive(_ line: String) {
        if let event = ModelDownloadEvent(line) { download?.apply(event) }
        else { output = String((output + "\n" + line).suffix(16_000)) }
    }
    @concurrent private static func execute(script: URL, home: String,
        onLine: @Sendable (String) async -> Void) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        var env = ProcessInfo.processInfo.environment; env["PAPERREVIEW_MODEL_HOME"] = home
        process.environment = env
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        var pending = Data(), lines: [String] = []
        while true {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            pending.append(data)
            while let newline = pending.firstIndex(of: 10) {
                let line = String(decoding: pending[..<newline], as: UTF8.self)
                pending.removeSubrange(...newline)
                await onLine(line)
                if ModelDownloadEvent(line) == nil { lines.append(line) }
            }
        }
        if !pending.isEmpty {
            let line = String(decoding: pending, as: UTF8.self)
            await onLine(line); lines.append(line)
        }
        process.waitUntilExit()
        let text = String(lines.joined(separator: "\n").suffix(16_000))
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "PaperReview.ModelControl", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: text])
        }
        return text
    }
}
