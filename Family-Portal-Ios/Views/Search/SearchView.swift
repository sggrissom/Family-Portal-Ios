import SwiftData
import SwiftUI

/// Global search — the web's `/search`. Pushed onto the current tab rather than presented, so opening a result and coming back finds the results as they were.
/// Groups come in the web's fixed order, and an empty one is hidden.
struct SearchView: View {
    let initialQuery: String?

    @Environment(AppNavigator.self) private var navigator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.name) private var people: [Person]
    @Query private var familyTags: [FamilyTag]

    @State private var model = SearchModel { request in
        try await APIClient.shared.callRPC(.search, payload: request)
    }
    @State private var text = ""
    @State private var didStart = false
    @FocusState private var isFieldFocused: Bool

    /// This device's copies of the answer's photos and moments, by server id. Fetched per answer rather than queried, so the screen doesn't redraw on every sync.
    @State private var localPhotos: [Int: Photo] = [:]
    @State private var localMoments: [Int: Milestone] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !chips.isEmpty {
                    chipRow
                }
                content
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(Copy.search.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: Copy.search.placeholder)
        .searchFocused($isFieldFocused)
        .onChange(of: text) { _, new in
            model.type(new)
        }
        .onSubmit(of: .search) {
            Task { await model.search(text) }
        }
        .task {
            // Coming back from a result re-runs `.task`; the results are already here.
            guard !didStart else { return }
            didStart = true
            if let initialQuery, !initialQuery.isEmpty {
                text = initialQuery
                await model.search(initialQuery)
            } else {
                isFieldFocused = true
            }
        }
        .task(id: LocalKey(response: model.currentResponse)) {
            resolveLocal()
        }
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        if model.trimmedQuery.isEmpty {
            emptyQuery
        } else if model.failed {
            Text(Copy.search.failed)
                .foregroundStyle(.secondary)
        } else if let response = model.currentResponse {
            VStack(alignment: .leading, spacing: 24) {
                if response.isTextOnly {
                    Text(Copy.search.textOnly)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if response.isEmpty {
                    nothingMatched
                } else {
                    groups(response)
                }
            }
            .opacity(model.isLoading ? 0.6 : 1)
        } else {
            Text(Copy.search.searching)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyQuery: some View {
        let family = people.filter { !$0.isPregnancy }
        return VStack(alignment: .leading, spacing: 24) {
            if !family.isEmpty {
                group(Copy.search.family) {
                    FlowLayout(spacing: 8) {
                        ForEach(family) { person in
                            Button(person.name.firstName) {
                                searchNow(person.name.firstName)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var nothingMatched: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.search.nothing(model.trimmedQuery))
            ForEach(chips) { chip in
                Button(Copy.search.tryWithout(chip.label)) {
                    Task { await model.remove(chip.kind) }
                }
            }
        }
    }

    // MARK: - Chips

    /// The server's understanding once it answers; until then the phone's own reading of the words, so the chips keep up with typing.
    private var chips: [SearchChip] {
        guard !model.trimmedQuery.isEmpty else { return [] }
        if model.isCurrent, let response = model.response {
            return SearchResults.chips(response.understood, names: names)
        }
        let parsed = SearchQuery.parse(model.trimmedQuery, people: queryPeople, tags: queryTags, ignore: model.ignore)
        return SearchResults.chips(parsed, names: names)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text(Copy.search.understood)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(chips) { chip in
                    Button {
                        Task { await model.remove(chip.kind) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(chip.label)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Copy.search.remove(chip.label))
                }
            }
        }
    }

    // MARK: - Groups

    @ViewBuilder
    private func groups(_ response: SearchResponseDTO) -> some View {
        let terms = SearchText.terms(response.understood.text)
        let g = Copy.search.groups.self

        if !response.people.isEmpty {
            group(g.people) {
                ForEach(response.people, id: \.id) { person in
                    personRow(person)
                }
            }
        }

        if !response.moments.isEmpty {
            group(g.moments, action: response.momentCount > response.moments.count ? AnyView(
                Button(Copy.search.showAllMoments(response.momentCount)) {
                    Task { await model.showAllMoments() }
                }
            ) : nil) {
                moments(response, terms: terms)
            }
        }

        if !response.photos.isEmpty {
            group(g.photos, action: response.morePhotos ? AnyView(
                Button(Copy.search.seeAllPhotos) {
                    seeAllPhotos(response.understood)
                }
            ) : nil) {
                photoStrip(response)
            }
        }

        if !response.tags.isEmpty {
            group(g.tags) {
                ForEach(response.tags) { tag in
                    Button {
                        var filter = PhotoFilter()
                        filter.tagRemoteIds = [tag.id]
                        navigator.openPhotos(filter)
                    } label: {
                        SearchRow(detail: Copy.search.tagPhotos) {
                            Circle()
                                .fill(TagColor.color(forHex: tag.color))
                                .frame(width: 12, height: 12)
                        } title: {
                            Text(highlighted(tag.name, terms: terms))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if !response.places.isEmpty {
            group(g.places) {
                ForEach(response.places, id: \.key) { place in
                    Button {
                        var filter = PhotoFilter()
                        filter.placeKey = place.key
                        filter.placeName = place.name
                        navigator.openPhotos(filter)
                    } label: {
                        SearchRow {
                            Image(systemName: "mappin.and.ellipse")
                        } title: {
                            Text(highlighted(place.name, terms: terms))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if !response.activities.isEmpty {
            group(g.activities) {
                ForEach(response.activities, id: \.key) { hit in
                    activityRow(hit, terms: terms)
                }
            }
        }

        if !response.books.isEmpty {
            group(g.books) {
                ForEach(response.books) { book in
                    Button {
                        navigator.push(.book(id: book.id, title: book.title))
                    } label: {
                        SearchRow(detail: book.personNames.isEmpty ? nil : Copy.search.by(book.personNames)) {
                            Image(systemName: "book.closed")
                        } title: {
                            Text(highlighted(book.title, terms: terms))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, action: AnyView? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                if let action {
                    action
                        .font(.subheadline)
                }
            }
            content()
        }
    }

    // MARK: - People

    private func personRow(_ person: PersonDTO) -> some View {
        let local = localPeople[person.id]
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                if let local {
                    navigator.push(.person(local.id))
                }
            } label: {
                Group {
                    if let local {
                        PersonRowView(person: local, avatarSize: 44)
                    } else {
                        PersonRowView(
                            name: person.name,
                            relationship: person.relationship,
                            birthday: person.birthday,
                            isPregnancy: person.isPregnancy,
                            profilePhotoRemoteId: person.profilePhotoId,
                            crop: ProfilePhotoCrop(x: person.profileCropX, y: person.profileCropY, scale: person.profileCropScale),
                            avatarSize: 44
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(local == nil)

            if let local {
                HStack(spacing: 16) {
                    Button(Copy.search.quick.moments) {
                        navigator.push(.person(local.id, tab: .story))
                    }
                    Button(Copy.search.quick.photos) {
                        navigator.push(.person(local.id, tab: .photos))
                    }
                    if !local.isPregnancy {
                        Button(Copy.search.quick.growth) {
                            navigator.push(.person(local.id, tab: .growth))
                        }
                    }
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
                .padding(.leading, 56)
            }
        }
    }

    // MARK: - Moments

    @ViewBuilder
    private func moments(_ response: SearchResponseDTO, terms: [String]) -> some View {
        let interviews = Dictionary(response.interviews.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let responsePeople = Dictionary(response.people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        ForEach(Array(SearchResults.momentItems(response.moments).enumerated()), id: \.offset) { _, item in
            switch item {
            case .moment(let moment):
                momentRow(moment, terms: terms)
            case .interview(let answers):
                let personId = answers.answers.first?.personId ?? 0
                let name = localPeople[personId]?.name ?? responsePeople[personId]?.name
                let birthday = localPeople[personId]?.birthday ?? responsePeople[personId]?.birthday
                InterviewCardView(model: InterviewCardModel(
                    answers: answers,
                    personName: name?.firstName,
                    birthday: birthday,
                    interview: interviews[answers.interviewId]
                ))
            }
        }
    }

    private func momentRow(_ moment: MilestoneDTO, terms: [String]) -> some View {
        let category = MilestoneCategory(rawValue: moment.category) ?? .other
        let local = localMoments[moment.id]
        let name = localPeople[moment.personId]?.name.firstName
        var line = Text("")
        if let name {
            line = Text("\(name) ").bold()
        }
        var entry = Text(highlighted(moment.displayText, terms: terms))
        if category == .quote {
            entry = entry.italic()
        }
        return Button {
            if let local {
                navigator.push(.milestone(local.id))
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundStyle(category.color)
                VStack(alignment: .leading, spacing: 2) {
                    (line + entry)
                        .fixedSize(horizontal: false, vertical: true)
                    if category == .quote, !moment.context.isEmpty {
                        (Text("— ") + Text(highlighted(moment.context, terms: terms)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(moment.milestoneDate.displayDay().formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(local == nil)
    }

    // MARK: - Photos

    private func photoStrip(_ response: SearchResponseDTO) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(SearchResults.resolve(response.photos.map(\.image.id), in: localPhotos), id: \.id) { photo in
                    ServerPhotoCell(remoteId: photo.id, local: photo.local)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func seeAllPhotos(_ understood: SearchUnderstoodDTO) {
        let localIds = Dictionary(people.compactMap { person in person.serverId.map { ($0, person.id) } }, uniquingKeysWith: { first, _ in first })
        navigator.openPhotos(SearchResults.photoFilter(understood, localIds: localIds), search: true)
    }

    // MARK: - Activities

    @ViewBuilder
    private func activityRow(_ hit: ActivityHitDTO, terms: [String]) -> some View {
        let detail = [hit.detail, hit.kind != ActivityHitDTO.activity ? hit.startDate.map { $0.displayDay().formatted(date: .abbreviated, time: .omitted) } ?? "" : ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let row = SearchRow(detail: detail.isEmpty ? nil : detail) {
            Image(systemName: "trophy")
        } title: {
            Text(highlighted(hit.name, terms: terms))
        }
        switch hit.kind {
        case ActivityHitDTO.season:
            NavigationLink {
                SeasonView(seasonId: hit.id, seasonName: hit.name)
            } label: {
                row
            }
            .buttonStyle(.plain)
        case ActivityHitDTO.event:
            Button {
                navigator.push(.event(id: hit.id, name: hit.name))
            } label: {
                row
            }
            .buttonStyle(.plain)
        default:
            Button {
                navigator.push(.activities)
            } label: {
                row
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Data

    private var localPeople: [Int: Person] {
        people.byServerId()
    }

    /// Everyone's name by server id, for the chips: the answer's people first, then this device's.
    private var names: [Int: String] {
        var names = Dictionary(people.compactMap { person in person.serverId.map { ($0, person.name) } }, uniquingKeysWith: { first, _ in first })
        for person in model.response?.people ?? [] {
            names[person.id] = person.name
        }
        return names
    }

    private var queryPeople: [SearchQuery.Person] {
        people.compactMap { person in
            person.serverId.map {
                SearchQuery.Person(id: $0, name: person.name, relationship: person.relationship, isPregnancy: person.isPregnancy)
            }
        }
    }

    private var queryTags: [SearchQuery.Tag] {
        familyTags.compactMap { tag in tag.serverId.map { SearchQuery.Tag(id: $0, name: tag.name) } }
    }

    private func searchNow(_ query: String) {
        text = query
        Task { await model.search(query) }
    }

    private struct LocalKey: Equatable {
        var photoIds: [Int] = []
        var momentIds: [Int] = []

        init(response: SearchResponseDTO?) {
            photoIds = response?.photos.map(\.image.id) ?? []
            momentIds = response?.moments.map(\.id) ?? []
        }
    }

    private func resolveLocal() {
        guard let response = model.currentResponse else { return }
        localPhotos = Dictionary(response.photos.compactMap { item in fetchPhoto(item.image.id).map { (item.image.id, $0) } }, uniquingKeysWith: { first, _ in first })
        localMoments = Dictionary(response.moments.compactMap { moment in fetchMoment(moment.id).map { (moment.id, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    private func fetchPhoto(_ remoteId: Int) -> Photo? {
        let key = String(remoteId)
        var descriptor = FetchDescriptor<Photo>(predicate: #Predicate { $0.remoteId == key })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchMoment(_ remoteId: Int) -> Milestone? {
        let key = String(remoteId)
        var descriptor = FetchDescriptor<Milestone>(predicate: #Predicate { $0.remoteId == key })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Highlighting

    private func highlighted(_ text: String, terms: [String]) -> AttributedString {
        SearchHighlight.attributed(text, terms: terms)
    }
}

/// Matched words marked the way the web's `<mark>` does.
enum SearchHighlight {
    static func attributed(_ text: String, terms: [String]) -> AttributedString {
        var out = AttributedString()
        var at = text.startIndex
        for range in SearchText.highlightRanges(in: text, terms: terms) {
            out += AttributedString(String(text[at..<range.lowerBound]))
            var mark = AttributedString(String(text[range]))
            mark.backgroundColor = Color.yellow.opacity(0.35)
            mark.inlinePresentationIntent = .stronglyEmphasized
            out += mark
            at = range.upperBound
        }
        out += AttributedString(String(text[at...]))
        return out
    }
}

/// A plain result row: an icon, a title and a line of detail.
private struct SearchRow<Icon: View, Title: View>: View {
    var detail: String?
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let title: () -> Title

    var body: some View {
        HStack(spacing: 12) {
            icon()
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                title()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
