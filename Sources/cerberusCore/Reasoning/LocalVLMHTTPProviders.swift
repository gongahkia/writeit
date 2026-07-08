import Foundation

public struct OllamaVLMProvider: LocalVLMProviding {
    public let providerName = "Ollama"
    public let modelID: String
    public let endpointURL: URL
    private let transport: any LocalVLMHTTPTransport

    public init(
        modelID: String,
        endpointURL: URL,
        transport: any LocalVLMHTTPTransport = URLSessionLocalVLMHTTPTransport()
    ) {
        self.modelID = modelID
        self.endpointURL = endpointURL
        self.transport = transport
    }

    public func answer(
        imageURL: URL,
        prompt: String,
        options: LocalVLMRequestOptions
    ) async throws -> LocalVLMResponse {
        let imageData = try Data(contentsOf: imageURL).base64EncodedString()
        let requestBody = OllamaGenerateRequest(
            model: modelID,
            prompt: prompt,
            images: [imageData],
            stream: false,
            options: OllamaGenerateOptions(numPredict: options.maxTokens)
        )
        let data = try await transport.postJSON(
            body: JSONEncoder().encode(requestBody),
            to: generateURL(),
            timeoutSeconds: options.timeoutSeconds
        )
        let response = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        if let error = response.error, !error.isEmpty {
            throw ToolExecutionError.denied(error)
        }
        let text = (response.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ToolExecutionError.denied("Ollama returned no response text.")
        }
        return LocalVLMResponse(
            text: text,
            metadata: [
                "provider": providerName,
                "modelID": modelID
            ]
        )
    }

    private func generateURL() -> URL {
        let path = endpointURL.path
        if path.hasSuffix("/api/generate") {
            return endpointURL
        }
        if path.hasSuffix("/api") {
            return endpointURL.appendingPathComponent("generate")
        }
        return endpointURL
            .appendingPathComponent("api")
            .appendingPathComponent("generate")
    }
}

public struct OpenAICompatibleVLMProvider: LocalVLMProviding {
    public let providerName: String
    public let modelID: String
    public let endpointURL: URL
    private let transport: any LocalVLMHTTPTransport

    public init(
        providerName: String,
        modelID: String,
        endpointURL: URL,
        transport: any LocalVLMHTTPTransport = URLSessionLocalVLMHTTPTransport()
    ) {
        self.providerName = providerName
        self.modelID = modelID
        self.endpointURL = endpointURL
        self.transport = transport
    }

    public func answer(
        imageURL: URL,
        prompt: String,
        options: LocalVLMRequestOptions
    ) async throws -> LocalVLMResponse {
        let imageData = try Data(contentsOf: imageURL).base64EncodedString()
        let requestBody = OpenAIChatRequest(
            model: modelID,
            messages: [
                OpenAIChatMessage(
                    role: "user",
                    content: [
                        OpenAIChatContent(type: "text", text: prompt, imageURL: nil),
                        OpenAIChatContent(
                            type: "image_url",
                            text: nil,
                            imageURL: OpenAIImageURL(url: "data:image/png;base64,\(imageData)")
                        )
                    ]
                )
            ],
            maxTokens: options.maxTokens,
            stream: false
        )
        let data = try await transport.postJSON(
            body: JSONEncoder().encode(requestBody),
            to: chatCompletionsURL(),
            timeoutSeconds: options.timeoutSeconds
        )
        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        let text = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw ToolExecutionError.denied("\(providerName) returned no response text.")
        }
        return LocalVLMResponse(
            text: text,
            metadata: [
                "provider": providerName,
                "modelID": modelID
            ]
        )
    }

    private func chatCompletionsURL() -> URL {
        let path = endpointURL.path
        if path.hasSuffix("/v1/chat/completions") {
            return endpointURL
        }
        if path.hasSuffix("/v1") {
            return endpointURL
                .appendingPathComponent("chat")
                .appendingPathComponent("completions")
        }
        return endpointURL
            .appendingPathComponent("v1")
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }
}

public protocol LocalVLMHTTPTransport: Sendable {
    func postJSON(
        body: Data,
        to url: URL,
        timeoutSeconds: Double
    ) async throws -> Data
}

public struct URLSessionLocalVLMHTTPTransport: LocalVLMHTTPTransport {
    public init() {}

    public func postJSON(
        body: Data,
        to url: URL,
        timeoutSeconds: Double
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = max(1, timeoutSeconds)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolExecutionError.denied("Local VLM endpoint returned a non-HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ToolExecutionError.denied("Local VLM endpoint returned HTTP \(httpResponse.statusCode): \(body)")
        }
        return data
    }
}

private struct OllamaGenerateOptions: Encodable {
    let numPredict: Int

    enum CodingKeys: String, CodingKey {
        case numPredict = "num_predict"
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let images: [String]
    let stream: Bool
    let options: OllamaGenerateOptions
}

private struct OllamaGenerateResponse: Decodable {
    let response: String?
    let error: String?
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct OpenAIChatMessage: Encodable {
    let role: String
    let content: [OpenAIChatContent]
}

private struct OpenAIChatContent: Encodable {
    let type: String
    let text: String?
    let imageURL: OpenAIImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct OpenAIImageURL: Encodable {
    let url: String
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}
