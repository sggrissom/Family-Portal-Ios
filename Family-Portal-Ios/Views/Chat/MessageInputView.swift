import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onTyping: () -> Void
    let onSend: () -> Void
    /// "Message Grissoms…"; a read-only member gets a field that says why it's off.
    var placeholder = "Message"
    var canPost = true

    var body: some View {
        HStack(spacing: 12) {
            TextField(canPost ? placeholder : "You can read this chat but not post", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)
                .focused(isFocused)
                .disabled(!canPost)
                .onChange(of: text) { _, _ in
                    onTyping()
                }
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        canPost && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

