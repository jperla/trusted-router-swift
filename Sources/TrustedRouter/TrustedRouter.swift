import Foundation

public struct TrustedRouterConstants {
    public static let version = "0.3.0"
    public static let defaultAPIBaseURL = "https://api.quillrouter.com/v1"
    public static let defaultTrustReleaseURL = "https://trust.trustedrouter.com/trust/gcp-release.json"
    public static let defaultStatusURL = "https://status.trustedrouter.com/status.json"
    public static let autoModel = "trustedrouter/auto"

    public static let regionHosts: [String: String] = [
        "us-central1": "api.quillrouter.com",
        "europe-west4": "api-europe-west4.quillrouter.com"
    ]
}

public func regionBaseUrl(region: String) throws -> String {
    guard let host = TrustedRouterConstants.regionHosts[region] else {
        let known = TrustedRouterConstants.regionHosts.keys.sorted().joined(separator: ", ")
        throw TrustedRouterError.internalError("unknown TrustedRouter region '\(region)'; known: \(known)")
    }
    return "https://\(host)/v1"
}

public enum TrustedRouterError: Error, LocalizedError, CustomStringConvertible {
    case badRequest(statusCode: Int, message: String, payload: [String: Any]?)
    case authentication(statusCode: Int, message: String, payload: [String: Any]?)
    case permissionDenied(statusCode: Int, message: String, payload: [String: Any]?)
    case notFound(statusCode: Int, message: String, payload: [String: Any]?)
    case endpointNotSupported(statusCode: Int, message: String, payload: [String: Any]?)
    case rateLimit(statusCode: Int, message: String, payload: [String: Any]?, retryAfterSeconds: Double?)
    case internalError(String)
    case generic(statusCode: Int, message: String, payload: [String: Any]?)
    case invalidResponse(String)

    public var errorDescription: String? { description }
    public var description: String {
        switch self {
        case let .badRequest(statusCode, message, _),
             let .authentication(statusCode, message, _),
             let .permissionDenied(statusCode, message, _),
             let .notFound(statusCode, message, _),
             let .endpointNotSupported(statusCode, message, _),
             let .generic(statusCode, message, _):
            return "[\(statusCode)] \(message)"
        case let .rateLimit(statusCode, message, _, retryAfterSeconds):
            if let retryAfterSeconds {
                return "[\(statusCode)] \(message) (retry after \(retryAfterSeconds)s)"
            }
            return "[\(statusCode)] \(message)"
        case .internalError(let message), .invalidResponse(let message):
            return message
        }
    }
}

public struct TrustedRouterOptions {
    public var apiKey: String?
    public var baseUrl: String?
    public var region: String?
    public var urlSession: URLSession
    public var headers: [String: String]
    public var workspaceId: String?
    public var maxRetries: Int

    public init(
        apiKey: String? = nil,
        baseUrl: String? = nil,
        region: String? = nil,
        urlSession: URLSession = .shared,
        headers: [String: String] = [:],
        workspaceId: String? = nil,
        maxRetries: Int = 2
    ) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.region = region
        self.urlSession = urlSession
        self.headers = headers
        self.workspaceId = workspaceId
        self.maxRetries = maxRetries
    }
}

public struct PerCallOptions {
    public var apiKey: String?
    public var extraHeaders: [String: String]?
    public var workspaceId: String?
    public var idempotencyKey: String?
    public var timeout: TimeInterval?

    public init(
        apiKey: String? = nil,
        extraHeaders: [String: String]? = nil,
        workspaceId: String? = nil,
        idempotencyKey: String? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.apiKey = apiKey
        self.extraHeaders = extraHeaders
        self.workspaceId = workspaceId
        self.idempotencyKey = idempotencyKey
        self.timeout = timeout
    }
}

public struct ChatMessage: Codable, Sendable {
    public var role: String
    public var content: String?
    public var name: String?
    // Using AnyCodable or custom decodable for extra stuff would be ideal,
    // but to keep it simple we can represent tools via dicts if needed.
    // For pure Swift, we often use AnyCodable.
}
