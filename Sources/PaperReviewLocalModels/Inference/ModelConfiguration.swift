import Foundation
import PaperReviewCore

public struct ModelConfiguration: Codable, Equatable, Sendable {
    public var ocrURL: String = "http://127.0.0.1:18499"
    public var jevURL: String = "http://127.0.0.1:18500"
    public var reviewURL: String = "http://127.0.0.1:18501"
    /// An experimental retry trigger, not a calibrated accuracy guarantee.
    public var threshold: Double = 0.50
    public var maximumAttempts: Int = 3
    public init() {}
    public func validate() throws {
        for url in [ocrURL, jevURL, reviewURL] { _ = try LocalEndpoint.base(url) }
        guard QualityGate.validScore(threshold), (1...3).contains(maximumAttempts) else {
            throw ModelError.invalidConfiguration
        }
    }
}

public enum LocalEndpoint {
    public static func base(_ value: String) throws -> URL {
        guard let parts = URLComponents(string: value), parts.scheme == "http",
              let host = parts.host, ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host.lowercased()),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let url = parts.url else {
            throw ModelError.localOnly
        }
        return url
    }
}
