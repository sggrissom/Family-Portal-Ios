import SwiftUI

/// The family's books on a shelf, newest-edited first — the web's `/books`. Pushed from the account menu and from a person's page.
/// A viewer who may change books also gets "Start a book", one choice per preset.
struct BooksView: View {
    @Environment(BookService.self) private var service
    @Environment(AppNavigator.self) private var navigator

    @State private var state = ActivityScreenState<ListBooksResponseDTO>()
    @State private var starting: BookPlans.Preset?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18, alignment: .top)]

    var body: some View {
        ActivityScreen(state: state, read: { service.books() }) { response in
            VStack(alignment: .leading, spacing: 20) {
                Text("Turn your family's memories into a story.")
                    .font(BookType.serif(.body).italic())
                    .foregroundStyle(.secondary)

                if response.books.isEmpty {
                    ContentUnavailableView {
                        Label("No Books Yet", systemImage: "book.closed")
                    } description: {
                        Text(response.canEdit
                            ? "A first year, a year of one person, a family year, or any stretch of dates — drafted from what the family has already recorded."
                            : "Once a book is saved, it can be read here.")
                    }
                    .padding(.top, 8)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                        ForEach(response.books) { book in
                            NavigationLink(value: AppRoute.book(id: book.id, title: book.title)) {
                                BookShelfItem(book: book)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if response.canEdit {
                    Text("Start a book")
                        .font(BookType.serif(.title3).weight(.semibold))
                        .padding(.top, 12)
                    VStack(spacing: 10) {
                        ForEach(BookPlans.presets) { preset in
                            Button {
                                starting = preset
                            } label: {
                                PresetRow(preset: preset)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(Copy.account.books)
        .sheet(item: $starting) { preset in
            NewBookView(preset: preset) { book in
                Task { await state.reload() }
                navigator.push(.book(id: book.id, title: book.title))
            }
        }
    }
}

private struct PresetRow: View {
    let preset: BookPlans.Preset

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: preset.symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(preset.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(.separator), lineWidth: 0.5))
        .contentShape(Rectangle())
    }
}

/// A book standing on the shelf: its cover photo bound with a shaded spine, or a cloth cover with the title set on it when there is no photo.
private struct BookShelfItem: View {
    let book: BookSummaryDTO

    private var cover: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous)
    }

    private var subtitle: String {
        let dates = BookDay.bookDates(start: book.startDate, end: book.endDate)
        return book.personNames.count > 1 ? "\(BookAssembler.joinNames(book.personNames)) · \(dates)" : dates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    if book.coverPhotoId > 0 {
                        RemotePhotoView(remoteId: book.coverPhotoId, size: .medium)
                    } else {
                        cloth
                    }
                }
                .overlay(alignment: .leading) {
                    // The spine: a shadowed fold a few points in from the binding edge.
                    LinearGradient(
                        colors: [.black.opacity(0.22), .black.opacity(0.04), .white.opacity(0.10), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 12)
                }
                .clipShape(cover)
                .shadow(color: .black.opacity(0.16), radius: 9, x: 0, y: 6)

            Text(book.title)
                .font(BookType.serif(.subheadline).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var cloth: some View {
        ZStack {
            LinearGradient(
                colors: [BookPalette.rule, BookPalette.inkSoft.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Text(book.title)
                    .font(BookType.serif(.headline))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BookPalette.ink)
                Rectangle()
                    .fill(BookPalette.ink.opacity(0.4))
                    .frame(width: 28, height: 1)
            }
            .padding(18)
        }
    }
}
