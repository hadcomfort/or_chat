import Foundation

// Data structure for parsing the response from the OpenRouter API
// Based on typical LLM API responses. Adjust if OpenRouter has a different structure.
struct OpenRouterResponse: Codable {
    let id: String? // Optional: Some APIs return an ID for the response
    let choices: [Choice]
    // Add other fields like 'created', 'model', 'usage' if needed from the response.
}

struct Choice: Codable {
    let message: MessageContent
    // let finishReason: String? // Optional: e.g., "stop", "length"
}

struct MessageContent: Codable {
    let role: String // e.g., "assistant"
    let content: String
}
