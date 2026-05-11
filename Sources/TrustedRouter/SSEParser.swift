import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SSEEvent: Sendable {
    public var event: String?
    public var data: String
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public func iterSseEvents(response: HTTPURLResponse, bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<[String: Any], Error> {
    return AsyncThrowingStream { continuation in
        Task {
            do {
                var currentEvent: String? = nil
                var dataParts: [String] = []

                for try await line in bytes.lines {
                    if line.isEmpty {
                        if !dataParts.isEmpty {
                            let dataStr = dataParts.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                            if !dataStr.isEmpty && dataStr != "[DONE]" {
                                var payload: [String: Any]
                                if let data = dataStr.data(using: .utf8),
                                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    payload = json
                                } else {
                                    payload = ["data": dataStr]
                                }
                                if let event = currentEvent, payload["event"] == nil {
                                    payload["event"] = event
                                }
                                continuation.yield(payload)
                            }
                        }
                        currentEvent = nil
                        dataParts = []
                    } else if line.hasPrefix("event:") {
                        currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("data:") {
                        dataParts.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                    }
                }
                
                // Process any remaining parts if the stream didn't end with a blank line
                if !dataParts.isEmpty {
                    let dataStr = dataParts.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                    if !dataStr.isEmpty && dataStr != "[DONE]" {
                        var payload: [String: Any]
                        if let data = dataStr.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            payload = json
                        } else {
                            payload = ["data": dataStr]
                        }
                        if let event = currentEvent, payload["event"] == nil {
                            payload["event"] = event
                        }
                        continuation.yield(payload)
                    }
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
