import SwiftUI

struct TypingIndicatorView: View {
    let typingUsers: [String]

    var body: some View {
        HStack(spacing: 4) {
            TypingDotsView()

            Text(typingText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typingText: String {
        switch typingUsers.count {
        case 0:
            return ""
        case 1:
            return "\(typingUsers[0]) is typing..."
        case 2:
            return "\(typingUsers[0]) and \(typingUsers[1]) are typing..."
        default:
            return "Several people are typing..."
        }
    }
}

struct TypingDotsView: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .offset(y: animationPhase == index ? -4 : 0)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}
