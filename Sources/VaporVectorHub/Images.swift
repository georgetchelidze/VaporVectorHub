import Foundation
import Vapor

extension VectorHub {
    public enum Images {
        public enum OutputFormat: String, Codable, Sendable {
            case base64
            case png
            case jpeg
            case webp
        }

        public struct Request: Codable, Sendable {
            public let prompt: String
            public let width: Int
            public let height: Int
            public let numInferenceSteps: Int
            public let guidanceScale: Double
            public let seed: Int?
            public let outputFormat: OutputFormat
            public let outputQuality: Int?

            public init(
                prompt: String,
                width: Int = 1024,
                height: Int = 1024,
                numInferenceSteps: Int = 4,
                guidanceScale: Double = 1.0,
                seed: Int? = nil,
                outputFormat: OutputFormat = .base64,
                outputQuality: Int? = nil
            ) {
                self.prompt = prompt
                self.width = width
                self.height = height
                self.numInferenceSteps = numInferenceSteps
                self.guidanceScale = guidanceScale
                self.seed = seed
                self.outputFormat = outputFormat
                self.outputQuality = outputQuality
            }
        }

        public struct Response: Sendable {
            public let data: Data
            public let mimeType: String
            public let model: String
            public let seed: Int
            public let format: OutputFormat

            public init(
                data: Data,
                mimeType: String,
                model: String,
                seed: Int,
                format: OutputFormat
            ) {
                self.data = data
                self.mimeType = mimeType
                self.model = model
                self.seed = seed
                self.format = format
            }

            public var base64String: String {
                data.base64EncodedString()
            }
        }

        public static func generate(
            _ request: Request,
            on app: Application
        ) async throws -> Response {
            try await app.vectorHub.generateImage(request, on: app)
        }
    }
}

extension VectorHub.HTTPClient {
    public func generateImage(
        _ request: VectorHub.Images.Request,
        on app: Application
    ) async throws -> VectorHub.Images.Response {
        let normalizedPrompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else {
            throw Abort(.badRequest, reason: "VectorHub image generation requires non-empty prompt")
        }

        struct RequestBody: Content {
            let prompt: String
            let width: Int
            let height: Int
            let num_inference_steps: Int
            let guidance_scale: Double
            let seed: Int?
            let output_format: String
            let output_quality: Int?
        }

        struct Base64ResponseBody: Content {
            let image_base64: String
            let mime_type: String
            let model: String
            let seed: Int
        }

        let uri = URI(string: "\(Self.resolveBaseURL())/images/generate")
        let requestBody = RequestBody(
            prompt: normalizedPrompt,
            width: min(max(request.width, 512), 1536),
            height: min(max(request.height, 512), 1536),
            num_inference_steps: min(max(request.numInferenceSteps, 1), 80),
            guidance_scale: min(max(request.guidanceScale, 0.0), 20.0),
            seed: request.seed.map { min(max($0, 0), Int(Int32.max)) },
            output_format: request.outputFormat.rawValue,
            output_quality: request.outputQuality.map { min(max($0, 1), 100) }
        )

        let apiKey = try Self.resolveAPIKey()
        let response = try await app.client.post(uri) { req in
            req.headers.add(name: .init("x-api-key"), value: apiKey)
            req.headers.bearerAuthorization = .init(token: apiKey)
            try req.content.encode(requestBody)
        }

        guard response.status == .ok else {
            let body = response.body.flatMap { String(buffer: $0) } ?? ""
            throw Abort(
                response.status,
                reason: "VectorHub image service error: \(response.status.code) \(body)"
            )
        }

        if request.outputFormat == .base64 {
            let decoded = try response.content.decode(Base64ResponseBody.self)
            guard let data = Data(base64Encoded: decoded.image_base64) else {
                throw Abort(
                    .internalServerError, reason: "VectorHub image service returned invalid base64")
            }

            return VectorHub.Images.Response(
                data: data,
                mimeType: decoded.mime_type,
                model: decoded.model,
                seed: decoded.seed,
                format: .base64
            )
        }

        guard let buffer = response.body else {
            throw Abort(.internalServerError, reason: "VectorHub image service returned empty body")
        }

        let mimeType = response.headers.first(name: .contentType) ?? "application/octet-stream"
        let model = response.headers.first(name: "X-Image-Model") ?? ""
        let seedHeader = response.headers.first(name: "X-Image-Seed") ?? ""
        guard let seed = Int(seedHeader) else {
            throw Abort(
                .internalServerError, reason: "VectorHub image service returned invalid seed header"
            )
        }

        return VectorHub.Images.Response(
            data: Data(buffer: buffer),
            mimeType: mimeType,
            model: model,
            seed: seed,
            format: request.outputFormat
        )
    }
}
