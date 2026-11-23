import SwiftUI
import SwiftData
import UIKit
import os

/// The family's public page at /f/<slug> (web: pages/family-page/edit-family-page.tsx). Online only: nothing here is queued.
struct FamilyPageView: View {
    let family: FamilyInfoDTO

    @Environment(NetworkMonitor.self) private var networkMonitor
    @Query(sort: \Photo.photoDate, order: .reverse) private var photos: [Photo]

    @State private var current: FamilyPageSettingsResponseDTO?
    @State private var form = FamilyPageSettingsDTO()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var confirmingPublish = false
    @State private var confirmingUnpublish = false

    private let service = FamilyPageService()
    private typealias Words = Copy.familyPage

    private var canEdit: Bool { current?.canEdit == true && networkMonitor.isConnected && !isSaving }

    /// Finished photos this family owns, newest first; the server refuses anything else.
    private var photoChoices: [Int] {
        let local = photos.compactMap { photo -> Int? in
            guard photo.familyRemoteId == family.id, !photo.isVideo, photo.status == 0 else { return nil }
            return photo.serverId
        }
        let known = Set(local)
        return form.photoIds.filter { !known.contains($0) } + local
    }

    var body: some View {
        Form {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let current {
                editor(current)
            }
        }
        .navigationTitle(Words.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            Words.publish,
            isPresented: $confirmingPublish,
            titleVisibility: .hidden
        ) {
            Button(current?.published == true ? Words.republish : Words.publish) {
                Task { await publish() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Words.confirmPublish("/f/\(normalizedSlug)"))
        }
        .confirmationDialog(
            Words.unpublish,
            isPresented: $confirmingUnpublish,
            titleVisibility: .hidden
        ) {
            Button(Words.unpublish, role: .destructive) {
                Task { await unpublish() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Words.confirmUnpublish)
        }
    }

    private var normalizedSlug: String {
        form.slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    @ViewBuilder
    private func editor(_ current: FamilyPageSettingsResponseDTO) -> some View {
        Section {
            statusRows(current)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(Words.intro)
                if !current.canEdit {
                    Text(Words.adminsOnly)
                } else if !networkMonitor.isConnected {
                    Text(Words.offline)
                }
            }
        }

        Section {
            HStack(spacing: 2) {
                Text("/f/")
                    .foregroundStyle(.secondary)
                TextField(Words.address, text: $form.slug)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(Words.address)
            }
            TextField(Words.pageTitle, text: $form.title)
            TextField(Words.introPlaceholder, text: $form.intro, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityLabel(Words.introLabel)
        } header: {
            Text(Words.address)
        } footer: {
            Text(Words.addressHint)
        }
        .disabled(!canEdit)

        Section {
            if current.people.isEmpty {
                Text(Words.noPeople).foregroundStyle(.secondary)
            }
            ForEach(current.people) { person in
                memberRows(person, people: current.people)
            }
        } header: {
            Text(Words.people)
        } footer: {
            Text(Words.peopleHint)
        }
        .disabled(!canEdit)

        Section {
            photoGrid
        } header: {
            Text(Words.photos(FamilyPage.maxPhotos))
        } footer: {
            Text(Words.photosHint)
        }
        .disabled(!canEdit)

        Section {
            Toggle(Words.indexable, isOn: $form.indexable)
        } footer: {
            Text(Words.indexableHint)
        }
        .disabled(!canEdit)

        if current.canEdit {
            Section {
                Button(isSaving ? Words.publishing : current.published ? Words.republish : Words.publish) {
                    confirmingPublish = true
                }
                .disabled(!canEdit || normalizedSlug.isEmpty)
                if current.published {
                    Button(Words.unpublish, role: .destructive) {
                        confirmingUnpublish = true
                    }
                    .disabled(!canEdit)
                }
            } footer: {
                Text(Words.caching)
            }
        }

        Section(Words.preview) {
            FamilyPagePreview(preview: FamilyPage.preview(form, people: current.people))
        }
    }

    @ViewBuilder
    private func statusRows(_ current: FamilyPageSettingsResponseDTO) -> some View {
        if current.published, let url = URL(string: current.url) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Words.published).font(.caption).foregroundStyle(.secondary)
                Link(current.url, destination: url)
                    .font(.callout)
                if let publishedAt = current.publishedAt {
                    Text(Words.publishedBy(publishedAt.formatted(date: .abbreviated, time: .omitted), current.publishedByName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                UIPasteboard.general.string = current.url
                copied = true
            } label: {
                Label(copied ? Words.copied : Words.copyLink, systemImage: "doc.on.doc")
            }
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } else {
            Text(Words.notPublished).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func memberRows(_ person: FamilyPagePersonDTO, people: [FamilyPagePersonDTO]) -> some View {
        let index = form.members.firstIndex { $0.personId == person.id }
        Toggle(person.name, isOn: Binding(
            get: { index != nil },
            set: { _ in FamilyPage.toggleMember(&form, people: people, person: person) }
        ))
        if let index {
            Group {
                TextField(Words.shownName, text: $form.members[index].name)
                    .accessibilityLabel("\(Words.shownName) for \(person.name)")
                TextField(Words.line, text: $form.members[index].line)
                    .accessibilityLabel("\(Words.line) for \(person.name)")
                if person.ageYears != nil {
                    Toggle(Words.showAge, isOn: $form.members[index].showAge)
                }
                if person.profilePhotoId > 0 {
                    Toggle(Words.showPhoto, isOn: $form.members[index].showPhoto)
                } else {
                    Text(Words.noProfilePhoto)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 16)
        }
    }

    @ViewBuilder
    private var photoGrid: some View {
        let choices = photoChoices
        if choices.isEmpty {
            Text(Words.noPhotos).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
                ForEach(choices, id: \.self) { photoId in
                    let selected = form.photoIds.contains(photoId)
                    Button {
                        FamilyPage.togglePhoto(&form, photoId: photoId)
                    } label: {
                        RemotePhotoView(remoteId: photoId, size: .thumb)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 80)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: 6).strokeBorder(.tint, lineWidth: 3)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.white, .tint)
                                        .padding(4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func load() async {
        isLoading = current == nil
        defer { isLoading = false }
        do {
            apply(try await service.settings(familyId: family.id))
            errorMessage = nil
        } catch {
            AppLog.sync.error("Loading the family page failed: \(String(describing: error), privacy: .public)")
            errorMessage = current == nil ? Words.loadFailed : error.localizedDescription
        }
    }

    private func publish() async {
        isSaving = true
        defer { isSaving = false }
        do {
            apply(try await service.publish(familyId: family.id, settings: form))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unpublish() async {
        isSaving = true
        defer { isSaving = false }
        do {
            apply(try await service.unpublish(familyId: family.id))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ response: FamilyPageSettingsResponseDTO) {
        current = response
        form = response.settings
        copied = false
    }
}

/// What visitors will see, drawn with the signed-in photo URLs (web: FamilyPageView).
private struct FamilyPagePreview: View {
    let preview: FamilyPage.Preview

    var body: some View {
        VStack(spacing: 12) {
            Text(preview.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if !preview.intro.isEmpty {
                Text(preview.intro)
                    .multilineTextAlignment(.center)
            }
            if !preview.members.isEmpty {
                FlowLayout(spacing: 16) {
                    ForEach(Array(preview.members.enumerated()), id: \.offset) { _, member in
                        VStack(spacing: 2) {
                            PersonAvatarView(
                                name: member.name,
                                profilePhotoRemoteId: member.photoId,
                                crop: ProfilePhotoCrop(
                                    x: member.cropX == 0 ? nil : member.cropX,
                                    y: member.cropY == 0 ? nil : member.cropY,
                                    scale: member.cropScale == 0 ? nil : member.cropScale
                                ),
                                size: 64
                            )
                            Text(member.name).font(.subheadline.bold())
                            if let age = member.ageYears {
                                Text(Copy.familyPage.age(age)).font(.caption).foregroundStyle(.secondary)
                            }
                            if !member.line.isEmpty {
                                Text(member.line).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 110)
                        .multilineTextAlignment(.center)
                    }
                }
            }
            if !preview.photoIds.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], spacing: 6) {
                    ForEach(preview.photoIds, id: \.self) { photoId in
                        RemotePhotoView(remoteId: photoId, size: .medium)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
