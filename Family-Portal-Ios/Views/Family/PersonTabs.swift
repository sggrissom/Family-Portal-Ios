import SwiftUI
import SwiftData

// MARK: - Story

/// A short overview, highlight cards, then everything recorded for the person grouped into age chapters (`Story.chapters`) with a "Grew …" line each and a link to everyone at that age. The web's Story tab as built.
struct PersonStoryTab: View {
    let person: Person
    let onShowActivities: () -> Void
    /// The same `GetPersonPhotoInsights` answer the Photos tab shows; its Growing up faces lead the highlights.
    var insights: GetPersonPhotoInsightsResponseDTO? = nil
    /// Opens the Photos tab, where the full Growing up timeline sits at the top.
    var onShowGrowingUp: () -> Void = {}
    /// Switches to one of the person's other tabs, for a highlight's "All …" link.
    var onShowTab: (PersonTab) -> Void = { _ in }

    @Environment(AppNavigator.self) private var navigator

    @Environment(ActivityService.self) private var activityService
    @State private var season = ActivityScreenState<GetPersonSeasonResponseDTO>()
    @Query private var people: [Person]

    /// Whether nobody under eighteen was born before this person.
    private var isOldestChild: Bool {
        guard let birthday = person.birthday else { return true }
        return !people.contains { other in
            guard other.id != person.id, !other.isPregnancy, let otherBirthday = other.birthday else { return false }
            return otherBirthday < birthday && AgeSteps.monthsOld(birthday: otherBirthday, at: Date().localRecordDay()) < 18 * 12
        }
    }

    private var today: String { WhenEntry.localDateString(Date()) }

    /// Whether anyone else has a birthday to be compared at, which a chapter's "Everyone at" link needs.
    private var hasOthersToCompare: Bool {
        people.contains { $0.id != person.id && !$0.isPregnancy && $0.birthday != nil }
    }

    var body: some View {
        let days = DaySummaries.summarize(
            DayRecords(
                photos: person.photos,
                growth: person.growthData,
                milestones: person.milestones,
                appearances: (season.value?.appearances ?? []).map { TimelineAppearanceDTO(detail: $0, personIds: []) }
            ),
            people: [person],
            range: birthdayRange
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PersonOverview(person: person, season: season.value, onShowActivities: onShowActivities)

                VStack(spacing: 10) {
                    PersonHighlights(
                        person: person,
                        growingUp: insights?.growingUp ?? [],
                        onShowGrowingUp: onShowGrowingUp,
                        onShowTab: onShowTab
                    )
                    // The oldest child has nobody older to compare with, so the card would only ever be empty.
                    if !isOldestChild {
                        SameAgeHighlight(person: person)
                    }
                }

                if days.isEmpty {
                    Text(Copy.person.nothingYet(person.name.firstName))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(chapters(days)) { chapter in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(Story.chapterTitle(chapter.age))
                                    .font(.title3.weight(.bold))
                                Spacer()
                                if !chapter.grew.isEmpty {
                                    Text(chapter.grew)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let age = chapter.age, hasOthersToCompare, let remoteId = person.serverId {
                                Button(Copy.person.othersAtAge(age)) {
                                    navigator.push(.sameAge(ageMonths: max(age * 12, 6), fromRemoteId: remoteId, view: .details))
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            DaySummaryList(days: chapter.days, today: today, subjectId: person.id)
                        }
                    }
                }
            }
            .padding()
        }
        .task(id: person.remoteId) {
            guard let remoteId = person.serverId else { return }
            await season.load(activityService.personSeason(personId: remoteId))
        }
    }

    /// Childhood birthdays from the person's first record on, so a Story doesn't open on a run of empty years.
    private var birthdayRange: DaySummaries.BirthdayWindow? {
        guard let birthday = person.birthday, !person.isPregnancy else { return nil }
        return .init(from: birthday.recordDayKey, to: today, maxAge: DaySummaries.childhoodBirthdays, fromFirstRecord: true)
    }

    private func chapters(_ days: [DaySummary]) -> [StoryChapter] {
        guard let birthday = person.birthday else {
            return [StoryChapter(age: nil, days: days, grew: "")]
        }
        return Story.chapters(days, birthday: birthday)
    }
}

/// The top of a person's Story: Growing up, one of their quotes, an answer from their latest interview and a few pieces of artwork, each leading to its tab. The quote and answer rotate with the visit — the web's `ProfileHighlights`.
struct PersonHighlights: View {
    let person: Person
    let growingUp: [PortraitPhotoDTO]
    let onShowGrowingUp: () -> Void
    let onShowTab: (PersonTab) -> Void

