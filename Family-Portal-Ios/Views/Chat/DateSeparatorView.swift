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
            return date.formatted(.dateTime.weekday(.wide))
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}
