import Foundation

// Data structure for sending a request to the OpenRouter API.
// SECURITY: This struct defines the payload sent to the OpenRouter API.
// It's crucial to ensure it only includes data necessary for the API call and no unintended sensitive information.
struct OpenRouterRequest: Codable {
    // The model to use for the chat completion, e.g., "gryphe/mythomax-l2-13b".
    // This is a required parameter by the API.
    let model: String
    
    // An array of `ChatMessage` objects representing the conversation history.
    // SECURITY: The `ChatMessage` objects themselves are encoded according to their `CodingKeys`,
    // meaning only 'role' and 'content' are sent, not the local 'id'.
    // The 'content' of these messages is user-generated or AI-generated chat data, which can be sensitive.
    let messages: [ChatMessage]
    
    // Optional parameters like temperature, max_tokens, etc., could be added here if needed.
    // For now, the request is kept minimal.
    // Example:
    // let temperature: Double?
    // let maxTokens: Int?

    // Example of how this struct might be initialized:
    // OpenRouterRequest(model: "gryphe/mythomax-l2-13b", messages: [ChatMessage(role:"user", content:"Hello")])
}
