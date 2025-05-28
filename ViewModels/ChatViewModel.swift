import SwiftUI
import Combine

class ChatViewModel: ObservableObject {
    // MARK: - API Key Properties
    // Holds the API key fetched from Keychain. Nil if not set or not retrieved.
    // SECURITY: This property holds the sensitive API key in memory *after* it's been retrieved from Keychain.
    // It's used by OpenRouterService for API calls. Avoid logging or unnecessarily exposing it.
    @Published var apiKey: String?
    
    // Controls the presentation of the API key input sheet.
    @Published var showingAPIKeyPrompt = false
    
    // Bound to the TextField in APIKeyPromptView for user input.
    // SECURITY: This property temporarily holds the API key as the user types it.
    // It is cleared immediately after the key is submitted to KeychainService.
    // It is not logged.
    @Published var inputAPIKey: String = ""
    
    // MARK: - Chat State Properties
    // Array of chat messages, forming the conversation history.
    // SECURITY: This array holds chat content (user and assistant messages) in memory.
    // This data is potentially sensitive. It is also persisted to local disk by StorageService.
    @Published var messages: [ChatMessage] = [] {
        didSet {
            // Save messages whenever the array changes.
            // SECURITY: This action triggers `StorageService.saveMessages()`, which writes chat content to a local file.
            // The data is stored unencrypted by `StorageService` as per its design.
            StorageService.saveMessages(messages)
            print("ChatViewModel: messages.didSet, saving messages. Count: \(messages.count)")
        }
    }
    
    // Bound to the message input TextField in ChatView.
    // SECURITY: Holds the user's currently typed message before sending. Potentially sensitive.
    @Published var currentMessageText: String = ""
    
    // Indicates if an API call is in progress.
    @Published var isLoading: Bool = false
    
    // Holds error messages to be displayed to the user in the UI.
    // SECURITY: Error messages should not contain raw sensitive data from API responses or internal states.
    @Published var errorMessage: String? = nil

    private let openRouterService = OpenRouterService()

    init() {
        // Attempt to load API key from Keychain on initialization.
        checkAPIKey() // Sets `self.apiKey` and `self.showingAPIKeyPrompt` if needed.

        // Load chat messages from local storage.
        // SECURITY: `StorageService.loadMessages()` reads potentially sensitive chat history from an unencrypted local file.
        let loadedMessages = StorageService.loadMessages()
        if !loadedMessages.isEmpty {
            // Assign to messages. This will trigger `didSet` and re-save, which is redundant but harmless here.
            // For optimization, one might load into a temporary variable and then assign to `_messages` directly
            // if there was a way to bypass `didSet` only during init, but direct assignment is fine.
            self.messages = loadedMessages
            print("ChatViewModel init: Loaded \(loadedMessages.count) messages from history.")
        }
        
        // Logging the state after initialization.
        if apiKey == nil {
            print("ChatViewModel init: API Key not found or not set. User will be prompted if needed.")
        } else {
            print("ChatViewModel init: API Key is present.")
        }
    }

    // Checks for the API key in Keychain and updates the ViewModel's state.
    func checkAPIKey() {
        // SECURITY: `KeychainService.retrieveAPIKey()` securely fetches the key.
        self.apiKey = KeychainService.retrieveAPIKey()
        if self.apiKey == nil {
            // If API key is not found, set flag to show prompt.
            // This is a key part of the app's startup sequence to ensure API access.
            showingAPIKeyPrompt = true
        }
    }

    // Saves the API key entered by the user (from `inputAPIKey`) to Keychain.
    func saveAndUseAPIKey() {
        guard !inputAPIKey.isEmpty else {
            self.errorMessage = "API Key cannot be empty."
            return
        }
        do {
            // SECURITY: `KeychainService.saveAPIKey()` securely stores the key.
            // `self.inputAPIKey` (which holds the key temporarily during input) is used here.
            try KeychainService.saveAPIKey(inputAPIKey)
            self.apiKey = inputAPIKey // Update the in-memory key.
            self.showingAPIKeyPrompt = false // Dismiss the prompt.
            self.inputAPIKey = "" // SECURITY: Clear the temporary input field for the API key.
            self.errorMessage = nil // Clear any errors.
            print("ChatViewModel: API Key saved successfully via KeychainService.")
        } catch {
            // SECURITY: Error messages should be user-friendly and not expose sensitive details of the failure.
            self.errorMessage = "Failed to save API Key: \(error.localizedDescription)"
            print("ChatViewModel: Failed to save API Key: \(error.localizedDescription)")
        }
    }
    
