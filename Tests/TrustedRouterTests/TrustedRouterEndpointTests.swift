import Foundation
import XCTest
@testable import TrustedRouter

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

class MockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: HTTPURLResponse?
    static var mockError: Error?
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        if let error = MockURLProtocol.mockError {
            self.client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            if let handler = MockURLProtocol.requestHandler {
                let (response, data) = try handler(request)
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
            } else {
                if let response = MockURLProtocol.mockResponse {
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }
                if let data = MockURLProtocol.mockData {
                    self.client?.urlProtocol(self, didLoad: data)
                }
            }
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class TrustedRouterEndpointTests: XCTestCase {
    var router: TrustedRouter!
    var session: URLSession!

    override func setUpWithError() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)

        router = try TrustedRouter(options: TrustedRouterOptions(
            apiKey: "test_key",
            baseUrl: "https://test.local/v1",
            urlSession: session,
            workspaceId: "test_workspace"
        ))
    }

    func testModelsEndpoint() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://test.local/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = """
            {"data": [{"id": "model-1", "owned_by": "quill"}]}
            """.data(using: .utf8)!
            return (response, json)
        }

        let response = try await router.models()
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data.first?.id, "model-1")
        XCTAssertEqual(response.data.first?.ownedBy, "quill")
    }

    func testChatCompletions() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://test.local/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            
            // Gateway always streams, so we mock SSE data
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
            let sseData = """
            data: {"id": "test-chat", "object": "chat.completion.chunk", "choices": [{"index": 0, "delta": {"role": "assistant", "content": "Hello"}, "finish_reason": null}]}
            
            data: {"id": "test-chat", "object": "chat.completion.chunk", "choices": [{"index": 0, "delta": {"content": " world"}, "finish_reason": "stop"}]}
            
            data: [DONE]
            
            """.data(using: .utf8)!
            return (response, sseData)
        }

        let result = try await router.chatCompletions(messages: [["role": "user", "content": "Hi"]])
        XCTAssertEqual(result.id, "test-chat")
        XCTAssertEqual(result.choices.first?.message.content, "Hello world")
        XCTAssertEqual(result.choices.first?.finishReason, "stop")
    }
    
    func testErrorHandling() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = """
            {"error": {"message": "You do not have permission"}}
            """.data(using: .utf8)!
            return (response, json)
        }

        do {
            _ = try await router.models()
            XCTFail("Should have thrown")
        } catch TrustedRouterError.permissionDenied(let status, let message, _) {
            XCTAssertEqual(status, 403)
            XCTAssertEqual(message, "You do not have permission")
        } catch {
            XCTFail("Threw wrong error: \(error)")
        }
    }
}
