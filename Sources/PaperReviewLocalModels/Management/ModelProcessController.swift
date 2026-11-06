import Foundation
import Observation

@MainActor @Observable final class ModelProcessController {
    var busy = false
    var output = ""
    var showsCommandOutput = false
    var download: ModelDownloadProgress?
    var removal: ModelRemovalPlan?
    var modelHome: String {
        didSet { if modelHome != oldValue && !busy { removal = nil; output = ""; restoreDownload() } }
    }
    private let scriptDirectory: URL?
    private let checkpoint: DownloadCheckpointStore
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var control: DownloadControl?
    @ObservationIgnored private var pauseRequested = false
    @ObservationIgnored private var checkpointIssue: String?
    var isDownloadActive: Bool { control != nil }
    init(modelHome: String? = nil, scriptDirectory: URL? = Bundle.main.resourceURL, checkpointURL: URL? = nil) {
        let project = Bundle.main.object(forInfoDictionaryKey: "PaperReviewProjectRoot") as? String ?? ""
        self.modelHome = modelHome ?? UserDefaults.standard.string(forKey: "modelHome") ?? Self.defaultModelHome(projectRoot: project)
        self.scriptDirectory = scriptDirectory
        self.checkpoint = checkpointURL.map { DownloadCheckpointStore(url: $0) } ?? .applicationDefault
        restoreDownload()
    }
    private func restoreDownload() {
        download = nil
        do {
            guard let saved = try checkpoint.load(), saved.state != "complete",
                  saved.home == URL(fileURLWithPath: modelHome).standardizedFileURL.path,
                  let manifest = scriptDirectory?.appendingPathComponent("model_downloads.tsv") else { return }
            download = ModelDownloadProgress(files: try ModelDownloadFile.load(manifest),
                home: URL(fileURLWithPath: modelHome), checkpoint: saved, now: ProcessInfo.processInfo.systemUptime)
        } catch {
            showsCommandOutput = true
            output = "无法读取下载记录。点击“下载模型”仍可继续已有临时文件：\(error.localizedDescription)"
        }
    }
    private func saveDownload() throws {
        if let download { try checkpoint.save(download) }
    }
    private func stopDownload() {
        guard let control else { return }
        pauseRequested = true
        download?.beginPausing()
        control.stop()
    }
    func pauseDownload() {
        stopDownload()
        do { try saveDownload() }
        catch { checkpointIssue = error.localizedDescription }
    }
    func pauseForTermination() async {
        guard isDownloadActive else { return }
        pauseDownload()
        await operation?.value
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
    func installationStatuses() -> [String: String] {
        guard let manifest = scriptDirectory?.appendingPathComponent("model_downloads.tsv"),
              let files = try? ModelDownloadFile.load(manifest) else { return [:] }
        var result: [String: String] = [:]
        for id in ["ocr", "jev", "review"] {
            let required = files.filter { $0.id == id || $0.id == id + "-projector" }
            var state = "已安装，未运行"
            for file in required {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: URL(fileURLWithPath: modelHome).appendingPathComponent(file.relativePath).path)
                    if (attributes[.size] as? NSNumber)?.int64Value != file.bytes { state = "安装未完成"; break }
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                    state = "未安装"; break
                } catch { state = "无法检查文件"; break }
            }
            result[id] = state
        }
        return result
    }

    func prepareRemoval() {
        guard !busy else { return }
        busy = true; showsCommandOutput = true; output = ""
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
        busy = true; showsCommandOutput = true; removal = nil; output = "正在移到废纸篓…"
        Task {
            defer { busy = false }
            do {
                _ = try await plan.moveToTrash()
                download = nil
                try checkpoint.clear(home: plan.home)
                output = "模型已移到废纸篓。运行时和作业已保留。"
            } catch { output = error.localizedDescription }
        }
    }
    func run(_ name: String, refreshReadiness: @escaping @MainActor () async -> Bool) {
        guard !busy else { return }
        guard let script = scriptDirectory?.appendingPathComponent(name),
              FileManager.default.fileExists(atPath: script.path) else {
            showsCommandOutput = true
            output = "未找到模型管理脚本。请使用项目的 build_and_run.sh 构建完整应用。"; return
        }
        do { try saveModelHome() } catch { showsCommandOutput = true; output = error.localizedDescription; return }
        let downloading = name == "setup_models_modelscope.sh"
        showsCommandOutput = !downloading
        if downloading {
            do {
                let files = try ModelDownloadFile.load(script.deletingLastPathComponent().appendingPathComponent("model_downloads.tsv"))
                download = ModelDownloadProgress(files: files, home: URL(fileURLWithPath: modelHome), now: ProcessInfo.processInfo.systemUptime)
                try saveDownload()
            } catch {
                download?.finish(error: "无法保存下载记录：\(error.localizedDescription)")
                showsCommandOutput = download == nil
                output = error.localizedDescription; return
            }
        } else if download?.phase == .complete { download = nil }
        busy = true
        switch name {
        case "setup_models_modelscope.sh": output = "正在下载模型，支持断点续传…"
        case "start_models.sh": output = "正在启动本机模型…"
        default: output = "正在停止本项目的模型…"
        }
        let home = modelHome
        let session = downloading ? DownloadControl() : nil
        control = session; pauseRequested = false; checkpointIssue = nil
        operation = Task {
            let polling = downloading ? Task {
                var lastSave = ProcessInfo.processInfo.systemUptime
                while !Task.isCancelled {
                    let now = ProcessInfo.processInfo.systemUptime
                    download?.refresh(now: now)
                    if now - lastSave >= 2 {
                        do { try saveDownload() }
                        catch { checkpointIssue = error.localizedDescription; stopDownload() }
                        lastSave = now
                    }
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                }
            } : nil
            defer {
                polling?.cancel(); control = nil; operation = nil; busy = false
                if downloading {
                    do { try saveDownload() }
                    catch { showsCommandOutput = true; output = "下载文件已保留，但无法保存恢复记录：\(error.localizedDescription)" }
                }
            }
            do {
                let result = try await ModelCommandRunner.execute(script: script, home: home, control: session) { [weak self] line in
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
                if !downloading {
                    let ready = await refreshReadiness()
                    if name == "start_models.sh" && !ready { output += "\n当前设置的服务地址未全部连接，请检查高级设置。" }
                }
            } catch {
                polling?.cancel()
                output = error.localizedDescription
                if downloading {
                    download?.refresh(now: ProcessInfo.processInfo.systemUptime)
                    if let checkpointIssue { download?.finish(error: "无法保存下载记录：\(checkpointIssue)") }
                    else if pauseRequested { download?.pause(); output = "" }
                    else { download?.finish(error: error.localizedDescription) }
                }
                if !downloading { _ = await refreshReadiness() }
            }
        }
    }
    private func receive(_ line: String) {
        if line.hasPrefix("PR_DOWNLOAD_SESSION\t") { return }
        if let event = ModelDownloadEvent(line) { download?.apply(event) }
        else { output = String((output + "\n" + line).suffix(16_000)) }
    }
}
