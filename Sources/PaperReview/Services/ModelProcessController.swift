import Foundation
import Observation

@Observable final class ModelProcessController {
    var busy = false
    var output = ""
    var modelHome: String
    init() {
        let project = Bundle.main.object(forInfoDictionaryKey: "PaperReviewProjectRoot") as? String ?? ""
        modelHome = UserDefaults.standard.string(forKey: "modelHome") ?? (project.isEmpty ? "" : project + "/.local-models")
    }
    func run(_ name: String, store: WorkspaceStore) {
        guard !busy else { return }
        guard !modelHome.isEmpty, let script = Bundle.main.resourceURL?.appendingPathComponent(name),
              FileManager.default.fileExists(atPath: script.path) else { output = "未找到模型管理脚本。请使用项目的 build_and_run.sh 构建完整应用。"; return }
        busy = true; output = name == "start_models.sh" ? "正在启动本机模型…" : "正在停止本项目的模型…"
        UserDefaults.standard.set(modelHome, forKey: "modelHome")
        let home = modelHome
        Task {
            do {
                output = try await Self.execute(script: script, home: home)
                // The startup script now waits for each model's health response.
                // Also check the user's configured endpoints, which can differ.
                await store.checkModels()
                if name == "start_models.sh" && !store.allModelsReady { output += "\n当前设置的服务地址未全部连接，请检查高级设置。" }
            } catch {
                output = error.localizedDescription
                await store.checkModels()
            }
            busy = false
        }
    }
    @concurrent private static func execute(script: URL, home: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment; env["PAPERREVIEW_MODEL_HOME"] = home
        process.environment = env
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "PaperReview.ModelControl", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: text])
        }
        return text
    }
}
