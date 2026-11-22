import SwiftUI

/// What the share sheet needs to offer a recap link: the event, the server's revision of each performance, and why a link can't be made right now, if it can't.
struct RecapLinkContext {
    let eventId: Int
    let revisions: [Int: Int]
    let blocker: String?
}

/// The share sheet's **Recap link** section: publish the preview at an account-free page, then copy or send it, and turn off this event's links. Online only, never queued.
struct RecapLinksSection: View {
    let context: RecapLinkContext
    let share: CompetitionShare
    let labels: ActivityLabels

    @Environment(ActivityService.self) private var service

    @State private var links: [RecapLinkDTO] = []
    @State private var loadError: String?
    @State private var expiresInDays = 30
    @State private var confirming = false
    @State private var publishing = false
    @State private var created: URL?
    @State private var copied = false
    @State private var error: String?
    @State private var revoking: Int?

    private typealias Strings = Copy.share.recapLink

    var body: some View {
        Section {
            if let created {
                createdRows(created)
            } else if let blocker = context.blocker {
                Text(blocker)
                    .foregroundStyle(.secondary)
            } else if confirming {
                Text(Strings.confirm(count(share.routines.count), showsNames: share.routines.contains { $0.roster != nil }, lasts: lasts))
                Button {
                    Task { await publish() }
                } label: {
                    HStack {
                        Text(Strings.publish)
                        if publishing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(publishing || share.routines.isEmpty)
                Button(Strings.cancel, role: .cancel) { confirming = false }
                    .disabled(publishing)
            } else {
                Picker(Strings.lasts, selection: $expiresInDays) {
                    ForEach(Strings.expiryOptions, id: \.days) { option in
                        Text(option.label).tag(option.days)
                    }
                }
                Button {
                    error = nil
                    confirming = true
                } label: {
                    Label(Strings.create, systemImage: "link")
                }
                .disabled(share.routines.isEmpty)
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(Strings.title)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.explain)
                Text(Strings.turnOffNote)
            }
        }
        .task(id: context.eventId) { await load() }

        if loadError != nil || !links.isEmpty {
            Section(Strings.existing) {
                if let loadError {
                    Text(loadError)
                        .foregroundStyle(.secondary)
                }
                ForEach(links) { link in
                    linkRow(link)
                }
            }
        }
    }

    @ViewBuilder
    private func createdRows(_ url: URL) -> some View {
        Text(Strings.created)
            .font(.footnote)
            .foregroundStyle(.secondary)
        Text(url.absoluteString)
            .font(.footnote.monospaced())
            .textSelection(.enabled)
            .lineLimit(2)
        Button {
            UIPasteboard.general.url = url
            copied = true
        } label: {
            Label(copied ? Copy.share.copied : Strings.copy, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        ShareLink(item: url) {
            Label(Copy.share.action, systemImage: "square.and.arrow.up")
        }
    }

    private func linkRow(_ link: RecapLinkDTO) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.createdBy(day(link.createdAt), link.createdByName))
                Text(details(link))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if link.canRevoke {
                Button(link.expired ? Strings.remove : Strings.turnOff, role: .destructive) {
                    Task { await revoke(link) }
                }
                .buttonStyle(.borderless)
                .disabled(revoking != nil)
            }
        }
        .opacity(link.expired ? 0.6 : 1)
    }

    private var lasts: String {
        expiresInDays > 0 ? Strings.forDays(expiresInDays) : Strings.untilTurnedOff
    }

    private func count(_ n: Int) -> String {
        "\(n) \((n == 1 ? labels.entry : labels.entryPlural).lowercased())"
    }

    private func details(_ link: RecapLinkDTO) -> String {
        let expiry = link.expired
            ? Strings.expired
            : link.expiresAt.map { Strings.expires(day($0)) } ?? Strings.noExpiry
        return [count(link.routineCount), link.snapshotLabel.isEmpty ? nil : link.snapshotLabel, expiry]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Created and expiry times are real instants, so they read in the phone's own time zone.
    private func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func load() async {
        do {
            links = try await service.recapLinks(eventId: context.eventId)
            loadError = nil
        } catch {
            if context.blocker == nil { loadError = Strings.loadFailed }
        }
    }

    private func publish() async {
        guard !publishing else { return }
        publishing = true
        error = nil
        defer { publishing = false }
        do {
            let response = try await service.createRecapLink(
                eventId: context.eventId,
                expiresInDays: expiresInDays,
                recap: share.recapInput(revisions: context.revisions)
            )
            created = URL(string: response.url)
            copied = false
            confirming = false
            links.insert(response.link, at: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func revoke(_ link: RecapLinkDTO) async {
        guard revoking == nil else { return }
        revoking = link.id
        error = nil
        defer { revoking = nil }
        do {
            try await service.revokeRecapLink(id: link.id)
            links.removeAll { $0.id == link.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