    @State private var openMilestone: Milestone?
    private let visit = MemoryVisit.shared

    private var salt: Int { person.serverId ?? 0 }

    var body: some View {
        let quotes = person.milestones.filter { $0.category == .quote }.sorted { $0.date < $1.date }
        let artwork = person.milestones.filter { $0.category == .artwork && !$0.photoRemoteIds.isEmpty }.sorted { $0.date > $1.date }
        let answers = person.milestones.filter { $0.interviewId > 0 && !$0.descriptionText.isEmpty }
        let latest = answers.map(\.date).max()
        let answer = visit.pick(answers.filter { $0.date == latest }.sorted { $0.questionId < $1.questionId }, salt: salt)
        let quote = visit.pick(quotes, salt: salt)
        // One face is not a timeline, so Growing up waits for two, as the Photos tab does.
        let hasGrowingUp = growingUp.count > 1

        if hasGrowingUp || quote != nil || answer != nil || !artwork.isEmpty {
            VStack(spacing: 10) {
                if hasGrowingUp {
                    GrowingUpPreview(portraits: growingUp, onShowAll: onShowGrowingUp)
                }
                if let quote {
                    card(title: Copy.person.theySaid(person.name.firstName), link: Copy.person.allQuotes(quotes.count), tab: .quotes) {
                        Button { openMilestone = quote } label: {
                            Text("“\(quote.displayText)”")
                                .font(.title3.weight(.semibold))
                                .italic()
                                .multilineTextAlignment(.leading)
                                .lineLimit(4)
                        }
                        .buttonStyle(.plain)
                        Text(quote.dateText(.abbreviated))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let answer {
                    card(title: Copy.person.fromInterview, link: Copy.person.allInterviews, tab: .interviews) {
                        Text(Interviews.shortQuestion(answer.context))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Button { openMilestone = answer } label: {
                            Text(answer.displayText)
                                .font(.title3.weight(.semibold))
                                .multilineTextAlignment(.leading)
                                .lineLimit(4)
                        }
                        .buttonStyle(.plain)
                        Text(answer.dateText(.abbreviated))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !artwork.isEmpty {
                    card(title: Copy.person.tabs.artwork, link: Copy.person.artworkCount(artwork.count), tab: .artwork) {
                        HStack(spacing: 6) {
                            ForEach(artwork.prefix(3)) { piece in
                                Button { openMilestone = piece } label: {
                                    Color(.secondarySystemBackground)
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay { RemotePhotoView(remoteId: piece.photoRemoteIds[0], size: .thumb) }
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(piece.displayText)
                            }
                        }
                    }
                }
            }
            .sheet(item: $openMilestone) { milestone in
                MilestoneDetailSheetView(milestone: milestone)
            }
        }
    }

    private func card<Content: View>(title: String, link: String, tab: PersonTab, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
            Button(link) { onShowTab(tab) }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Everyone else at the person's age today, one line each — their face then and what was recorded — leading to the Same age page. The web's `SameAgeCard`; nothing until someone else has a record at this age.
struct SameAgeHighlight: View {
    let person: Person

    @Environment(NetworkMonitor.self) private var network
    @Environment(AppNavigator.self) private var navigator
    @State private var loader = SameAgeLoader()

    var body: some View {
        // A container, not a `Group`, so the `.task` runs before there is anything to show.
        VStack(alignment: .leading, spacing: 0) {
            if let response = loader.response, let remoteId = person.serverId {
                let others = response.rows.filter { $0.person.id != remoteId && !$0.isEmpty }
                if !others.isEmpty {
                    card(response: response, others: others, remoteId: remoteId)
                }
            }
        }
        .task(id: person.serverId) {
            guard !person.isPregnancy, let remoteId = person.serverId, let birthday = person.birthday else { return }
            let months = AgeSteps.monthsOld(birthday: birthday, at: Date())
            guard months >= 0 else { return }
            await loader.load(ageMonths: months, fromPersonId: remoteId, isConnected: network.isConnected)
        }
    }

    private func card(response: GetSameAgeResponseDTO, others: [SameAgeRowDTO], remoteId: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.sameAge.atThisAge(AgeSteps.ageTitle(response.ageMonths)))
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            ForEach(others.prefix(4)) { row in
                HStack(spacing: 10) {
                    face(row)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.person.name.firstName)
                            .font(.subheadline.weight(.semibold))
                        Text(SameAgeText.summary(row))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Button(Copy.sameAge.seeAll) {
                navigator.push(.sameAge(ageMonths: response.ageMonths, fromRemoteId: remoteId, view: .details))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func face(_ row: SameAgeRowDTO) -> some View {
        if let portrait = row.portraits.first {
            FaceCropView(photoId: portrait.photoId, box: portrait.box, size: 36)
        } else if let photoId = row.photoIds.first {
            RemotePhotoView(remoteId: photoId, size: .thumb)
        } else {
            Text(String(row.person.name.prefix(1)))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.tertiarySystemFill))
        }
    }
}

/// A handful of Growing up faces spread across the whole timeline — first and last included — linking to the full collection on the Photos tab. The web's `GrowingUpPreview`.
struct GrowingUpPreview: View {
    let portraits: [PortraitPhotoDTO]
    let onShowAll: () -> Void

    /// At most five, evenly spaced from the first portrait to the last, as the web picks them.
    static func spread<T>(_ items: [T], count limit: Int = 5) -> [T] {
        let count = min(limit, items.count)
        guard count > 1 else { return Array(items.prefix(count)) }
        return (0..<count).map { i in
            items[Int((Double(i * (items.count - 1)) / Double(count - 1)).rounded())]
        }
    }

    var body: some View {
        Button(action: onShowAll) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Copy.person.growingUp)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Self.spread(portraits), id: \.photoId) { portrait in
                        VStack(spacing: 4) {
                            FaceCropView(photoId: portrait.photoId, box: portrait.box, size: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(GetPersonPhotoInsightsResponseDTO.label(for: portrait))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(width: 56)
                    }
                }
                Text(Copy.person.seeGrowingUp)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.person.growingUp)
        .accessibilityHint(Copy.person.seeGrowingUp)
    }
}

/// The top of Story: latest height and weight with how long ago they were taken, and the season in progress.
struct PersonOverview: View {
    let person: Person
    let season: GetPersonSeasonResponseDTO?
    let onShowActivities: () -> Void

    /// A reading older than this next to a fresh one is no longer "latest" — the web's `STALE_METRIC_MONTHS`.
    private static let staleMonths = 12

    @State private var openMeasurement: GrowthData?

    var body: some View {
        let readings = MeasurementType.allCases.compactMap { Checkup.latest(of: person.growthData, type: $0) }
        let lastMeasured = readings.map(\.date).max()
        let latest = readings.filter { reading in
            guard let lastMeasured else { return false }
            return AgeSteps.monthsOld(birthday: reading.date, at: lastMeasured) <= Self.staleMonths
        }
        let seasons = activeSeasons

        if !latest.isEmpty || !seasons.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(latest) { record in
                    Button {
                        openMeasurement = record
                    } label: {
                        HStack {
                            Text(record.measurementType.label)
                                .foregroundStyle(.secondary)
                            Text(MeasurementConversion.format(record))
                                .fontWeight(.semibold)
                            if let label = percentile(record) {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if let lastMeasured {
                    Text(Copy.person.measured(Checkup.timeAgo(lastMeasured, now: Date())))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(seasons) { summary in
                    Button(action: onShowActivities) {
                        Text(seasonLine(summary))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .sheet(item: $openMeasurement) { MeasurementDetailSheetView(measurement: $0) }
        }
    }

    private func percentile(_ record: GrowthData) -> String? {
        guard let months = MeasurementConversion.ageMonths(of: record), months <= GrowthPercentiles.maxAgeMonths else { return nil }
        return GrowthPercentiles.percentileLabel(
            value: record.value,
            unit: record.unit,
            ageMonths: months,
            gender: person.gender,
            type: record.measurementType
        )
    }

    private var activeSeasons: [SeasonSummaryDTO] {
        guard let season else { return [] }
        let currentDay = Date().localRecordDay()
        return season.seasons.filter { summary in
            guard let start = summary.startDate.serverDate, start <= currentDay else { return false }
            return summary.endDate.serverDate.map { $0 >= currentDay } ?? true
        }
    }

    /// "🏆 Competition Season · 3 entries · next: Nuvo Nashville"
    private func seasonLine(_ summary: SeasonSummaryDTO) -> String {
        let entries = season?.entries.filter { $0.entry.seasonId == summary.id }.count ?? 0
        let startOfToday = Date().localRecordDay()
        let next = season?.appearances
            .filter { $0.entry.seasonId == summary.id && $0.event.startDate >= startOfToday }
            .min { $0.event.startDate < $1.event.startDate }
        var parts = ["🏆 \(summary.name)", Copy.person.entries(entries)]
        if let next { parts.append(Copy.person.next(next.event.name)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Quotes

/// Everything the person has said that was worth writing down, oldest first, with the age they said it at. The web's Quotes tab.
struct PersonQuotesTab: View {
    let person: Person

    @State private var openMilestone: Milestone?

    private var quotes: [Milestone] {
        person.milestones.filter { $0.category == .quote }.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if quotes.isEmpty {
                    Text(Copy.person.noQuotes(person.name.firstName))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(quotes) { quote in
                    Button {
                        openMilestone = quote
                    } label: {
                        card(quote)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .sheet(item: $openMilestone) { milestone in
            MilestoneDetailSheetView(milestone: milestone)
        }
    }

    private func card(_ quote: Milestone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(quote.displayText)
                .font(.title3)
                .italic()
            if !quote.context.isEmpty {
                Text(quote.context)
                    .foregroundStyle(.secondary)
            }
            Text([quote.hasExactDate ? person.age(on: quote.date) : nil, quote.dateText(.abbreviated)]
                .compactMap { $0 }
                .joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(MilestoneCategory.quote.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

// MARK: - Artwork

/// What the person has made, newest first, each piece shown by the first photo of it with the age they made it at. The web's Artwork tab.
struct PersonArtworkTab: View {
    let person: Person

    @State private var openMilestone: Milestone?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    private var pieces: [Milestone] {
        person.milestones.filter { $0.category == .artwork }.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            if pieces.isEmpty {
                Text(Copy.person.noArtwork(person.name.firstName))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(pieces) { piece in
                    Button {
                        openMilestone = piece
                    } label: {
                        card(piece)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .sheet(item: $openMilestone) { milestone in
            MilestoneDetailSheetView(milestone: milestone)
        }
    }

    private func card(_ piece: Milestone) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { cover(piece) }
                .overlay(alignment: .bottomTrailing) {
                    if piece.photoRemoteIds.count > 1 {
                        Text("+\(piece.photoRemoteIds.count - 1)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(piece.descriptionText)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
            Text((piece.hasExactDate ? person.age(on: piece.date) : nil) ?? piece.dateText(.abbreviated))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// The local copy when this device has one, so a piece photographed here shows before the server has thumbnails.
    @ViewBuilder
    private func cover(_ piece: Milestone) -> some View {
        if let remoteId = piece.photoRemoteIds.first {
            let local = person.photos.first { $0.serverId == remoteId }
            PhotoThumbnailView(imageData: local?.imageData, title: "", remoteId: String(remoteId))
        } else {
            Rectangle()
                .fill(MilestoneCategory.artwork.color.opacity(0.12))
                .overlay {
                    Image(systemName: MilestoneCategory.artwork.icon)
                        .font(.largeTitle)
                        .foregroundStyle(MilestoneCategory.artwork.color)
                }
        }
    }
}

// MARK: - Photos

/// The gallery scoped to this person, with date and tag filters, and a way into the Photos tab already filtered to them.
struct PersonPhotosTab: View {
    let person: Person
    /// Growing up and Often photographed with, above the grid. `nil` until the server answers, and never offline without a cached answer.
    var insights: GetPersonPhotoInsightsResponseDTO? = nil

    @Environment(AppNavigator.self) private var navigator
    @Query private var people: [Person]
    @State private var filter = PhotoFilter()
    @State private var isFilterPresented = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    /// SwiftData does not order to-many relationships.
    private var photos: [Photo] {
        filter.apply(to: person.photos.sorted { $0.photoDate > $1.photoDate })
    }

    var body: some View {
        ScrollView {
            HStack {
                Button(Copy.person.openInPhotos) { navigator.openPhotos(of: person.id) }
                    .font(.subheadline)
                Spacer()
                Button {
                    isFilterPresented = true
                } label: {
                    Image(systemName: filter.hasPanelFilters
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter photos")
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if let insights {
                insightsSection(insights)
            }

            if photos.isEmpty {
                Text(Copy.person.noPhotos)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(photos) { photo in
                        NavigationLink {
                            PhotoDetailView(photoId: photo.id, openedFrom: person.id)
                        } label: {
                            PhotoThumbnailView(imageData: photo.imageData, title: photo.title, remoteId: photo.remoteId, videoDurationMs: photo.videoBadgeDuration)
                        }
                    }
                }
                .padding(4)
            }
        }
        .sheet(isPresented: $isFilterPresented) {
            NavigationStack {
                PhotoFilterView(filter: $filter, showsServerOptions: false)
            }
        }
    }
}

/// Someone from Often photographed with, resolved to the local roster.
private struct Companion {
    let person: Person
    let count: Int
}

extension PersonPhotosTab {
    @ViewBuilder
    fileprivate func insightsSection(_ insights: GetPersonPhotoInsightsResponseDTO) -> some View {
        // One face is not a timeline, so the web waits for two.
        if insights.growingUp.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text(Copy.person.growingUp)
                    .font(.headline)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(insights.growingUp, id: \.photoId) { portrait in
                            growingUpItem(portrait)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 8)
        }

        let companions = insights.oftenWith.compactMap { with in
            localPerson(remoteId: with.person.id).map { Companion(person: $0, count: with.count) }
        }
        if !companions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(Copy.person.oftenWith)
                    .font(.headline)
                FlowLayout(spacing: 8) {
                    ForEach(companions, id: \.person.id) { companion in
                        companionChip(companion.person, count: companion.count)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func growingUpItem(_ portrait: PortraitPhotoDTO) -> some View {
        let label = GetPersonPhotoInsightsResponseDTO.label(for: portrait)
        let content = VStack(spacing: 4) {
            FaceCropView(photoId: portrait.photoId, box: portrait.box, size: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 76)
        // Bound the whole link, including its caption, to this timeline item.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)

        if let photo = RemotePhotoResolution.resolve([portrait.photoId], in: person.photos).first {
            NavigationLink {
                PhotoDetailView(photoId: photo.id, openedFrom: person.id)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            // Insights can arrive before the local photo mirror or its person
            // relationship. Keep the portrait usable through the server route.
            NavigationLink {
                RemotePhotoDetailView(remoteId: portrait.photoId)
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }

    /// The photos of both of them. The tab already shows only this person's photos, so filtering on the other person alone is the intersection; a second tap clears it.
    private func companionChip(_ other: Person, count: Int) -> some View {
        let selected = filter.personLocalIds == [other.id]
        return Button {
            filter.personLocalIds = selected ? [] : [other.id]
        } label: {
            HStack(spacing: 4) {
                Text(other.name)
                Text("\(count)")
                    .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? .white : .primary)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(other.name), \(count) photos together")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func localPerson(remoteId: Int) -> Person? {
        people.first { $0.serverId == remoteId }
    }
}

// MARK: - Growth

/// Latest height and weight with their own dates and percentiles, the chart with optional faint sibling curves, the measurement list, and **Measure**.
struct PersonGrowthTab: View {
    let person: Person

    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]
    @Environment(AddFlow.self) private var addFlow
    @Environment(AuthService.self) private var authService

    @State private var type: MeasurementType = .height
    @State private var showSiblings = false
    @State private var zoom: AgeRange?
    @State private var openMeasurement: GrowthData?

    /// Children under eighteen, other than this person — the web's `CHILD_MONTHS`.
    private var siblings: [Person] {
        people.filter { other in
            guard other.id != person.id, !other.isPregnancy, let birthday = other.birthday else { return false }
            return AgeSteps.monthsOld(birthday: birthday, at: Date().localRecordDay()) < 18 * 12
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                latest

                HStack {
                    Picker(Copy.person.metric, selection: $type) {
                        ForEach(MeasurementType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if authService.access.canContribute(to: person) {
                        Button(Copy.person.measure) {
                            addFlow.open(.measurement(personId: person.id))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if !siblings.isEmpty {
                    Toggle(Copy.person.showSiblings, isOn: $showSiblings)
                        .font(.subheadline)
                }

                chart

                list
            }
            .padding()
        }
        .onChange(of: type) { _, _ in zoom = nil }
        .sheet(item: $openMeasurement) { MeasurementDetailSheetView(measurement: $0) }
    }

    private var latest: some View {
        HStack(spacing: 12) {
            ForEach(MeasurementType.allCases, id: \.self) { kind in
                if let record = Checkup.latest(of: person.growthData, type: kind) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(MeasurementConversion.format(record))
                            .font(.headline)
                        Text(record.date.displayDay().formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let months = MeasurementConversion.ageMonths(of: record),
                           let label = GrowthPercentiles.percentileLabel(value: record.value, unit: record.unit, ageMonths: months, gender: person.gender, type: kind) {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if let birthday = person.birthday, !person.isPregnancy {
            let main = AgeSeries(
                id: person.id,
                label: person.name.firstName,
                color: AgeSeries.palette[0],
                points: AgeChart.chartPoints(person.growthData, birthday: birthday, type: type)
            )
            let nowMonths = Double(AgeSteps.monthsOld(birthday: birthday, at: Date().localRecordDay()))
            let maxAge = max(nowMonths + 1, 12)
            let others: [AgeSeries] = showSiblings ? siblings.enumerated().compactMap { index, sibling in
                guard let siblingBirthday = sibling.birthday else { return nil }
                let points = AgeChart.chartPoints(sibling.growthData, birthday: siblingBirthday, type: type).filter { $0.ageMonths <= maxAge }
                guard !points.isEmpty else { return nil }
                return AgeSeries(
                    id: sibling.id,
                    label: sibling.name.firstName,
                    color: AgeSeries.palette[(index + 1) % AgeSeries.palette.count],
                    points: points,
                    faint: true
                )
            } : []
            let band = nowMonths <= 240 ? AgeChart.percentileBand(gender: person.gender, type: type, from: 0, to: maxAge) : []

            if main.points.isEmpty && others.isEmpty {
                Text(Copy.person.noMeasurements)
                    .foregroundStyle(.secondary)
            } else {
                AgeChartView(series: others + [main], band: band, type: type, zoom: $zoom) { id in
                    openMeasurement = (person.growthData + siblings.flatMap(\.growthData)).first { $0.id == id }
                }
            }
        }
    }

    private var list: some View {
        let records = person.growthData
            .filter { $0.measurementType == type }
            .sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(records) { record in
                Button {
                    openMeasurement = record
                } label: {
                    MeasurementRowView(measurement: record)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}
