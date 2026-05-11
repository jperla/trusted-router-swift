import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class TrustedRouter: Sendable {
    public let apiKey: String?
    public let baseUrl: String
    public let region: String?
    public let urlSession: URLSession
    public let defaultHeaders: [String: String]
    public let maxRetries: Int
    public let workspaceId: String?

    public init(options: TrustedRouterOptions = TrustedRouterOptions()) throws {
        if options.region != nil && options.baseUrl != nil {
            throw TrustedRouterError.internalError("pass region OR baseUrl, not both")
        }
        var computedBaseUrl = options.baseUrl ?? TrustedRouterConstants.defaultAPIBaseURL
        if let region = options.region {
            computedBaseUrl = try regionBaseUrl(region: region)
        }

        self.apiKey = options.apiKey
        self.baseUrl = computedBaseUrl.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        self.region = options.region
        self.urlSession = options.urlSession
        self.defaultHeaders = options.headers
        self.maxRetries = max(0, options.maxRetries)
        self.workspaceId = options.workspaceId
    }

    private func buildHeaders(
        headers: [String: String]? = nil,
        extraHeaders: [String: String]? = nil,
        idempotencyKey: String? = nil,
        apiKey: String? = nil,
        workspaceId: String? = nil
    ) -> [String: String] {
        var out = ["user-agent": "trusted-router-swift/\(TrustedRouterConstants.version)"]
        for (k, v) in self.defaultHeaders { out[k] = v }
        if let headers = headers {
            for (k, v) in headers { out[k] = v }
        }
        if let extraHeaders = extraHeaders {
            for (k, v) in extraHeaders { out[k] = v }
        }
        if let idempotencyKey = idempotencyKey {
            out["idempotency-key"] = idempotencyKey
        }
        if let selectedWorkspaceId = workspaceId ?? self.workspaceId {
            out["x-trustedrouter-workspace"] = selectedWorkspaceId
        }
        if let bearer = apiKey ?? self.apiKey, out["authorization"] == nil {
            out["authorization"] = "Bearer \(bearer)"
        }
        return out
    }

    private func parseRetryAfter(_ response: HTTPURLResponse) -> Double? {
        if let raw = response.allHeaderFields["retry-after"] as? String ?? response.allHeaderFields["Retry-After"] as? String {
            return Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func isRetryable(_ statusCode: Int) -> Bool {
        return statusCode == 429 || statusCode >= 500
    }

    private func retrySleepMs(attempt: Int, retryAfterSeconds: Double?) -> UInt64 {
        let baseMs = min(30_000, 500 * pow(2.0, Double(attempt)))
        let jittered = Double.random(in: 0...baseMs)
        let floor = (retryAfterSeconds ?? 0) * 1000.0
        return UInt64(max(jittered, floor) * 1_000_000)
    }

    private func classifyError(statusCode: Int, data: Data?, response: HTTPURLResponse) -> TrustedRouterError {
        var message = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        var payload: [String: Any]? = nil
        
        if let data = data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = obj
            if let err = obj["error"] as? [String: Any] {
                message = (err["message"] as? String) ?? (err["type"] as? String) ?? message
            } else if let msg = obj["message"] as? String {
                message = msg
            }
        } else if let data = data, let str = String(data: data, encoding: .utf8), !str.isEmpty {
            message = str
            payload = ["message": str]
        }

        let retryAfter = parseRetryAfter(response)

        switch statusCode {
        case 401: return .authentication(statusCode: statusCode, message: message, payload: payload)
        case 403: return .permissionDenied(statusCode: statusCode, message: message, payload: payload)
        case 404: return .notFound(statusCode: statusCode, message: message, payload: payload)
        case 429: return .rateLimit(statusCode: statusCode, message: message, payload: payload, retryAfterSeconds: retryAfter)
        case 501: return .endpointNotSupported(statusCode: statusCode, message: message, payload: payload)
        case 400..<500: return .badRequest(statusCode: statusCode, message: message, payload: payload)
        case 500...: return .generic(statusCode: statusCode, message: message, payload: payload)
        default: return .generic(statusCode: statusCode, message: message, payload: payload)
        }
    }

    public func rawRequest(
        method: String,
        path: String,
        headers: [String: String]? = nil,
        body: Data? = nil,
        options: PerCallOptions = PerCallOptions()
    ) async throws -> (Data, HTTPURLResponse) {
        let urlString = "\(baseUrl)/\(path.replacingOccurrences(of: "^/+", with: "", options: .regularExpression))"
        guard let url = URL(string: urlString) else {
            throw TrustedRouterError.internalError("Invalid URL: \(urlString)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if let timeout = options.timeout {
            req.timeoutInterval = timeout
        }

        let reqHeaders = buildHeaders(
            headers: headers,
            extraHeaders: options.extraHeaders,
            idempotencyKey: options.idempotencyKey,
            apiKey: options.apiKey,
            workspaceId: options.workspaceId
        )

        for (k, v) in reqHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        
        if body != nil && req.value(forHTTPHeaderField: "Content-Type") == nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrustedRouterError.internalError("Non-HTTP response")
        }
        return (data, httpResponse)
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    public func rawStreamRequest(
        method: String,
        path: String,
        headers: [String: String]? = nil,
        body: Data? = nil,
        options: PerCallOptions = PerCallOptions()
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let urlString = "\(baseUrl)/\(path.replacingOccurrences(of: "^/+", with: "", options: .regularExpression))"
        guard let url = URL(string: urlString) else {
            throw TrustedRouterError.internalError("Invalid URL: \(urlString)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if let timeout = options.timeout {
            req.timeoutInterval = timeout
        }

        let reqHeaders = buildHeaders(
            headers: headers,
            extraHeaders: options.extraHeaders,
            idempotencyKey: options.idempotencyKey,
            apiKey: options.apiKey,
            workspaceId: options.workspaceId
        )

        for (k, v) in reqHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        
        if body != nil && req.value(forHTTPHeaderField: "Content-Type") == nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (bytes, response) = try await urlSession.bytes(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrustedRouterError.internalError("Non-HTTP response")
        }
        return (bytes, httpResponse)
    }

    public func request<T: Decodable>(
        method: String,
        path: String,
        headers: [String: String]? = nil,
        body: Any? = nil,
        options: PerCallOptions = PerCallOptions()
    ) async throws -> T {
        var bodyData: Data? = nil
        if let body = body {
            if let data = body as? Data {
                bodyData = data
            } else {
                bodyData = try JSONSerialization.data(withJSONObject: body)
            }
        }

        var attempt = 0
        while true {
            do {
                let (data, response) = try await rawRequest(method: method, path: path, headers: headers, body: bodyData, options: options)
                if attempt >= maxRetries || !isRetryable(response.statusCode) {
                    if response.statusCode >= 400 {
                        throw classifyError(statusCode: response.statusCode, data: data, response: response)
                    }
                    
                    if T.self == Data.self {
                        return data as! T
                    }
                    
                    if data.isEmpty {
                        // For Void or empty responses, we might need a better way.
                        // For now we'll try to decode empty JSON.
                        if let emptyObj = "{}" .data(using: .utf8) {
                            return try JSONDecoder().decode(T.self, from: emptyObj)
                        }
                    }

                    return try JSONDecoder().decode(T.self, from: data)
                }
                
                let retryAfter = parseRetryAfter(response)
                try await Task.sleep(nanoseconds: retrySleepMs(attempt: attempt, retryAfterSeconds: retryAfter))
                attempt += 1
            } catch let err as TrustedRouterError {
                throw err
            } catch {
                if attempt >= maxRetries {
                    throw TrustedRouterError.internalError(error.localizedDescription)
                }
                try await Task.sleep(nanoseconds: retrySleepMs(attempt: attempt, retryAfterSeconds: nil))
                attempt += 1
            }
        }
    }
}
