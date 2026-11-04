import Foundation

// The stream reader and the main actor share only this synchronized writer.
// EOF is the supervisor's stop signal; no application or model PID is killed.
nonisolated final class DownloadControl: @unchecked Sendable {
    private let lock = NSLock()
    private var writer: FileHandle?
    private var stopped = false
    func attach(_ handle: FileHandle) {
        lock.lock()
        let shouldClose = stopped
        if !shouldClose { writer = handle }
        lock.unlock()
        if shouldClose { try? handle.close() }
    }
    func stop() {
        lock.lock()
        stopped = true
        let handle = writer
        writer = nil
        lock.unlock()
        try? handle?.close()
    }
    deinit { stop() }
}
