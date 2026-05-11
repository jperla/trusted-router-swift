import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SSEEvent: Sendable {
    public var event: String?
    public var data: String
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public enum SSEParser {
    
    /// Low-level stream of raw SSE events from AsyncBytes.
    public static func stream(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Use a buffer approach to handle \n\n correctly
                    var buffer = ""
                    for try await byte in bytes {
                        if let char = String(bytes: [byte], encoding: .utf8) {
                            buffer += char
                            if buffer.hasSuffix("\n\n") || buffer.hasSuffix("\r\n\r\n") {
                                // Frame boundary reached
                                let frame = buffer
                                buffer = ""
                                if let event = parseFrame(frame) {
                                    continuation.yield(event)
                                }
                            }
                        }
                    }
                    
                    // Final frame
                    if !buffer.isEmpty {
                        if let event = parseFrame(buffer) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private static func parseFrame(_ frame: String) -> SSEEvent? {
        var currentEvent: String? = nil
        var dataParts: [String] = []
        
        let lines = frame.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("event:") {
                currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataParts.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
            }
        }
        
        if dataParts.isEmpty { return nil }
        return SSEEvent(event: currentEvent, data: dataParts.joined(separator: "\n"))
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public func iterSseEvents<T: Decodable>(bytes: URLSession.AsyncBytes, type: T.Type) -> AsyncThrowingStream<T, Error> {
    let decoder = JSONDecoder()
    let rawStream = SSEParser.stream(from: bytes)
    
    return AsyncThrowingStream { continuation in
        Task {
            do {
                for try await event in rawStream {
                    let trimmedData = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedData == "[DONE]" { break }
                    guard let data = trimmedData.data(using: .utf8) else { continue }
                    do {
                        let model = try decoder.decode(T.self, from: data)
                        continuation.yield(model)
                    } catch {
                        // Skip non-matching chunks
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
public func iterSseEvents(bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<[String: Any], Error> {
    let rawStream = SSEParser.stream(from: bytes)
    
    return AsyncThrowingStream { continuation in
        Task {
            do {
                for try await event in rawStream {
                    let trimmedData = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedData == "[DONE]" { break }
                    guard let data = trimmedData.data(using: .utf8) else { continue }
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var payload = json
                        if let eventName = event.event, payload["event"] == nil {
                            payload["event"] = eventName
                        }
                        continuation.yield(payload)
                    } else {
                        var payload: [String: Any] = ["data": event.data]
                        if let eventName = event.event { payload["event"] = eventName }
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
