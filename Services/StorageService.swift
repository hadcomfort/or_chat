import Foundation

// Service to handle local storage of chat messages.
// SECURITY: Stores conversation data (ChatMessage objects) in the app's sandboxed Application Support directory.
// This data is stored as plain JSON and is *not encrypted at rest* by this service.
// Protection relies on macOS's default file system permissions for user-specific data and app sandboxing.
// For enhanced security of chat content, disk encryption (e.g., FileVault) should be enabled by the user,
// or application-level encryption could be added to this service in the future.
struct StorageService {
    private static let fileName = "chatHistory.json" // The file where chat history is stored.

    // Returns the URL for the chat history file in the Application Support directory.
    // SECURITY: Ensures data is stored in a standard, app-specific, user-private location.
    private static func getChatHistoryFileURL() -> URL? {
        guard let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Log error: Cannot find Application Support directory. This is a system-level issue.
            print("StorageService: Error - Cannot find Application Support directory for storing chat history.")
            return nil
        }

        // Create a subdirectory for the app if it doesn't exist.
        // SECURITY: Using the Bundle Identifier for the subdirectory name ensures it's unique to this app,
        // preventing conflicts and isolating its data.
        let appDirectoryName = Bundle.main.bundleIdentifier ?? "OpenRouterChat"
        let appDirectoryURL = appSupportDirectory.appendingPathComponent(appDirectoryName)

        do {
            // `withIntermediateDirectories: true` means it won't fail if the directory already exists.
            try FileManager.default.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            return appDirectoryURL.appendingPathComponent(fileName)
        } catch {
            // Log error: Could not create app-specific subdirectory. This might indicate a permissions issue.
            print("StorageService: Error creating directory \(appDirectoryURL.path): \(error.localizedDescription)")
            return nil
        }
    }

    // Saves the chat messages to a local JSON file.
    // SECURITY: The `messages` array, containing potentially sensitive chat content, is written to disk.
    // As mentioned, this data is not encrypted by this function.
    static func saveMessages(_ messages: [ChatMessage]) {
        guard let fileURL = getChatHistoryFileURL() else {
            // Log error: File URL is nil, cannot save.
            print("StorageService: Error - Chat history file URL is nil. Cannot save messages.")
            return
        }

        do {
            // Encode messages to JSON Data.
            // `ChatMessage` includes `id` (UUID), `role` (String), and `content` (String).
            // All these properties are saved locally.
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted // For readability if the file is manually inspected.
            let data = try encoder.encode(messages)
            
            // Write data to file using atomic write for data integrity.
            // SECURITY: `.atomicWrite` ensures that the file is either fully written or not at all, preventing data corruption.
            try data.write(to: fileURL, options: [.atomicWrite])
            // Log success for debugging.
            print("StorageService: Chat history saved successfully to \(fileURL.path). Messages count: \(messages.count)")
        } catch {
            // Log error: Failed to save messages. This could be due to disk space, permissions, or encoding errors.
            print("StorageService: Error saving chat history: \(error.localizedDescription)")
        }
    }

    // Loads chat messages from the local JSON file.
    // SECURITY: Reads potentially sensitive chat content from disk.
    // Returns an empty array if the file doesn't exist or an error occurs during loading/decoding.
    static func loadMessages() -> [ChatMessage] {
        guard let fileURL = getChatHistoryFileURL(), FileManager.default.fileExists(atPath: fileURL.path) else {
            // Log info: File doesn't exist or URL is nil, returning empty history. This is normal on first launch.
            if let url = getChatHistoryFileURL() { // Check URL again for logging path if it exists
                print("StorageService: Info - Chat history file not found at \(url.path). Starting with empty history.")
            } else {
                print("StorageService: Info - Chat history file URL is nil. Starting with empty history.")
            }
            return []
        }

        do {
            // Read data from file.
            let data = try Data(contentsOf: fileURL)
            // Decode JSON data to [ChatMessage].
            let messages = try JSONDecoder().decode([ChatMessage].self, from: data)
            // Log success for debugging.
            print("StorageService: Chat history loaded successfully from \(fileURL.path). \(messages.count) messages found.")
            return messages
        } catch {
            // Log error: Failed to load or decode messages.
            // This might happen if the file is corrupted. Returning an empty array prevents app crash.
            // SECURITY: A corrupted file could be an indicator of tampering, though more likely data corruption.
            print("StorageService: Error loading or decoding chat history: \(error.localizedDescription). Returning empty history.")
            // Consider renaming/deleting the corrupt file to allow starting fresh next time.
            return [] 
        }
    }
    
    // Deletes the chat history file from disk.
    // SECURITY: This action permanently removes the stored chat conversation from the user's device.
    static func deleteChatHistory() {
        guard let fileURL = getChatHistoryFileURL(), FileManager.default.fileExists(atPath: fileURL.path) else {
            print("StorageService: Info - Chat history file not found or URL is nil. Nothing to delete.")
            return
        }
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("StorageService: Chat history deleted successfully from \(fileURL.path).")
        } catch {
            // Log error: Failed to delete chat history. Could be a permissions issue.
            print("StorageService: Error deleting chat history: \(error.localizedDescription)")
        }
    }
}
