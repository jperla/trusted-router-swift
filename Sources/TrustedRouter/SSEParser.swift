import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SSEEvent: Sendable {
    public var event: String?
    public var data: String
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public func iterSseEvents<T: Decodable>(response: HTTPURLResponse, bytes: URLSession.AsyncBytes, type: T.Type) -> AsyncThrowingStream<T, Error> {
    return AsyncThrowingStream { continuation in
        Task {
            do {
                let decoder = JSONDecoder()
                for try await line in bytes.lines {
                    if line.hasPrefix("data:") {
                        let dataStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if !dataStr.isEmpty && dataStr != "[DONE]" {
                            if let data = dataStr.data(using: .utf8) {
                                do {
                                    let model = try decoder.decode(T.self, from: data)
                                    continuation.yield(model)
                                } catch {
                                    // Skip decoding errors for now or yield them
                                }
                            }
                        }
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public func iterSseEvents(response: HTTPURLResponse, bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<[String: Any], Error> {
    return AsyncThrowingStream { continuation in
        Task {
            do {
                var currentEvent: String? = nil
                for try await line in bytes.lines {
                    if line.hasPrefix("event:") {
                        currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("data:") {
                        let dataStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if !dataStr.isEmpty && dataStr != "[DONE]" {
                            if let data = dataStr.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                var payload = json
                                if let event = currentEvent, payload["event"] == nil {
                                    payload["event"] = event
                                }
                                continuation.yield(payload)
                            } else {
                                var payload: [String: Any] = ["data": dataStr]
                                if let event = currentEvent {
                                    payload["event"] = event
                                }
                                continuation.yield(payload)
                            }
                        }
                    } else if line.isEmpty {
                        currentEvent = nil
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
