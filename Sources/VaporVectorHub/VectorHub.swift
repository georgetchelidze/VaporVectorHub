import Foundation
import Vapor

public enum VectorHub {
    public protocol Client: Sendable {
        func predictNLI(
            _ request: NLI.Request,
            on app: Application
        ) async throws -> NLI.Response
        func humanize(
            _ request: LLM.Request,
            on app: Application
        ) async throws -> LLM.Response
    }

    public struct HTTPClient: Client {
        public init() {}
    }
}

extension VectorHub.HTTPClient {
    static func resolveBaseURL() -> String {
        let configured = Environment.get("VECTORHUB_API_BASE_URL")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "https://api.vectorhub.xyz"
    }

    static func resolveAPIKey() throws -> String {
        let configured = Environment.get("VECTORHUB_API_KEY")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        throw Abort(.internalServerError, reason: "VECTORHUB_API_KEY not configured")
    }
}

extension Application {
    private struct VectorHubClientKey: StorageKey {
        typealias Value = any VectorHub.Client
    }

    public var vectorHub: any VectorHub.Client {
        get {
            guard let value = self.storage[VectorHubClientKey.self] else {
                fatalError(
                    "VectorHub client not configured. Assign Application.vectorHub during boot.")
            }
            return value
        }
        set {
            self.storage[VectorHubClientKey.self] = newValue
        }
    }
}
