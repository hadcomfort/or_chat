import SwiftUI

struct ChatView: View {
    // ViewModel to manage chat logic, API key, and messages.
    // @StateObject ensures the ViewModel lifecycle is tied to the View.
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) { // Use 0 spacing for tight layout, control with padding.
            // Error Display Area
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(10) // Standard padding
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .onTapGesture { viewModel.errorMessage = nil } // Allow dismissing error.
                    .padding(.horizontal)
                    .padding(.top, 5)
            }
            
            // Message display area
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        // SECURITY: `viewModel.messages` contains chat content, which can be sensitive.
                        // It is displayed here.
                        ForEach(viewModel.messages) { msg in
                            MessageView(message: msg)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                .onChange(of: viewModel.messages.count) { _ in // Auto-scroll on new message.
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Loading Indicator
            if viewModel.isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small) // Smaller progress view.
                    Text("Waiting for OpenRouter...")
                        .font(.caption) // Smaller text.
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(EdgeInsets(top: 8, leading: 15, bottom: 8, trailing: 15)) // Consistent padding.
                .background(Color.secondary.opacity(0.05))
            }

            Divider()

            // Input area
            HStack {
                // SECURITY: `viewModel.currentMessageText` binds to this TextField.
                // This is user-inputted text, potentially sensitive, that will be sent to the API.
                TextField("Type a message...", text: $viewModel.currentMessageText, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .lineLimit(1...5) // Multi-line input.
                    .padding(8)
                    // Using NSVisualEffectView for a modern, blurred background.
                    .background(EffectView(material: .popover, blendingMode: .withinWindow).cornerRadius(10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1) // Subtle border.
                    )
                    // Input disabled if API key is missing or if loading a response.
                    .disabled(viewModel.apiKey == nil || viewModel.isLoading)

                Button(action: {
                    Task { // Use Task for async `viewModel.sendMessage()`.
                        await viewModel.sendMessage()
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: 28, height: 28)
                        // Button color indicates state: disabled if text empty, key missing, or loading.
                        .foregroundColor(viewModel.currentMessageText.isEmpty || viewModel.apiKey == nil || viewModel.isLoading ? .gray : .accentColor)
                }
                .disabled(viewModel.currentMessageText.isEmpty || viewModel.apiKey == nil || viewModel.isLoading)
                .padding(.leading, 5)
                .buttonStyle(PlainButtonStyle()) // Cleaner button style.
            }
            .padding()
            .frame(minHeight: 50) // Ensure input area has a consistent minimum height.
        }
        .frame(minWidth: 400, minHeight: 300, idealHeight: 600) // Define window size constraints.
        // Sheet for API Key Prompt.
        // SECURITY: This sheet is presented when `viewModel.showingAPIKeyPrompt` is true,
        // which occurs if the API key is missing.
        .sheet(isPresented: $viewModel.showingAPIKeyPrompt) {
            APIKeyPromptView(viewModel: viewModel)
        }
        // `.onAppear` is suitable for initial setup, but `checkAPIKey` is in ViewModel's init.
    }
}

// Helper for NSVisualEffectView to create a blurred background effect common in macOS.
struct EffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active // Ensure effect is active.
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}


// View for individual messages in the chat.
struct MessageView: View {
    let message: ChatMessage // Contains role and content.
    var body: some View {
        HStack {
            // Align user messages to the right, assistant messages to the left.
            if message.role == "user" { Spacer(minLength: 20) }
            
            Text(message.content) // SECURITY: Displays chat content.
                .padding(10)
                .background(message.role == "user" ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.2))
                .foregroundColor(message.role == "user" ? .white : .primary)
                .cornerRadius(12)
                .contextMenu { // Allow copying message text.
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    }
                }

            if message.role != "user" { Spacer(minLength: 20) }
        }
        .id(message.id) // Necessary for ScrollViewReader.
        .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
    }
}
    
// View for prompting the user to enter their API Key.
struct APIKeyPromptView: View {
    @ObservedObject var viewModel: ChatViewModel // Shared ViewModel.

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter OpenRouter API Key")
                .font(.title2)
            
            // SECURITY: This TextField is used for API key input.
            // While `SecureField` is typical for passwords, API keys are often long and users
            // might want to paste them. `TextField` allows visibility.
            // The input is bound to `viewModel.inputAPIKey`, which is a @Published String
            // in the ChatViewModel. This property is temporary: it's cleared by the
            // ViewModel immediately after the key is submitted to KeychainService.
            // It is not logged or otherwise exposed.
            TextField("sk-or-...", text: $viewModel.inputAPIKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Text("Your API key will be stored securely in the macOS Keychain.")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            HStack {
                Button("Cancel") { 
                    // Dismisses the sheet. If key is still nil, main UI remains disabled/prompt may reappear.
                    viewModel.showingAPIKeyPrompt = false 
                }
                Button("Save Key") {
                    // SECURITY: `saveAndUseAPIKey()` in ViewModel handles the secure submission
                    // of `viewModel.inputAPIKey` to `KeychainService`.
                    viewModel.saveAndUseAPIKey()
                }
                .disabled(viewModel.inputAPIKey.isEmpty) // Prevent saving an empty key.
            }
        }
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
        .frame(width: 380, height: 250) // Defined size for the sheet.
    }
}

// Preview provider for ChatView.
struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView()
            // Provide a ChatViewModel for the preview to function correctly.
            .environmentObject(ChatViewModel())
    }
}
