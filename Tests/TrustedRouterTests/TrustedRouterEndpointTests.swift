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
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer test_key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-trustedrouter-workspace"), "test_workspace")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = """
            {"data": [{"id": "model-1"}]}
            """.data(using: .utf8)!
            return (response, json)
        }

        let response = try await router.models()
        XCTAssertNotNil(response["data"])
    }

    func testChatCompletions() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://test.local/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            
            var dataToParse: Data? = request.httpBody
            if dataToParse == nil, let stream = request.httpBodyStream {
                stream.open()
                let bufferSize = 1024
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                var data = Data()
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: bufferSize)
                    if read < 0 { break }
                    data.append(buffer, count: read)
                    if read == 0 { break }
                }
                stream.close()
                buffer.deallocate()
                dataToParse = data
            }

            if let bodyData = dataToParse,
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                XCTAssertEqual(json["model"] as? String, "trustedrouter/auto")
                XCTAssertEqual(json["stream"] as? Bool, false)
            } else {
                XCTFail("Missing or invalid body")
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = """
            {"id": "test-chat", "choices": []}
            """.data(using: .utf8)!
            return (response, json)
        }

        let result = try await router.chatCompletions(messages: [["role": "user", "content": "Hello"]])
        XCTAssertEqual(result["id"] as? String, "test-chat")
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
