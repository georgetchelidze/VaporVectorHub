import Vapor

extension VectorHub {
    public enum LLM {
        public struct Request: Codable, Sendable {
            public let text: String
            public let instruction: String
            public let maxNewTokens: Int
            public let autoLength: Bool
            public let temperature: Double
            public let topP: Double

            public init(
                text: String,
                instruction: String = "Rewrite the text for clarity and concision.",
                maxNewTokens: Int = 240,
                autoLength: Bool = true,
                temperature: Double = 0.2,
                topP: Double = 0.9
            ) {
                self.text = text
                self.instruction = instruction
                self.maxNewTokens = maxNewTokens
                self.autoLength = autoLength
                self.temperature = temperature
                self.topP = topP
            }
        }

        public struct Response: Codable, Sendable {
            public let text: String
            public let model: String

            public init(text: String, model: String) {
                self.text = text
                self.model = model
            }
        }

        public static func humanize(
            _ request: Request,
            on app: Application
        ) async throws -> Response {
            try await app.vectorHub.humanize(request, on: app)
        }
    }
}

extension VectorHub.HTTPClient {
    public func humanize(
        _ request: VectorHub.LLM.Request,
        on app: Application
    ) async throws -> VectorHub.LLM.Response {
        let normalizedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInstruction = request.instruction.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !normalizedText.isEmpty else {
            throw Abort(.badRequest, reason: "VectorHub humanize requires non-empty text")
        }
        guard !normalizedInstruction.isEmpty else {
            throw Abort(.badRequest, reason: "VectorHub humanize requires non-empty instruction")
        }

        struct RequestBody: Content {
            let text: String
            let instruction: String
            let max_new_tokens: Int
            let auto_length: Bool
            let temperature: Double
            let top_p: Double
        }

        struct ResponseBody: Content {
            let rewritten_text: String
            let model: String
        }

        let uri = URI(string: "\(Self.resolveBaseURL())/rewrite/unslopper")
        let requestBody = RequestBody(
            text: normalizedText,
            instruction: normalizedInstruction,
            max_new_tokens: min(max(request.maxNewTokens, 1), 2048),
            auto_length: request.autoLength,
            temperature: min(max(request.temperature, 0.0), 2.0),
            top_p: min(max(request.topP, 0.0), 1.0)
        )

        let apiKey = try Self.resolveAPIKey()
        let response = try await app.client.post(uri) { req in
            req.headers.add(name: .init("x-api-key"), value: apiKey)
            req.headers.bearerAuthorization = .init(token: apiKey)
            try req.content.encode(requestBody)
        }

        guard response.status == HTTPResponseStatus.ok else {
            let body = response.body.flatMap { String(buffer: $0) } ?? ""
            throw Abort(
                response.status,
                reason: "VectorHub humanize service error: \(response.status.code) \(body)"
            )
        }

        let decoded = try response.content.decode(ResponseBody.self)
        return VectorHub.LLM.Response(text: decoded.rewritten_text, model: decoded.model)
    }
}
