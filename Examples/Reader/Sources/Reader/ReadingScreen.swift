//
//  ReadingScreen.swift
//  Reader
//
//  A chapter on a page, the bar above it titled with the chapter and the
//  controls below it. A tap on the page hides the bar and the controls and
//  gives the page the whole window; another tap brings them back. The
//  chapter on screen is the one the route named until the reader turns to
//  another — that is this screen's own state; where the book was left is
//  the library's.
//
//  The screen keeps the library up to date as the reader goes: an
//  `.onChange(of: chapter, initial: true)` records the place on opening and
//  on every turn, and a `.task(id: chapter)` counts the seconds the chapter
//  is open — restarted for each new chapter, so the seconds go to the one on
//  screen, and cancelled when the screen is popped. A change of text size
//  shows the size over the page until the buttons have been left alone for
//  a moment: `.onChange` brings it up, and a `.task(id:)` on the size, which
//  starts over with every press, takes it down.
//

import NucleantUI

@View
struct ReadingScreen {
    let library: Library
    let book: Book
    /// The chapter the screen was pushed to open.
    let opened: Int
    /// The chapter turned to with the controls, once there is one.
    @State private var turnedTo: Int? = nil
    /// The page alone: no bar above it, no controls below.
    @State private var isImmersive = false
    /// The text size over the page, just after it changed.
    @State private var isShowingTextSize = false
    @Environment(\.navigationRouter) private var router

    var chapter: Int { turnedTo ?? opened }

    var body: some View {
        VStack(spacing: 0) {
            // One element, keyed by the chapter: turning to another chapter
            // is a new scroll view, starting at its top.
            ForEach([chapter], id: \.self) { index in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ChapterPage(book: book, index: index, textSize: library.textSize)
                            .onTapGesture { isImmersive.toggle() }
                        endOfChapter(index)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if isShowingTextSize {
                    Text("\(Int(library.textSize)) pt")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(horizontal: 14, vertical: 6)
                        .background(ShapeStyle.secondaryBackground)
                        .cornerRadius(13)
                        .padding(.top, 12)
                        .transition(.opacity)
                }
            }

            if isImmersive {
                Text("\(book.title) · \(chapter + 1) of \(book.chapters.count)")
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .padding(horizontal: 16, vertical: 10)
            } else {
                controls
            }
        }
        .background(Theme.page)
        .navigationTitle(book.name(ofChapter: chapter))
        .toolbarVisibility(isImmersive ? .hidden : .visible, for: .navigationBar)
        .onChange(of: chapter, initial: true) {
            library.read(book, at: chapter)
        }
        .task(id: chapter) { [chapter] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                library.recordSecond(of: book, chapter: chapter)
            }
        }
        .onChange(of: library.textSize) {
            withAnimation(.easeOut) { isShowingTextSize = true }
        }
        .task(id: library.textSize) {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut) { isShowingTextSize = false }
        }
    }

    /// Under the page: the previous and next chapter, the text size.
    var controls: some View {
        HStack(spacing: 8) {
            Button("‹ Previous") { turn(to: chapter - 1) }
                .tint(Theme.accent)
                .disabled(chapter == 0)

            VStack(spacing: 1) {
                Text("Chapter \(chapter + 1) of \(book.chapters.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ReadingClock(library: library, book: book, chapter: chapter)
                    Text("· tap the page to hide")
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.faint)
            }
            .frame(maxWidth: .infinity)

            Button("A−") { library.shrinkText() }
                .tint(Theme.control)
                .disabled(!library.canShrinkText)
            Button("A+") { library.enlargeText() }
                .tint(Theme.control)
                .disabled(!library.canEnlargeText)

            Button("Next ›") { turn(to: chapter + 1) }
                .tint(Theme.accent)
                .disabled(chapter == book.chapters.count - 1)
        }
        .padding(horizontal: 12, vertical: 0)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        .background(ShapeStyle.secondaryBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(.separator).frame(height: 1)
        }
    }

    func endOfChapter(_ index: Int) -> some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(Theme.faint)
                .frame(width: 40, height: 1)
            if index + 1 < book.chapters.count {
                Text("Next")
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
                Button("\(book.name(ofChapter: index + 1)) ›") { turn(to: index + 1) }
                    .tint(Theme.accent)
            } else {
                Text("End of the sample")
                    .font(.system(size: 15, design: .serif).italic())
                    .foregroundStyle(Theme.faint)
                Button("Mark as Finished") { finish() }
                    .tint(Theme.accent)
            }
        }
        .padding(.bottom, 56)
        .frame(maxWidth: .infinity)
    }

    func turn(to index: Int) {
        turnedTo = index
    }

    /// Done with the book: back to the library, where it shows as finished.
    func finish() {
        library.finish(book)
        router?.popToRoot()
    }
}

/// How long the chapter has been open. Its own view, so the second the
/// screen's task records each time rebuilds this text and nothing else.
@View
struct ReadingClock {
    let library: Library
    let book: Book
    let chapter: Int

    var body: some View {
        Text("\(clockTime(library.secondsRead(book, chapter: chapter))) in this chapter")
    }
}

/// The text of one chapter, in a column that stops widening at a
/// comfortable measure.
@View
struct ChapterPage {
    let book: Book
    let index: Int
    let textSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: textSize * 0.8) {
            Text("CHAPTER \(index + 1)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.faint)
            if let title = book.chapters[index].title {
                Text(title)
                    .font(.system(size: textSize * 1.5, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
            }
            ForEach(0..<book.chapters[index].paragraphs.count) { paragraph in
                Text(book.chapters[index].paragraphs[paragraph])
                    .font(.system(size: textSize, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(horizontal: 36, vertical: 36)
        .frame(maxWidth: .infinity)
        // The gaps between paragraphs are page too.
        .contentShape(Rectangle())
    }
}
