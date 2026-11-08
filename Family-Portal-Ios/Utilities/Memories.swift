import Foundation

/// A visit's memories: the seed that fixes the server's draw, which one is featured, and what earlier visits already showed — `currentVisit` and `markSeen` in frontend/lib/memories.ts.
/// A visit lasts as long as the app process, so going back to Home finds the same memory; the seen list is frozen when the visit starts and kept on the device between launches.
@MainActor
@Observable
final class MemoryVisit {
    static let shared = MemoryVisit()

    static let seenKey = "com.familyrecord.memoriesSeen"
    static let seenLimit = 80

    let seed: Int
    let seen: [String]
    var index = 0

    @ObservationIgnored private let defaults: UserDefaults

    init(seed: Int = Int.random(in: 0..<1_000_000_000), defaults: UserDefaults = .standard) {
        self.seed = seed
        self.defaults = defaults
        seen = defaults.stringArray(forKey: Self.seenKey) ?? []
    }

    /// The featured memory out of `memories`, by the visit's position.
    func featured(_ memories: [MemoryDTO]) -> MemoryDTO? {
        memories.isEmpty ? nil : memories[index % memories.count]
    }

    func advance(count: Int) {
        guard count > 0 else { return }
        index = (index + 1) % count
    }

    func markSeen(_ key: String) {
        var next = (defaults.stringArray(forKey: Self.seenKey) ?? []).filter { $0 != key }
        next.append(key)
        defaults.set(Array(next.suffix(Self.seenLimit)), forKey: Self.seenKey)
    }

    /// One of `list`, picked by the visit's seed and `salt` — a person's id — so different pages pick differently but each holds still.
    func pick<T>(_ list: [T], salt: Int = 0) -> T? {
        list.isEmpty ? nil : list[abs(seed &+ salt) % list.count]
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: seenKey)
    }
}

/// How a memory reads — `memoryNames` and `memoryWhen` in frontend/lib/memories.ts.
nonisolated enum Memories {
    /// First names joined as the web joins them: "Clara", "Clara & Rowan", "Clara, Rowan & Jake".
    static func names(_ memory: MemoryDTO, people: [Int: (name: String, birthday: Date?)]) -> String {
        let names = memory.personIds.compactMap { people[$0]?.name.firstName }
        guard names.count > 2 else { return names.joined(separator: " & ") }
        return names.dropLast().joined(separator: ", ") + " & " + names[names.count - 1]
    }

    /// An exact record's long date and, for one person, their age then. Anything approximate keeps the family's own wording rather than inventing a day.
    static func when(_ memory: MemoryDTO, people: [Int: (name: String, birthday: Date?)]) -> String {
        if let recordTime = memory.recordTime, !recordTime.isExactDay {
            return recordTime.label
        }
        let date = memory.date.displayDay().formatted(date: .long, time: .omitted)
        guard memory.personIds.count == 1, let birthday = people[memory.personIds[0]]?.birthday else { return date }
        let age = AgeSteps.photoAge(birthday: birthday, at: memory.date)
        return age.isEmpty ? date : "\(date) · \(age)"
    }

    /// The year a memory is filed under on a "through the years" strip: its calendar year when exact, otherwise its own label.
    static func yearLabel(_ memory: MemoryDTO) -> String {
        if let recordTime = memory.recordTime, !recordTime.isExactDay {
            return recordTime.label
        }
        return String(memory.date.recordDay.year ?? 0)
    }

    /// One photo memory per year, the server's order deciding which, up to `limit`, oldest first.
    static func throughTheYears(_ memories: [MemoryDTO], limit: Int = 6) -> [MemoryDTO] {
        var seen: Set<String> = []
        var picked: [MemoryDTO] = []
        for memory in memories where !memory.photoIds.isEmpty && picked.count < limit {
            if seen.insert(yearLabel(memory)).inserted { picked.append(memory) }
        }
        return picked.sorted { ($0.recordTime?.start ?? $0.date.recordDayKey) < ($1.recordTime?.start ?? $1.date.recordDayKey) }
    }
}
