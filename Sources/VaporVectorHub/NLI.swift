import Vapor

extension VectorHub {
    public enum NLI {
        public enum Mode: String, Codable, Sendable {
            case pairwise
            case cross
        }

        public struct Request: Codable, Sendable {
            public let premises: [String]
            public let hypotheses: [String]
            public let mode: Mode?
            public let batchSize: Int?
            public let maxLength: Int?

            public init(
                premises: [String],
                hypotheses: [String],
                mode: Mode? = nil,
                batchSize: Int? = nil,
                maxLength: Int? = nil
            ) {
                self.premises = premises
                self.hypotheses = hypotheses
                self.mode = mode
                self.batchSize = batchSize
                self.maxLength = maxLength
            }
        }

        public struct Result: Codable, Sendable {
            public let premise: String
            public let hypothesis: String
            public let score: Double

            public init(premise: String, hypothesis: String, score: Double) {
                self.premise = premise
                self.hypothesis = hypothesis
                self.score = score
            }
        }

        public struct Response: Codable, Sendable {
            public let modelTask: String
            public let count: Int
            public let results: [Result]

            public init(modelTask: String, count: Int, results: [Result]) {
                self.modelTask = modelTask
                self.count = count
                self.results = results
            }

            private enum CodingKeys: String, CodingKey {
                case modelTask = "model_task"
                case count
                case results
            }
        }

        public static func predict(
            _ request: Request,
            on app: Application
        ) async throws -> Response {
            try await app.vectorHub.predictNLI(request, on: app)
        }
    }
}

extension VectorHub.HTTPClient {
    public func predictNLI(
        _ request: VectorHub.NLI.Request,
        on app: Application
    ) async throws -> VectorHub.NLI.Response {
        let normalizedPremises = request.premises
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalizedHypotheses = request.hypotheses
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedPremises.isEmpty else {
            throw Abort(.badRequest, reason: "VectorHub NLI requires at least one premise")
        }
        guard !normalizedHypotheses.isEmpty else {
            throw Abort(.badRequest, reason: "VectorHub NLI requires at least one hypothesis")
        }

        struct RequestBody: Content {
            let premises: [String]
            let hypotheses: [String]
            let mode: String?
            let batch_size: Int?
            let max_length: Int?
        }

        struct ResponseBody: Content {
            struct Item: Content {
                let premise: String
                let hypothesis: String
                let score: Double
            }

            let model_task: String
            let count: Int
            let results: [Item]
        }

        let uri = URI(string: "\(Self.resolveBaseURL())/nli/batch")
        let requestBody = RequestBody(
            premises: normalizedPremises,
            hypotheses: normalizedHypotheses,
            mode: request.mode?.rawValue,
            batch_size: request.batchSize.map { min(max($0, 1), 256) },
            max_length: request.maxLength.map { min(max($0, 8), 4096) }
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
                reason: "VectorHub NLI service error: \(response.status.code) \(body)"
            )
        }

        let decoded = try response.content.decode(ResponseBody.self)
        return VectorHub.NLI.Response(
            modelTask: decoded.model_task,
            count: decoded.count,
            results: decoded.results.map {
                VectorHub.NLI.Result(
                    premise: $0.premise,
                    hypothesis: $0.hypothesis,
                    score: $0.score
                )
            }
        )
    }
}
