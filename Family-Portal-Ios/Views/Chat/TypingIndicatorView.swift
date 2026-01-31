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
    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.2) % 3
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .offset(y: phase == index ? -4 : 0)
                        .animation(.easeInOut(duration: 0.2), value: phase)
                }
            }
        }
    }
}
