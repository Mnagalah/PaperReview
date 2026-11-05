import Foundation
import Observation
import PaperReviewCore

@MainActor @Observable public final class LocalModelModule: ModelModule {
    public private(set) var configuration: ModelConfiguration
    public private(set) var readiness = ModelReadiness(required: Set(ModelRole.allCases))
    let controller: ModelProcessController
    private let client: ModelClient
    private let preferences: UserDefaults
    public var policy: RecognitionPolicy { configuration.policy }
    public var needsTerminationPreparation: Bool { controller.isDownloadActive }

    public init() {
        preferences = .standard
        configuration = Self.loadConfiguration(from: .standard)
        controller = ModelProcessController()
        client = ModelClient()
    }

    init(preferences: UserDefaults, controller: ModelProcessController, client: ModelClient = ModelClient()) {
        self.preferences = preferences; self.controller = controller; self.client = client
        configuration = Self.loadConfiguration(from: preferences)
    }

    private static func loadConfiguration(from preferences: UserDefaults) -> ModelConfiguration {
        preferences.data(forKey: "modelConfiguration")
            .flatMap { try? JSONDecoder().decode(ModelConfiguration.self, from: $0) } ?? ModelConfiguration()
    }

    func saveConfiguration(_ value: ModelConfiguration) throws {
        try value.validate()
        preferences.set(try JSONEncoder().encode(value), forKey: "modelConfiguration")
        if configuration != value { readiness = ModelReadiness(required: Set(ModelRole.allCases)) }
        configuration = value
    }

    public func makeSession() throws -> any ModelSession {
        try configuration.validate()
        return LocalModelSession(configuration: configuration, client: client)
    }

    public func checkReadiness() async {
        let checked = configuration
        async let ocr = client.health(checked.ocrURL)
        async let jev = client.health(checked.jevURL)
        async let review = client.health(checked.reviewURL)
        let values = await [ocr, jev, review]
        guard configuration == checked else { return }
        readiness = ModelReadiness(required: Set(ModelRole.allCases),
            available: Set(zip([ModelRole.ocr, .jev, .review], values).filter(\.1).map(\.0)))
    }

    func run(_ action: LocalModelAction) {
        controller.run(action.script) { [weak self] in
            guard let self else { return false }
            await checkReadiness()
            return readiness.isReady
        }
    }

    public func prepareForTermination() async {
        // Model services intentionally outlive the window in the local edition.
        await controller.pauseForTermination()
    }
}

enum LocalModelAction {
    case download, start, stop
    var script: String {
        switch self {
        case .download: "setup_models_modelscope.sh"
        case .start: "start_models.sh"
        case .stop: "stop_models.sh"
        }
    }
}

extension ModelConfiguration {
    var policy: RecognitionPolicy { RecognitionPolicy(threshold: threshold, maximumAttempts: maximumAttempts) }
}

struct LocalModelSession: ModelSession {
    let configuration: ModelConfiguration
    let client: ModelClient
    var policy: RecognitionPolicy { configuration.policy }
    var recognitionIdentity: String { "ocr-f16-59e3a326:\(configuration.ocrURL)" }
    var verificationIdentity: String { "jev-q4:\(configuration.jevURL)" }
    func recognize(image: Data) async throws -> OCRResponse {
        try await client.recognize(image: image, base: configuration.ocrURL)
    }
    func score(original: Data, rendered: Data, text: String) async throws -> Double {
        try await client.score(original: original, rendered: rendered, text: text, base: configuration.jevURL)
    }
    func review(transcript: Transcript) async throws -> ReviewResult {
        try await client.review(transcript: transcript, base: configuration.reviewURL)
    }
}
