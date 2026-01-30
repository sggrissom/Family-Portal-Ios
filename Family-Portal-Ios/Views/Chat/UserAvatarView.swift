import SwiftUI

struct UserAvatarView: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(backgroundColor)
            .clipShape(Circle())
    }

    private var initial: String {
        String(name.prefix(1)).uppercased()
    }

    private var backgroundColor: Color {
        // Consistent color based on name hash
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .mint,
            .teal, .cyan, .blue, .indigo, .purple, .pink
        ]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}
