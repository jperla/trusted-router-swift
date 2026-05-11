import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension TrustedRouter {
    
    // ---- catalog / metadata ---------------------------------------------
    
    public func models() async throws -> DataList<ModelInfo> {
        return try await request(method: "GET", path: "/models")
    }
    
    public func providers() async throws -> DataList<ProviderInfo> {
        return try await request(method: "GET", path: "/providers")
    }
    
    public func regions() async throws -> DataList<RegionInfo> {
        return try await request(method: "GET", path: "/regions")
    }
    
    public func credits(workspaceId: String? = nil) async throws -> CreditsResponse {
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "GET", path: "/credits", options: options)
    }
    
    // ---- chat ------------------------------------------------------------
    
    /**
     * OpenAI-compatible chat completion. This method collects all chunks from the
     * gateway (which always streams) and returns a single ChatCompletion object.
     */
    public func chatCompletions(
        model: String = TrustedRouterConstants.autoModel,
        messages: [[String: Any]],
        options: PerCallOptions = PerCallOptions(),
        params: [String: Any] = [:]
    ) async throws -> ChatCompletion {
        let stream: AsyncThrowingStream<ChatCompletionChunk, Error> = try await chatCompletionsChunks(
            model: model,
            messages: messages,
            options: options,
            params: params
        )
        
        var chunks: [ChatCompletionChunk] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }
        return collectCompletion(chunks: chunks)
    }
    
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func chatCompletionsChunks(
        model: String = TrustedRouterConstants.autoModel,
        messages: [[String: Any]],
        options: PerCallOptions = PerCallOptions(),
        params: [String: Any] = [:]
    ) async throws -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        var body = params
        body["model"] = model
        body["messages"] = messages
        body["stream"] = true
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await rawStreamRequest(
            method: "POST",
            path: "/chat/completions",
            headers: ["accept": "text/event-stream"],
            body: bodyData,
            options: options
        )
        
        if response.statusCode >= 400 {
            throw TrustedRouterError.generic(statusCode: response.statusCode, message: "Error in stream response", payload: nil)
        }
        
        return iterSseEvents(response: response, bytes: bytes, type: ChatCompletionChunk.self)
    }

    /** Simple helper to yield only the text deltas from a chat completion stream. */
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func chatCompletionsText(
        model: String = TrustedRouterConstants.autoModel,
        messages: [[String: Any]],
        options: PerCallOptions = PerCallOptions(),
        params: [String: Any] = [:]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let chunks = try await chatCompletionsChunks(model: model, messages: messages, options: options, params: params)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in chunks {
                        if let content = chunk.choices.first?.delta?.content, !content.isEmpty {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // ---- other endpoints ---------------------------------------------
    
    public func embeddings(
        model: String,
        input: Any,
        encodingFormat: String? = nil,
        dimensions: Int? = nil,
        user: String? = nil,
        options: PerCallOptions = PerCallOptions()
    ) async throws -> EmbeddingResponse {
        var body: [String: Any] = ["model": model, "input": input]
        if let encodingFormat = encodingFormat { body["encoding_format"] = encodingFormat }
        if let dimensions = dimensions { body["dimensions"] = dimensions }
        if let user = user { body["user"] = user }
        
        return try await request(method: "POST", path: "/embeddings", body: body, options: options)
    }
    
    public func messages(
        model: String,
        messages: [[String: Any]],
        maxTokens: Int = 1024,
        options: PerCallOptions = PerCallOptions(),
        params: [String: Any] = [:]
    ) async throws -> MessageResponse {
        var body = params
        body["model"] = model
        body["messages"] = messages
        body["max_tokens"] = maxTokens
        
        return try await request(method: "POST", path: "/messages", body: body, options: options)
    }
    
    public func responses(
        model: String = TrustedRouterConstants.autoModel,
        input: Any,
        instructions: String? = nil,
        options: PerCallOptions = PerCallOptions(),
        params: [String: Any] = [:]
    ) async throws -> ResponseObject {
        var body = params
        body["model"] = model
        body["input"] = input
        body["stream"] = false
        if let instructions = instructions {
            body["instructions"] = instructions
        }
        
        return try await request(method: "POST", path: "/responses", body: body, options: options)
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func responsesEvents(
        model: String = TrustedRouterConstants.autoModel,
        input: Any,
        instructions: String? = nil,
        options: PerCallOptions = PerCallOptions(),
        params: [String: Any] = [:]
    ) async throws -> AsyncThrowingStream<[String: Any], Error> {
        var body = params
        body["model"] = model
        body["input"] = input
        body["stream"] = true
        if let instructions = instructions {
            body["instructions"] = instructions
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await rawStreamRequest(
            method: "POST",
            path: "/responses",
            headers: ["accept": "text/event-stream"],
            body: bodyData,
            options: options
        )
        
        if response.statusCode >= 400 {
            throw TrustedRouterError.generic(statusCode: response.statusCode, message: "Error in stream response", payload: nil)
        }
        
        return iterSseEvents(response: response, bytes: bytes)
    }
    
    public func responsesInputTokens(
        model: String = TrustedRouterConstants.autoModel,
        input: Any,
        instructions: String? = nil,
        workspaceId: String? = nil,
        params: [String: Any] = [:]
    ) async throws -> ResponseInputTokens {
        var body = params
        body["model"] = model
        body["input"] = input
        body["stream"] = false
        if let instructions = instructions {
            body["instructions"] = instructions
        }
        
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "POST", path: "/responses/input_tokens", body: body, options: options)
    }

    public func broadcastDestinations(workspaceId: String? = nil) async throws -> DataList<BroadcastDestination> {
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "GET", path: "/broadcast/destinations", options: options)
    }
    
    public func createBroadcastDestination(
        type: String,
        name: String = "Broadcast destination",
        endpoint: String? = nil,
        enabled: Bool = true,
        includeContent: Bool = false,
        method: String = "POST",
        headers: [String: String]? = nil,
        apiKey: String? = nil,
        workspaceId: String? = nil
    ) async throws -> BroadcastDestination {
        var body: [String: Any] = [
            "type": type,
            "name": name,
            "enabled": enabled,
            "include_content": includeContent,
            "method": method
        ]
        if let endpoint = endpoint { body["endpoint"] = endpoint }
        if let headers = headers { body["headers"] = headers }
        if let apiKey = apiKey { body["api_key"] = apiKey }
        
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "POST", path: "/broadcast/destinations", body: body, options: options)
    }
    
    public func getBroadcastDestination(id: String, workspaceId: String? = nil) async throws -> BroadcastDestination {
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "GET", path: "/broadcast/destinations/\(id)", options: options)
    }
    
    public func updateBroadcastDestination(id: String, patch: [String: Any], workspaceId: String? = nil) async throws -> BroadcastDestination {
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "PATCH", path: "/broadcast/destinations/\(id)", body: patch, options: options)
    }
    
    public func deleteBroadcastDestination(id: String, workspaceId: String? = nil) async throws -> EmptyResponse {
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "DELETE", path: "/broadcast/destinations/\(id)", options: options)
    }
    
    public func testBroadcastDestination(id: String, workspaceId: String? = nil) async throws -> EmptyResponse {
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "POST", path: "/broadcast/destinations/\(id)/test", options: options)
    }
    
    public func billingCheckout(
        amount: Any,
        paymentMethod: String? = nil,
        successUrl: String? = nil,
        cancelUrl: String? = nil,
        options: PerCallOptions = PerCallOptions()
    ) async throws -> CheckoutResponse {
        var body: [String: Any] = ["amount": amount]
        if let paymentMethod = paymentMethod { body["payment_method"] = paymentMethod }
        if let successUrl = successUrl { body["success_url"] = successUrl }
        if let cancelUrl = cancelUrl { body["cancel_url"] = cancelUrl }
        
        if body["workspace_id"] == nil && options.workspaceId != nil {
            body["workspace_id"] = options.workspaceId
        }
        return try await request(method: "POST", path: "/billing/checkout", body: body, options: options)
    }
    
    public func authSession() async throws -> AuthSessionResponse {
        return try await request(method: "GET", path: "/auth/session")
    }
    
    public func logout() async throws -> EmptyResponse {
        return try await request(method: "POST", path: "/auth/logout")
    }
    
    public func activity(params: [String: Any] = [:]) async throws -> ActivityResponse {
        var queryItems: [URLQueryItem] = []
        for (key, value) in params {
            queryItems.append(URLQueryItem(name: key, value: "\(value)"))
        }
        var urlComponents = URLComponents()
        urlComponents.queryItems = queryItems.isEmpty ? nil : queryItems
        let queryStr = urlComponents.query ?? ""
        let path = queryStr.isEmpty ? "/activity" : "/activity?\(queryStr)"
        
        return try await request(method: "GET", path: path)
    }

    public func status(url: String = TrustedRouterConstants.defaultStatusURL) async throws -> [String: Any] {
        // Return raw dict for status as it's highly dynamic
        let data: Data = try await request(method: "GET", path: url)
        if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return [:]
    }

    /**
     * Roll a list of ChatCompletionChunk frames into a single ChatCompletion object.
     * Mirrors the JS/Python collect_completion helpers.
     */
    public func collectCompletion(chunks: [ChatCompletionChunk]) -> ChatCompletion {
        if chunks.isEmpty {
            return ChatCompletion(
                id: "",
                object: "chat.completion",
                created: nil,
                model: nil,
                choices: [
                    ChatCompletion.Choice(
                        index: 0,
                        message: ChatCompletion.Choice.Message(role: "assistant", content: ""),
                        finishReason: "stop"
                    )
                ],
                usage: nil
            )
        }
        
        var content = ""
        var finishReason: String? = nil
        for chunk in chunks {
            if let choice = chunk.choices.first {
                if let deltaContent = choice.delta?.content {
                    content += deltaContent
                }
                if let reason = choice.finishReason {
                    finishReason = reason
                }
            }
        }
        
        let last = chunks.last!
        return ChatCompletion(
            id: last.id ?? "",
            object: "chat.completion",
            created: last.created,
            model: last.model,
            choices: [
                ChatCompletion.Choice(
                    index: 0,
                    message: ChatCompletion.Choice.Message(role: "assistant", content: content),
                    finishReason: finishReason ?? "stop"
                )
            ],
            usage: nil
        )
    }
}