    // Clears the API key from Keychain and the ViewModel.
    func clearAPIKey() {
        do {
            // SECURITY: `KeychainService.deleteAPIKey()` securely removes the key.
            try KeychainService.deleteAPIKey()
            self.apiKey = nil // Clear the in-memory key.
            self.showingAPIKeyPrompt = true // Show prompt to enter a new key.
            // Note: Chat history (`self.messages`) is not cleared here. User must use `clearChatHistory` for that.
            self.errorMessage = "API Key cleared. Please enter a new key to send messages."
            print("ChatViewModel: API Key cleared from Keychain.")
        } catch {
            self.errorMessage = "Failed to delete API key: \(error.localizedDescription)"
            print("ChatViewModel: Failed to delete API key: \(error.localizedDescription)")
        }
    }

    // Sends the `currentMessageText` to the OpenRouter API.
    @MainActor // Ensure UI updates (isLoading, errorMessage, messages) are on the main thread.
    func sendMessage() async {
        guard !currentMessageText.isEmpty else {
            self.errorMessage = "Cannot send an empty message."
            return
        }
        guard apiKey != nil else {
            // This check should ideally prevent UI from allowing send if key is nil, but double-check.
            self.errorMessage = "API Key is not set. Please provide an API Key."
            self.showingAPIKeyPrompt = true
            return
        }

        // Create user message and append to local messages array.
        // SECURITY: `currentMessageText` (user input) becomes part of the `messages` array.
        let userMessage = ChatMessage(text: currentMessageText, isFromUser: true)
        // Appending to `messages` triggers `didSet`, which saves all messages to local storage.
        messages.append(userMessage) 
        
        let messageTextForRetry = currentMessageText // Store before clearing, for potential retry/error scenarios.
        currentMessageText = "" // Clear input field immediately.

        isLoading = true
        errorMessage = nil

        // Prepare messages for the API. `ChatMessage.CodingKeys` ensures only `role` and `content` are sent.
        let apiMessages = messages.map { ChatMessage(role: $0.role, content: $0.content) }

        do {
            // SECURITY: `openRouterService.sendChatRequest` handles the secure transmission of data,
            // including fetching the API key from Keychain on demand.
            print("ChatViewModel: Calling OpenRouterService to send messages.")
            let responseMessage = try await openRouterService.sendChatRequest(messages: apiMessages)
            // Append assistant's response. This also triggers `didSet` and saves to local storage.
            messages.append(responseMessage)
            print("ChatViewModel: Received API response and updated messages.")
        } catch let error as OpenRouterService.NetworkError {
            self.errorMessage = "API Error: \(error.localizedDescription)"
            // Rollback: Remove the user's message if the API call failed, as it wasn't successfully processed.
            if messages.last?.id == userMessage.id {
                messages.removeLast() // This also triggers `didSet` to save the rolled-back state.
            }
            currentMessageText = messageTextForRetry // Restore user's text to input field.
            print("ChatViewModel: sendMessage failed with NetworkError: \(error.localizedDescription)")
        } catch { // Catch any other unexpected errors.
            self.errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
            if messages.last?.id == userMessage.id {
                messages.removeLast()
            }
            currentMessageText = messageTextForRetry
            print("ChatViewModel: sendMessage failed with unexpected error: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // Clears all chat history from `StorageService` and the ViewModel.
    func clearChatHistory() {
        // SECURITY: `StorageService.deleteChatHistory()` removes the unencrypted chat history file from disk.
        StorageService.deleteChatHistory()
        // `messages.removeAll()` clears the in-memory array and triggers `didSet`,
        // which then saves an empty array to disk (effectively clearing the file content if it wasn't deleted).
        messages.removeAll()
        print("ChatViewModel: User cleared chat history.")
        self.errorMessage = "Chat history has been cleared." // Provide user feedback.
    }
}
