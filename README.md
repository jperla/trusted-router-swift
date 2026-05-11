# trusted-router-swift

Swift SDK for [TrustedRouter](https://trustedrouter.com).

This is a pure Swift, zero-dependency client SDK for the Quill Cloud API gateway. It provides the same interface, error handling, SSE streaming, and GCP Confidential Space JWT verification as the Python and Javascript SDKs.

## Installation

Add this to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/jperla/trusted-router-swift.git", from: "0.4.0")
```

Then add `"TrustedRouter"` to your target's dependencies.

## Usage

```swift
import TrustedRouter

let client = try TrustedRouter(options: .init(apiKey: "your-api-key"))

// Typed catalog calls
let models = try await client.models()                    // DataList<ModelInfo>
print(models.data.map(\.id))

// Typed chat with the ChatMessage convenience constructors
let answer = try await client.chatCompletions(messages: [
    .system("Reply with one word."),
    .user("Hello?"),
])
print(answer.choices.first?.message.content ?? "")

// SSE streaming, typed chunks
let stream = try await client.chatCompletionsChunks(messages: [
    .user("Tell me a joke."),
])
for try await chunk in stream {
    if let delta = chunk.choices.first?.delta?.content {
        print(delta, terminator: "")
    }
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
