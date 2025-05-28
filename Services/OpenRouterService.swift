import Foundation

// Service to interact with the OpenRouter API
// Handles constructing requests, sending them, and parsing responses.
class OpenRouterService {
    // The base URL for the OpenRouter API.
    // SECURITY: This URL must use HTTPS to ensure encrypted communication between the app and the API server.
    private let openRouterAPIURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    // Default model if not specified by the user.
    private let defaultModel = "gryphe/mythomax-l2-13b" // Example model, can be made configurable.

    // Custom Error type for networking operations.
    enum NetworkError: Error, LocalizedError {
        case invalidURL
        case requestFailed(Error) // Underlying error from URLSession.
        case noData // No data received when data was expected.
        case decodingError(Error) // Error during JSON decoding.
        case apiError(message: String, statusCode: Int) // Specific error reported by the API.
        case apiKeyMissing // API key was not found in Keychain.
        case unknown // Other unexpected errors.

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Network Error: The API endpoint URL is invalid."
            case .requestFailed(let error): return "Network Error: Request failed: \(error.localizedDescription)"
            case .noData: return "Network Error: No data received from the server."
            case .decodingError(let error): return "Network Error: Failed to decode server response: \(error.localizedDescription)"
            case .apiError(let message, let statusCode): return "API Error (\(statusCode)): \(message)"
            case .apiKeyMissing: return "API Key Error: OpenRouter API Key is missing. Please set it in the app."
            case .unknown: return "Network Error: An unknown networking error occurred."
            }
        }
    }

    // Function to send a chat message history and get a response from OpenRouter.
    // SECURITY: This function handles sensitive data (API key, chat content).
    // The API key is fetched on-demand from `KeychainService` for each request and is not stored as a property of this service.
    func sendChatRequest(messages: [ChatMessage], model: String? = nil) async throws -> ChatMessage {
        guard let apiKey = KeychainService.retrieveAPIKey() else {
            // SECURITY: Critical check. If API key is missing, an error is thrown before any network call.
            print("OpenRouterService: API Key is missing. Cannot make API call.")
            throw NetworkError.apiKeyMissing
        }

        let requestModel = model ?? defaultModel
        // SECURITY: `OpenRouterRequest` is prepared, containing only necessary data (model, messages).
        let openRouterRequest = OpenRouterRequest(model: requestModel, messages: messages)

        var request = URLRequest(url: openRouterAPIURL)
        request.httpMethod = "POST"
        // SECURITY: The Authorization header is constructed using the API key as a Bearer token. This is standard practice for API authentication.
        // The API key is not logged or exposed beyond this point in the request construction.
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Optional headers for OpenRouter.
        // SECURITY: `HTTP-Referer` and `X-Title` are currently using generic local values.
        // For a production app, these should be meaningful URLs/names or user-configurable for privacy if desired.
        // Using "http://localhost" is acceptable for a local-only app and does not leak user-specific site data.
        request.addValue("http://localhost", forHTTPHeaderField: "HTTP-Referer") 
        request.addValue("OpenRouter Minimal Chat", forHTTPHeaderField: "X-Title")

        do {
            // SECURITY: The request body is encoded to JSON. `JSONEncoder` helps prevent malformed requests.
            request.httpBody = try JSONEncoder().encode(openRouterRequest)
            // SECURITY LOGGING: Log request details for debugging, but *never* log the API key.
            // Only message content (potentially sensitive) and model are logged here.
            print("OpenRouterService: Sending API Request - Model: \(requestModel), Message Count: \(messages.count), First Message (Sanitized): '\(messages.first?.content.prefix(30) ?? "N/A")...'")
        } catch {
            print("OpenRouterService: Failed to encode request: \(error)")
            throw NetworkError.decodingError(error) // More accurately, an encoding error.
        }

        do {
            // SECURITY: `URLSession.shared.data(for: request)` handles the HTTPS communication,
            // ensuring transport layer security (TLS) if the URL is HTTPS.
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                // This indicates a non-HTTP response, which is unexpected.
                throw NetworkError.unknown 
            }
            
            // SECURITY LOGGING: Log the HTTP status code. Full headers could be logged for debugging but might contain sensitive info; avoid in production.
            print("OpenRouterService: API Response Status Code: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                // Attempt to decode a specific error message from the API response body.
                // SECURITY: The error response from the API might contain useful, non-sensitive diagnostics.
                if let errorData = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data),
                   let detail = errorData.error?.message {
                    print("OpenRouterService: API Error Details from response: \(detail)")
                    throw NetworkError.apiError(message: detail, statusCode: httpResponse.statusCode)
                }
                // Fallback if custom error decoding fails.
                throw NetworkError.apiError(message: "Server returned status \(httpResponse.statusCode)", statusCode: httpResponse.statusCode)
            }

            // SECURITY: Decode the successful JSON response.
            let decodedResponse = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
            
            guard let firstChoice = decodedResponse.choices.first else {
                // If the API returns a 2xx but no choices, this is an unexpected API behavior.
                throw NetworkError.noData 
            }

            // SECURITY LOGGING: Log successful response details. The content is chat data and potentially sensitive.
            // Here, only a prefix of the content is logged to minimize exposure in logs.
            print("OpenRouterService: API Response Success - Role: \(firstChoice.message.role), Content (Sanitized): '\(firstChoice.message.content.prefix(100))...'")

            // Return the assistant's message.
            return ChatMessage(role: firstChoice.message.role, content: firstChoice.message.content)

        } catch let error as NetworkError {
            // Re-throw known NetworkError types.
            print("OpenRouterService: NetworkError encountered: \(error.localizedDescription)")
            throw error
        } catch {
            // Catch other errors (e.g., decoding issues not caught above, or other URLSession errors).
            print("OpenRouterService: Generic error during network call: \(error)")
            throw NetworkError.requestFailed(error)
        }
    }
}

// MARK: - OpenRouter Error Response Model
// Model for decoding structured error responses from OpenRouter API.
// SECURITY: This helps in parsing API-provided error messages without exposing raw response data directly.
struct OpenRouterErrorResponse: Codable {
    let error: OpenRouterErrorDetail?
}

struct OpenRouterErrorDetail: Codable {
    let message: String?
    let type: String?
    // Other fields like 'param' or 'code' could be added if the API provides them.
}
