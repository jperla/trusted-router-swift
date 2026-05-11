# trusted-router-swift

Swift SDK for [TrustedRouter](https://trustedrouter.com).

This is a pure Swift, zero-dependency client SDK for the Quill Cloud API gateway. It provides the same interface, error handling, SSE streaming, and GCP Confidential Space JWT verification as the Python and Javascript SDKs.

## Installation

Add this to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/Lore-Hex/trusted-router-swift.git", from: "0.3.0")
```

Then add `"TrustedRouter"` to your target's dependencies.

## Usage

```swift
import TrustedRouter

let client = try TrustedRouter(options: TrustedRouterOptions(
    apiKey: "your-api-key"
))

// Async/await JSON requests
let models = try await client.models()
print(models)

// SSE Streaming
let stream = try await client.chatCompletionsChunks(messages: [
    ["role": "user", "content": "Hello, world!"]
])

for try await chunk in stream {
    print(chunk)
}
```

## Features

- **Asynchronous**: Built fully on modern Swift Concurrency (`async/await`, `Task`).
- **Streaming**: Native parsing of SSE using `AsyncThrowingStream` and `URLSession.AsyncBytes`.
- **Attestation Verification**: Verifies the Confidential Space JWT using `CryptoKit`/`Security`.
- **Pure Swift**: No 3rd party dependencies. Operates seamlessly on macOS, iOS, tvOS, watchOS, and Linux (with `swift-crypto` and `FoundationNetworking`).
- **Retries**: Implements transparent exponential backoff on `429` and `5xx` errors.

## License

Apache 2.0
