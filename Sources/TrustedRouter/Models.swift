import Foundation

public struct ChatCompletionChunk: Sendable {
    public var id: String?
    public var object: String?
    public var created: Int?
    public var model: String?
    public var choices: [Choice]
    
    public struct Choice: Sendable {
        public var index: Int?
        public var delta: Delta?
        public var finishReason: String?
        
        public struct Delta: Sendable {
            public var role: String?
            public var content: String?
        }
    }
}

public struct ChatCompletion: Sendable {
    public var id: String
    public var object: String
    public var created: Int?
    public var model: String?
    public var choices: [Choice]
    public var usage: Usage?
    
    public struct Choice: Sendable {
        public var index: Int
        public var message: Message
        public var finishReason: String?
        
        public struct Message: Sendable {
            public var role: String
            public var content: String?
        }
    }
    
    public struct Usage: Sendable {
        public var promptTokens: Int
        public var completionTokens: Int
        public var totalTokens: Int
    }
}
