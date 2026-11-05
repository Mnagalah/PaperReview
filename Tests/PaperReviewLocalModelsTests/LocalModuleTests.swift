import Foundation
import Testing
import PaperReviewCore
@testable import PaperReviewLocalModels

@Test @MainActor func localModulePreservesSavedSettingsAndFreezesEachAssignmentBinding() throws {
    let suite = "PaperReview-module-\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    var old = ModelConfiguration()
    old.ocrURL = "http://127.0.0.1:19001"; old.threshold = 0.43; old.maximumAttempts = 2
    preferences.set(try JSONEncoder().encode(old), forKey: "modelConfiguration")
    let controller = ModelProcessController(modelHome: "/tmp/PaperReview-no-download", checkpointURL: URL(fileURLWithPath: "/tmp/\(suite).json"))
    let module = LocalModelModule(preferences: preferences, controller: controller)
    let session = try module.makeSession()
    #expect(module.configuration == old)
    #expect(session.policy.threshold == 0.43 && session.policy.maximumAttempts == 2)
    #expect(module.readiness.required == [.ocr, .jev, .review])
    #expect(!module.readiness.isReady && !module.needsTerminationPreparation)
    var new = old; new.ocrURL = "http://127.0.0.1:19011"; new.threshold = 0.61
    try module.saveConfiguration(new)
    let next = try module.makeSession()
    #expect(session.recognitionIdentity != next.recognitionIdentity)
    #expect(session.policy.threshold == 0.43 && next.policy.threshold == 0.61)
    #expect(session.verificationIdentity == next.verificationIdentity)
    #expect(try JSONDecoder().decode(ModelConfiguration.self, from: #require(preferences.data(forKey: "modelConfiguration"))) == new)
    var invalid = new; invalid.ocrURL = "https://example.invalid"
    #expect(throws: ModelError.self) { try module.saveConfiguration(invalid) }
    #expect(module.configuration == new)
    #expect(!controller.busy && controller.download == nil)
}

@Test @MainActor func localReadinessRequiresJevAndDoesNotChangeTheSavedEndpoints() async throws {
    let suite = "PaperReview-health-\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let controller = ModelProcessController(modelHome: "/tmp/PaperReview-no-download", checkpointURL: URL(fileURLWithPath: "/tmp/\(suite).json"))
    let module = LocalModelModule(preferences: preferences, controller: controller, client: fixtureClient())
    var config = ModelConfiguration()
    config.ocrURL = "http://127.0.0.1:19001"; config.jevURL = "http://127.0.0.1:19002"; config.reviewURL = "http://127.0.0.1:19003"
    try module.saveConfiguration(config)
    await module.checkReadiness()
    #expect(module.readiness.available == [.ocr, .review])
    #expect(!module.readiness.isReady)
    config.jevURL = "http://127.0.0.1:19003"
    try module.saveConfiguration(config)
    await module.checkReadiness()
    #expect(module.readiness.isReady)
    await module.prepareForTermination()
    #expect(module.configuration == config && !controller.busy)
}

@Test func localSessionKeepsLiteralSpellingAndTheNativeJevRequestContract() async throws {
    var config = ModelConfiguration()
    config.ocrURL = "http://127.0.0.1:19001"; config.jevURL = "http://127.0.0.1:19003"
    let session = LocalModelSession(configuration: config, client: fixtureClient())
    let response = try await session.recognize(image: Data([1, 2, 3]))
    #expect(response.text == "The wether is suny.\nI feeled happy.")
    #expect(!response.truncated)
    #expect(try await session.score(original: Data([1]), rendered: Data([2]), text: response.text) == 0.75)
    config.ocrURL = "http://127.0.0.1:19004"; config.jevURL = "http://127.0.0.1:19005"
    let failing = LocalModelSession(configuration: config, client: fixtureClient())
    #expect(try await failing.recognize(image: Data([1, 2, 3])).truncated)
    await #expect(throws: ModelError.self) { try await failing.score(original: Data([1]), rendered: Data([2]), text: response.text) }
    let cancelled = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await session.recognize(image: Data([1, 2, 3]))
    }
    do { _ = try await cancelled.value; Issue.record("A cancelled reading must not be returned") }
    catch is CancellationError {}
}

private func fixtureClient() -> ModelClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LocalFixtureProtocol.self]
    return ModelClient(session: URLSession(configuration: configuration))
}

private final class LocalFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        var status = 200
        var value: [String: Any] = [:]
        if url.path == "/health" {
            status = url.port == 19002 ? 503 : 200
            value = ["status": status == 200 ? "ok" : "loading"]
        } else {
            let data = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
                stream.open(); defer { stream.close() }
                var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count))
                }
                return data
            } ?? Data()
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if url.path == "/v1/chat/completions" {
                let messages = body["messages"] as? [[String: Any]]
                let content = messages?.first?["content"] as? [[String: Any]]
                guard request.httpMethod == "POST", body["model"] as? String == "minicpm-ocr",
                      content?.last?["text"] as? String == "Text Recognition:",
                      (content?.first?["image_url"] as? [String: String])?["url"] == "data:image/png;base64,AQID",
                      body["temperature"] as? Double == 0.01 else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
                }
                value = ["choices": [["message": ["content": "The wether is suny.\r\nI feeled happy."],
                    "finish_reason": url.port == 19004 ? "length" : "stop"]]]
            } else if url.path == "/v1/systemone" {
                guard body["files"] as? [String] == ["data:image/png;base64,AQ==", "data:image/png;base64,Ag=="],
                      body["state"] as? String == "The wether is suny.\nI feeled happy." else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
                }
                value = ["answers": ["consistency": ["probabilities": ["0": 0.25, "1": url.port == 19005 ? -1.0 : 0.75]]]]
            } else { status = 404 }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: value)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
