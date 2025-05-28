import Foundation

// Represents a single message in the chat, used for UI and API communication.
// Conforms to Codable for JSON serialization when talking to OpenRouter API and for local storage.
// Conforms to Identifiable for SwiftUI list rendering.
// SECURITY: This model holds chat content (`content`) which can be sensitive.
// Its `role` indicates if it's from the user or the AI.
// The `id` is a local identifier for UI purposes.
struct ChatMessage: Identifiable, Codable {
    let id: UUID // Used for SwiftUI list identification. For local storage, this is saved. Not sent to API.
    var role: String // e.g., "user", "assistant", "system". Sent to API and saved locally.
    var content: String // The actual message text. Sent to API and saved locally.

    // CodingKeys define how this struct is encoded/decoded, particularly for network requests.
    // SECURITY: This enum ensures that only 'role' and 'content' are included when ChatMessage
    // instances are encoded as part of an API request (e.g., in OpenRouterRequest).
    // The 'id' field is deliberately excluded from API communication by not being a case here.
    // For local storage (e.g., using JSONEncoder/Decoder directly on ChatMessage), all properties
    // including 'id' will be encoded/decoded by default unless specific encoder/decoder configurations prevent it.
    // Our StorageService saves and loads 'id', 'role', and 'content'.
    enum CodingKeys: String, CodingKey {
        case role
        case content
        // 'id' is omitted, so it won't be part of the JSON for API requests using these keys.
    }

    // Initializer for creating messages within the app, typically for UI display or before sending.
    // The 'id' is automatically generated if not provided.
    init(id: UUID = UUID(), role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    // Convenience initializer for creating messages from user input (text, isFromUser)
    // or when adapting data that uses a boolean flag for user identification.
    // It translates 'isFromUser' to the 'role' string.
    // SECURITY: This initializer handles the transformation of a display-oriented flag (`isFromUser`)
    // to the data model's `role` property.
    init(id: UUID = UUID(), text: String, isFromUser: Bool) {
        self.id = id
        self.role = isFromUser ? "user" : "assistant"
        self.content = text
    }
}
