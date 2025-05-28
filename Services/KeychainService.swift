import Foundation
import Security

// Service to handle secure storage and retrieval of the API key using macOS Keychain
struct KeychainService {
    // Define a unique service name and account name for the Keychain item.
    // SECURITY: Using a bundle identifier for `service` ensures uniqueness for this application's keychain items.
    // `account` is specific to the piece of data being stored (OpenRouter API Key).
    private static let service = Bundle.main.bundleIdentifier ?? "com.example.OpenRouterChat"
    private static let account = "openRouterAPIKey"

    // MARK: - Save API Key
    // Saves the API key to the Keychain.
    // SECURITY: Keychain items are stored encrypted by the macOS operating system.
    // `kSecClassGenericPassword` is used here to store a generic secret, suitable for API keys.
    static func saveAPIKey(_ apiKey: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            // SECURITY: If data conversion fails, an error is thrown to prevent storing corrupted data.
            throw KeychainError.dataConversionError
        }

        // Query to find an existing item.
        // SECURITY: `kSecAttrService` and `kSecAttrAccount` are used to uniquely identify this keychain item,
        // ensuring we operate on the correct item.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Attributes for the new item or attributes to update.
        // SECURITY: `kSecValueData` holds the actual secret (API key) to be stored.
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        // Check if item already exists to decide whether to add or update.
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
            case errSecSuccess, errSecInteractionNotAllowed: // errSecInteractionNotAllowed can occur in non-interactive contexts.
                // Item found, update it.
                // SECURITY: Updates the existing item with new data if present.
                let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
                if updateStatus != errSecSuccess {
                    throw KeychainError.operationError(status: updateStatus)
                }
            case errSecItemNotFound:
                // Item not found, add it.
                var newItemQuery = query
                newItemQuery[kSecValueData as String] = data
                // SECURITY: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` ensures the keychain item is accessible only when
                // the current device is unlocked. It cannot be migrated to a new device via an unencrypted backup
                // and is not available if the device is locked. This is a strong protection level.
                newItemQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

                let addStatus = SecItemAdd(newItemQuery as CFDictionary, nil)
                if addStatus != errSecSuccess {
                    throw KeychainError.operationError(status: addStatus)
                }
            default:
                // SECURITY: Handle any other unexpected Keychain status codes by throwing an error.
                throw KeychainError.operationError(status: status)
        }
        // Log success for debugging.
        // SECURITY: Crucially, the API key itself is *never* logged by this service, only status messages.
        print("KeychainService: API Key saved to Keychain successfully.")
    }

    // MARK: - Retrieve API Key
    // Retrieves the API key from the Keychain.
    // Returns nil if the key is not found or an error occurs.
    // SECURITY: Data is retrieved directly from the encrypted Keychain store.
    static func retrieveAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, // Specifies the item class.
            kSecAttrService as String: service,           // Uniquely identifies based on service.
            kSecAttrAccount as String: account,           // Uniquely identifies based on account.
            kSecReturnData as String: kCFBooleanTrue!,    // Request the actual data of the item.
            kSecMatchLimit as String: kSecMatchLimitOne   // Expect only one item to match.
        ]

        var item: CFTypeRef? // Holds the retrieved item.
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            if status == errSecItemNotFound {
                // This is a normal condition if the key hasn't been set yet.
                print("KeychainService: API Key not found in Keychain.")
            } else {
                // Log error for debugging.
                // SECURITY: The API key itself is not part of the error message.
                print("KeychainService: Error retrieving API Key from Keychain: OSStatus \(status)")
            }
            return nil
        }

        // SECURITY: Ensure data is correctly converted back to a String using UTF-8 encoding.
        guard let apiKey = String(data: data, encoding: .utf8) else {
            print("KeychainService: Failed to convert Keychain data to String.")
            return nil
        }
        
        // Log success for debugging.
        // SECURITY: The API key itself is *never* logged.
        print("KeychainService: API Key retrieved from Keychain.")
        return apiKey
    }

    // MARK: - Delete API Key
    // Deletes the API key from the Keychain.
    // Useful for testing or if the user wants to remove the key.
    static func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        // Not finding the item is not an error for deletion, it means it's already gone.
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.operationError(status: status)
        }
        // Log success for debugging.
        // SECURITY: The API key itself is not involved in this logging.
        print("KeychainService: API Key deleted from Keychain (if it existed).")
    }
}

// MARK: - Keychain Error Enum
// Custom errors for Keychain operations, providing more context than raw OSStatus codes.
enum KeychainError: Error, LocalizedError {
    case dataConversionError
    case operationError(status: OSStatus)
    case unknownError // Should ideally not be used.

    var errorDescription: String? {
        switch self {
        case .dataConversionError:
            return "Keychain Error: Failed to convert API key to storable data format."
        case .operationError(let status):
            // Provides the specific OSStatus code for debugging.
            return "Keychain Error: A Keychain operation failed with OSStatus \(status)."
        case .unknownError:
            return "Keychain Error: An unknown error occurred."
        }
    }
}
