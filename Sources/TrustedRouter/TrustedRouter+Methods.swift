import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension TrustedRouter {
    
    // ---- catalog / metadata ---------------------------------------------
    
    public func models() async throws -> [String: Any] {
        return try await request(method: "GET", path: "/models")
    }
    
    public func providers() async throws -> [String: Any] {
        return try await request(method: "GET", path: "/providers")
    }
    
    public func regions() async throws -> [String: Any] {
        return try await request(method: "GET", path: "/regions")
    }
    
    public func credits(workspaceId: String? = nil) async throws -> [String: Any] {
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "GET", path: "/credits", options: options)
    }
    
    // ---- chat ------------------------------------------------------------
    
    public func chatCompletions(
        model: String = TrustedRouterConstants.autoModel,
        messages: [[String: Any]],
        options: PerCallOptions = PerCallOptions(),
        params: [String: Any] = [:]
    ) async throws -> [String: Any] {
        var body = params
        body["model"] = model
        body["messages"] = messages
        body["stream"] = false
        
        return try await request(method: "POST", path: "/chat/completions", body: body, options: options)
    }
    
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func chatCompletionsChunks(
        model: String = TrustedRouterConstants.autoModel,
        messages: [[String: Any]],
        options: PerCallOptions = PerCallOptions(),
        params: [String: Any] = [:]
    ) async throws -> AsyncThrowingStream<[String: Any], Error> {
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
            // Need to read the body. For streaming, this is tricky. We'll throw generic error here.
            throw TrustedRouterError.generic(statusCode: response.statusCode, message: "Error in stream response", payload: nil)
        }
        
        return iterSseEvents(response: response, bytes: bytes)
    }

    // ---- other endpoints ---------------------------------------------
    
    public func embeddings(
        model: String,
        input: Any,
        encodingFormat: String? = nil,
        dimensions: Int? = nil,
        user: String? = nil,
        options: PerCallOptions = PerCallOptions()
    ) async throws -> [String: Any] {
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
    ) async throws -> [String: Any] {
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
    ) async throws -> [String: Any] {
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
    
    public func broadcastDestinations(workspaceId: String? = nil) async throws -> [String: Any] {
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
    ) async throws -> [String: Any] {
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
    
    public func getBroadcastDestination(id: String, workspaceId: String? = nil) async throws -> [String: Any] {
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "GET", path: "/broadcast/destinations/\(id)", options: options)
    }
    
    public func updateBroadcastDestination(id: String, patch: [String: Any], workspaceId: String? = nil) async throws -> [String: Any] {
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "PATCH", path: "/broadcast/destinations/\(id)", body: patch, options: options)
    }
    
    public func deleteBroadcastDestination(id: String, workspaceId: String? = nil) async throws -> [String: Any] {
        var options = PerCallOptions()
        options.workspaceId = workspaceId
        return try await request(method: "DELETE", path: "/broadcast/destinations/\(id)", options: options)
    }
    
    public func testBroadcastDestination(id: String, workspaceId: String? = nil) async throws -> [String: Any] {
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
    ) async throws -> [String: Any] {
        var body: [String: Any] = ["amount": amount]
        if let paymentMethod = paymentMethod { body["payment_method"] = paymentMethod }
        if let successUrl = successUrl { body["success_url"] = successUrl }
        if let cancelUrl = cancelUrl { body["cancel_url"] = cancelUrl }
        
        let reqOptions = options
        if body["workspace_id"] == nil && options.workspaceId != nil {
            body["workspace_id"] = options.workspaceId
        }
        return try await request(method: "POST", path: "/billing/checkout", body: body, options: reqOptions)
    }
    
    public func authSession() async throws -> [String: Any] {
        return try await request(method: "GET", path: "/auth/session")
    }
    
    public func logout() async throws -> [String: Any] {
        return try await request(method: "POST", path: "/auth/logout")
    }
    
    public func activity(params: [String: Any] = [:]) async throws -> [String: Any] {
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
}
