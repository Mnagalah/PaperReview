import Foundation

nonisolated enum ModelCommandRunner {
    @concurrent static func execute(script: URL, home: String, control: DownloadControl? = nil,
        onLine: @Sendable (String) async -> Void) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        if let control {
            let input = Pipe()
            process.standardInput = input
            control.attach(input.fileHandleForWriting)
            process.arguments = [script.deletingLastPathComponent().appendingPathComponent("download_supervisor.sh").path, script.path]
        } else {
            process.standardInput = FileHandle.nullDevice
            process.arguments = [script.path]
        }
        defer { control?.stop() }
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
                if ModelDownloadEvent(line) == nil && !line.hasPrefix("PR_DOWNLOAD_SESSION\t") { lines.append(line) }
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
