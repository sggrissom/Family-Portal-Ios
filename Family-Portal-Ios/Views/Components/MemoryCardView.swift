import SwiftData
import SwiftUI

/// A memory's kind as a symbol, matching the web's lucide icons.
private func memorySymbol(_ kind: String) -> String {
    switch kind {
    case "quote": return "quote.bubble"
    case "artwork": return "paintpalette"
    case "interview": return "mic"
    case "event": return "trophy"
    case "photo": return "photo"
    default: return "star"
    }
}

/// Where a memory opens: its milestone, event or photo, from the store when the device holds it and from the server when it does not.
@MainActor
struct MemoryOpener {
    let context: ModelContext
    let navigator: AppNavigator

    func open(_ memory: MemoryDTO) {
        if memory.milestoneId > 0 {
            let id = String(memory.milestoneId)
            var descriptor = FetchDescriptor<Milestone>(predicate: #Predicate { $0.remoteId == id })
            descriptor.fetchLimit = 1
            if let local = try? context.fetch(descriptor).first {
                navigator.push(.milestone(local.id))
            } else if memory.interviewId > 0 {
                navigator.push(.interview(id: memory.interviewId))
            }
        } else if memory.eventId > 0 {
            navigator.push(.event(id: memory.eventId, name: memory.text))
        } else if memory.photoId > 0 {
            let id = String(memory.photoId)
            var descriptor = FetchDescriptor<Photo>(predicate: #Predicate { $0.remoteId == id })
            descriptor.fetchLimit = 1
            if let local = try? context.fetch(descriptor).first {
                navigator.push(PhotoRoute(id: local.id))
            } else {
                navigator.push(.remotePhoto(id: memory.photoId))
            }
        }
    }
}

/// The text of a memory, a quote in quotation marks and italics as the web's `<q>` sets it.
private struct MemoryText: View {
    let memory: MemoryDTO

    var body: some View {
        if memory.kind == "quote" {
            Text("“\(memory.text)”").italic()
        } else {
            Text(memory.text)
        }
    }
}

/// Home's featured memory: a photo when it has one, what kind it is and whose, the record, when, and Open / Another memory — `FeaturedMemory` on the web.
struct FeaturedMemoryView: View {
    let memory: MemoryDTO
    let people: [Int: (name: String, birthday: Date?)]
    let onOpen: () -> Void
    let onAnother: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let photoId = memory.photoIds.first {
                Button(action: onOpen) {
                    Color(.secondarySystemBackground)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .overlay { RemotePhotoView(remoteId: photoId, size: .medium) }
                        .clipped()
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                eyebrow
                if memory.kind == "interview", !memory.context.isEmpty {
                    Text(Interviews.shortQuestion(memory.context))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if !memory.text.isEmpty {
                    Button(action: onOpen) {
                        MemoryText(memory: memory)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                if memory.kind != "interview", !memory.context.isEmpty {
                    Text(memory.context)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Text(Memories.when(memory, people: people))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(Copy.memory.open, action: onOpen)
                        .buttonStyle(.bordered)
                    if let onAnother {
                        Button(action: onAnother) {
                            Label(Copy.memory.another, systemImage: "shuffle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .font(.subheadline)
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator)))
    }

    private var eyebrow: some View {
        let names = Memories.names(memory, people: people)
        let kind = Copy.memory.kinds[memory.kind] ?? ""
        return Label(names.isEmpty ? kind : "\(kind) · \(names)", systemImage: memorySymbol(memory.kind))
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// A memory as one compact row: thumbnail or symbol, the record, whose and when — `MemoryTile` on the web.
struct MemoryTileView: View {
    let memory: MemoryDTO
    let people: [Int: (name: String, birthday: Date?)]
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Group {
                    if let photoId = memory.photoIds.first {
                        RemotePhotoView(remoteId: photoId, size: .thumb)
                    } else {
                        Image(systemName: memorySymbol(memory.kind))
                            .font(.title3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.accentColor.opacity(0.12))
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if memory.text.isEmpty {
                            Text(Copy.memory.kinds[memory.kind] ?? "")
                        } else {
                            MemoryText(memory: memory)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    let names = Memories.names(memory, people: people)
                    Text(names.isEmpty ? Memories.when(memory, people: people) : "\(names) · \(Memories.when(memory, people: people))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
