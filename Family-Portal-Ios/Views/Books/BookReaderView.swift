import SwiftUI

/// One book, read: a cover, the contents, then each chapter's designed blocks, set on the book's own paper. The web's `/book/<id>` reader (`frontend/pages/books/book.tsx`).
/// Reading only, with no editing chrome on the page — the reading surface is the keepsake. The book is assembled on the device from `GetBook`'s references and sources by `BookAssembler`, exactly as the web assembles it.
struct BookReaderView: View {
    let bookId: Int
    let title: String

    @Environment(BookService.self) private var service
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var state = ActivityScreenState<GetBookResponseDTO>()
    @State private var assembled: AssembledBook?
    @State private var editing: GetBookResponseDTO?
    @State private var wasDeleted = false

    private static let gutter: CGFloat = 24

    var body: some View {
        Group {
            if let assembled {
                reader(assembled)
            } else if let error = state.error {
                ActivityUnavailableView(message: error) { await state.load(service.book(id: bookId)) }
            } else {
                ProgressView()
                    .tint(BookPalette.inkSoft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BookPalette.paper.ignoresSafeArea())
        .navigationTitle(assembled?.title ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BookPalette.paper, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if state.isShowingCached, !state.isLoading, state.value != nil {
                ActivityStaleNote(fetchedAt: state.fetchedAt)
            }
        }
        .toolbar {
            // Only over a fresh copy: a save carries the revision it opened, and a cached one may be behind.
            if let response = state.value, response.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = response }
                        .disabled(state.isShowingCached || state.isLoading)
                }
            }
        }
        .sheet(item: $editing, onDismiss: {
            // A deleted book has nothing left to read.
            if wasDeleted { dismiss() }
        }) { response in
            BookEditorView(
                response: response,
                onSaved: { await state.reload() },
                onDeleted: { wasDeleted = true }
            )
        }
        .task { await state.load(service.book(id: bookId)) }
        // Assembled once per payload rather than in `body`: it formats every date in the book.
        .onChange(of: state.fetchedAt, initial: true) {
            assembled = state.value.map { BookAssembler(book: $0.book, sources: $0.sources).assemble() }
        }
    }

    private func reader(_ book: AssembledBook) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    BookCoverView(book: book)

                    BookContentsView(chapters: book.chapters.filter { !$0.title.isEmpty }) { chapter in
                        jump(to: chapter, with: proxy)
                    }
                    .padding(.bottom, 8)

                    ForEach(book.chapters) { chapter in
                        BookChapterView(chapter: chapter, axis: book.growthAxis, gutter: Self.gutter)
                            .id(chapter.id)
                    }

                    BookEndView(ending: book.ending)
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, Self.gutter)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 64)
            }
            .refreshable { await state.reload() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(book.chapters.filter { !$0.title.isEmpty }) { chapter in
                            Button {
                                jump(to: chapter, with: proxy)
                            } label: {
                                if chapter.dates.isEmpty {
                                    Text(chapter.title)
                                } else {
                                    Text(chapter.title)
                                    Text(chapter.dates)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Chapters")
                }
            }
        }
    }

    private func jump(to chapter: BookChapter, with proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(chapter.id, anchor: .top)
        } else {
            withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(chapter.id, anchor: .top) }
        }
    }
}

// MARK: - Cover, contents, chapters

private struct BookCoverView: View {
    let book: AssembledBook

    var body: some View {
        VStack(spacing: 28) {
            if let cover = book.cover {
                BookImage(photo: cover, size: .large, maxHeight: 480)
                    .frame(maxWidth: 560)
                    .shadow(color: Color(red: 0.16, green: 0.12, blue: 0.08).opacity(0.2), radius: 25, y: 18)
                    .frame(maxWidth: .infinity)
            } else {
                Text("❦")
                    .font(.system(size: 44))
                    .foregroundStyle(BookPalette.inkSoft)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 10) {
                Text(book.title)
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(BookPalette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(book.dates)
                    .font(BookType.serif(.body).italic())
                    .foregroundStyle(BookPalette.inkSoft)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 48)
    }
}

private struct BookContentsView: View {
    let chapters: [BookChapter]
    let onSelect: (BookChapter) -> Void

    var body: some View {
        if !chapters.isEmpty {
            VStack(spacing: 12) {
                Text("Contents")
                    .font(BookType.label)
                    .textCase(.uppercase)
                    .tracking(2.5)
                    .foregroundStyle(BookPalette.inkSoft)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                        Button {
                            onSelect(chapter)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(chapter.title)
                                    .font(BookType.serif(.body))
                                    .foregroundStyle(BookPalette.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if !chapter.dates.isEmpty {
                                    Text(chapter.dates)
                                        .font(BookType.serif(.footnote))
                                        .foregroundStyle(BookPalette.inkSoft)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < chapters.count - 1 {
                            Line()
                                .stroke(BookPalette.rule, style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                                .frame(height: 1)
                        }
                    }
                }
            }
            .padding(.vertical, 28)
            .overlay(alignment: .top) { Rectangle().fill(BookPalette.rule).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(BookPalette.rule).frame(height: 1) }
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

private struct BookChapterView: View {
    let chapter: BookChapter
    let axis: GrowthAxis
    let gutter: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            if !chapter.title.isEmpty {
                VStack(spacing: 6) {
                    if !chapter.dates.isEmpty {
                        Text(chapter.dates)
                            .font(BookType.label)
                            .textCase(.uppercase)
                            .tracking(2)
                            .foregroundStyle(BookPalette.inkSoft)
                    }
                    Text(chapter.title)
                        .font(.system(size: 32, weight: .regular, design: .serif))
                        .foregroundStyle(BookPalette.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, -8)
            }
            ForEach(Array(chapter.blocks.enumerated()), id: \.offset) { index, block in
                BookBlockView(block: block, index: index, axis: axis, gutter: gutter)
            }
        }
        .padding(.top, 56)
    }
}

private struct BookEndView: View {
    let ending: String

    var body: some View {
        VStack(spacing: 6) {
            Text("❦")
                .font(.system(size: 26))
                .accessibilityHidden(true)
            Text(ending)
                .font(BookType.serif(.body).italic())
        }
        .foregroundStyle(BookPalette.inkSoft)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }
}
