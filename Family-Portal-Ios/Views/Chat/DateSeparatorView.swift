import SwiftUI

struct DateSeparatorView: View {
    let date: Date

    var body: some View {
        HStack {
            line
            Text(dateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            line
        }
        .padding(.vertical, 8)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(height: 1)
    }

    private var dateLabel: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day,
                  daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}
