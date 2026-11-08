import SwiftUI

/// Explore's rotating previews, picked with the visit's seed so they hold still for the visit: everyone at one childhood age, things they said, and one person through the years — the web's `/explore` previews. Online only; offline the directory stands alone.
@MainActor
@Observable
final class ExplorePreviews {
    struct Years {
        let personId: UUID
        let personName: String
        let memories: [MemoryDTO]
    }

    private(set) var sameAge: GetSameAgeResponseDTO?
    private(set) var said: [MemoryDTO] = []
    private(set) var years: Years?
    private var loadedFor: Int?

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    /// `candidates` are the people a "through the years" strip could be about, in strip order.
    func load(candidates: [(id: UUID, serverId: Int, name: String)], visit: MemoryVisit) async {
        guard loadedFor != visit.seed else { return }
        let today = WhenEntry.localDateString(Date())

        async let quotes: GetMemoriesResponseDTO? = try? apiClient.callRPC(
            .getMemories,
            payload: GetMemoriesRequestDTO(today: today, seed: visit.seed, limit: 4, kinds: ["quote"])
        )
        async let ages: GetSameAgeResponseDTO? = try? apiClient.callRPC(
            .getSameAge,
            payload: GetSameAgeRequestDTO(ageMonths: nil, fromPersonId: 0, today: today, includeAvailableAges: true)
        )
        let person = visit.pick(candidates)
        async let personMemories = memories(of: person?.serverId, today: today, seed: visit.seed)

        said = await quotes?.memories ?? []

        if let ages = await ages {
            let shared = { (options: [SameAgeOptionDTO]?) in
                (options ?? []).filter { $0.peopleCount >= 2 && AgeSteps.invitingAge($0.ageMonths) }
            }
            let pictured = shared(ages.portraitAges)
            if let age = visit.pick(pictured.isEmpty ? shared(ages.availableAges) : pictured) {
                let answer: GetSameAgeResponseDTO? = age.ageMonths == ages.ageMonths
                    ? ages
                    : try? await apiClient.callRPC(.getSameAge, payload: GetSameAgeRequestDTO(ageMonths: age.ageMonths, fromPersonId: 0, today: today))
                sameAge = answer.flatMap { $0.rows.filter(Self.hasRecords).count >= 2 ? $0 : nil }
            }
        }

        if let person, let memories = await personMemories?.memories {
            let picked = Memories.throughTheYears(memories)
            years = picked.count >= 2 ? Years(personId: person.id, personName: person.name, memories: picked) : nil
        }

        loadedFor = visit.seed
    }

    private func memories(of serverId: Int?, today: String, seed: Int) async -> GetMemoriesResponseDTO? {
        guard let serverId else { return nil }
        return try? await apiClient.callRPC(
            .getMemories,
            payload: GetMemoriesRequestDTO(today: today, seed: seed, limit: 24, personId: serverId)
        )
    }

    nonisolated static func hasRecords(_ row: SameAgeRowDTO) -> Bool {
        row.height != nil || row.weight != nil || !row.milestones.isEmpty || !row.contextMilestones.isEmpty
            || !row.photoIds.isEmpty || !row.portraits.isEmpty
    }
}
