import Foundation

public enum ModelRole: CaseIterable, Sendable { case ocr, jev, review }

/// Availability is distinct from which roles an edition requires.
public struct ModelReadiness: Equatable, Sendable {
    public let required: Set<ModelRole>
    public let available: Set<ModelRole>
    public var isReady: Bool { required.isSubset(of: available) }
    public func isReady(_ role: ModelRole) -> Bool { available.contains(role) }
    public init(required: Set<ModelRole>, available: Set<ModelRole> = []) {
        self.required = required; self.available = available
    }
}

public struct RecognitionPolicy: Sendable {
    public let threshold: Double
    public let maximumAttempts: Int
    public init(threshold: Double, maximumAttempts: Int) {
        self.threshold = threshold; self.maximumAttempts = maximumAttempts
    }
}

/// One immutable model binding for an entire assignment. Provider settings,
/// prompts and transport stay outside the shared assignment workflow.
public protocol ModelSession: Sendable {
    var policy: RecognitionPolicy { get }
    var recognitionIdentity: String { get }
    var verificationIdentity: String { get }
    func recognize(image: Data) async throws -> OCRResponse
    func score(original: Data, rendered: Data, text: String) async throws -> Double
    func review(transcript: Transcript) async throws -> ReviewResult
}

@MainActor public protocol ModelModule: AnyObject {
    var readiness: ModelReadiness { get }
    var policy: RecognitionPolicy { get }
    func makeSession() throws -> any ModelSession
    func checkReadiness() async
    var needsTerminationPreparation: Bool { get }
    func prepareForTermination() async
}
