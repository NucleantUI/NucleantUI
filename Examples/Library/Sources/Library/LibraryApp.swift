//
//  LibraryApp.swift
//  Library
//
//  An `@Observable` object handed down through the environment: the root
//  owns the `Library` in `@State` and puts it in the environment of the
//  first layer only, with `.environment(library)`. Every layer below reads
//  it with `@Environment(Library.self)` — none of them is passed it:
//
//  * Layer 1, `LibraryScreen`: the totals — books on loan, starred.
//  * Layer 2, `ShelfView`: the shelf's books, and "Return all".
//  * Layer 3, `BookRow`: a book, and its star.
//  * Layer 4, `LoanButton`: borrowing and returning it.
//
//  A change made four layers down — borrowing a book — shows in the totals
//  at the top, since every layer reads the same object.
//
//  Key-path values travel the same environment beside it: layer 1 reads
//  `@Environment(\.colorScheme)` next to the library and applies the View
//  menu's System / Light / Dark choice with `.colorScheme(_:)`, and every
//  layer's frame reads `\.colorScheme` again for its colors — below that
//  write, so it sees the choice.
//

import NucleantUI
import Observation

@main
struct LibraryApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Library") {
            LibraryRoot()
        }
        .defaultSize(width: 520, height: 760)
        .commands { AppearanceCommands() }
    }
}

// MARK: - Model

struct Book: Identifiable {
    let id: Int
    let title: String
    let author: String
    var isOnLoan = false
    var isStarred = false
}

@MainActor @Observable
final class Library {
    let name = "City Library"
    private(set) var books: [Book] = [
        Book(id: 1, title: "The Left Hand of Darkness", author: "Ursula K. Le Guin"),
        Book(id: 2, title: "Invisible Cities", author: "Italo Calvino"),
        Book(id: 3, title: "Beloved", author: "Toni Morrison"),
        Book(id: 4, title: "Solaris", author: "Stanisław Lem"),
        Book(id: 5, title: "The Remains of the Day", author: "Kazuo Ishiguro"),
    ]

    var onLoanCount: Int { books.count(where: { $0.isOnLoan }) }
    var starredCount: Int { books.count(where: { $0.isStarred }) }

    func toggleLoan(_ id: Book.ID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].isOnLoan.toggle()
    }

    func toggleStar(_ id: Book.ID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].isStarred.toggle()
    }

    func returnAll() {
        for index in books.indices { books[index].isOnLoan = false }
    }
}

// MARK: - Root

/// Owns the library, and hands it to the first layer — the only place it
/// is passed.
@View
struct LibraryRoot {
    @State private var library = Library()

    var body: some View {
        LibraryScreen()
            .environment(library)
    }
}

// MARK: - Layers

/// Layer 1: where the library is put in the environment. It reads the
/// window's color scheme beside it, and hands down the View menu's choice.
@View
struct LibraryScreen {
    @Environment(Library.self) private var library
    @Environment(\.colorScheme) private var system

    var body: some View {
        ScrollView {
            LayerBox(1, "LibraryScreen", note: "given .environment(library)") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(library.name).font(.title2)
                    Text("\(library.onLoanCount) of \(library.books.count) on loan · \(library.starredCount) starred")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ShelfView()
            }
            .padding(20)
        }
        .background(.background)
        .colorScheme(AppearanceModel.shared.appearance.scheme ?? system)
    }
}

/// Layer 2.
@View
struct ShelfView {
    @Environment(Library.self) private var library

    var body: some View {
        LayerBox(2, "ShelfView", note: "reads @Environment(Library.self)") {
            ForEach(library.books) { book in
                BookRow(book: book)
            }
            Button("Return all") { library.returnAll() }
                .disabled(library.onLoanCount == 0)
        }
    }
}

/// Layer 3: given its book, not the library.
@View
struct BookRow {
    let book: Book
    @Environment(Library.self) private var library

    var body: some View {
        LayerBox(3, "BookRow", note: "reads it too") {
            HStack(spacing: 10) {
                Button(book.isStarred ? "★" : "☆") { library.toggleStar(book.id) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).lineLimit(1)
                    Text(book.author).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LoanButton(book: book)
            }
        }
    }
}

/// Layer 4.
@View
struct LoanButton {
    let book: Book
    @Environment(Library.self) private var library

    var body: some View {
        LayerBox(4, "LoanButton") {
            Button(book.isOnLoan ? "Return" : "Borrow") { library.toggleLoan(book.id) }
        }
    }
}

// MARK: - Layer frame

/// A layer's frame: its number, its view, and how it gets the library.
@View
struct LayerBox<Content: View> {
    let layer: Int
    let name: String
    let note: String?
    let content: Content
    @Environment(\.colorScheme) private var scheme

    init(_ layer: Int, _ name: String, note: String? = nil, _viewID: ViewID = #viewID, @ViewBuilder content: () -> Content) {
        self.layer = layer
        self.name = name
        self.note = note
        self.content = content()
        self._viewID = _viewID
    }

    /// Bright on dark, deeper on light.
    private var tint: Color {
        let dark = scheme == .dark
        switch layer {
        case 1: return Color(hex: dark ? 0x4F7CFF : 0x2A55D4)
        case 2: return Color(hex: dark ? 0x2EB67D : 0x1E8A5C)
        case 3: return Color(hex: dark ? 0xF2994A : 0xC46A1A)
        default: return Color(hex: dark ? 0xBB6BD9 : 0x8E3FB0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.map { "Layer \(layer) · \(name) · \($0)" } ?? "Layer \(layer) · \(name)")
                .font(.caption)
                .foregroundStyle(tint)
                .lineLimit(1)
            content
        }
        .padding(layer == 4 ? 6 : 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint, lineWidth: 1)
        )
    }
}
