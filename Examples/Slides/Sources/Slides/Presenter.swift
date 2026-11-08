//
//  Presenter.swift
//  Slides
//
//  The show: the window is the stage. A click, → or the space bar brings
//  out the next point — with the slide's build — or, once every point is
//  out, the next slide, the one on stage going off with its exit and the
//  next coming on with its entrance; ← takes the last point back in, or
//  goes back a slide. Escape ends the show.
//
//  None of it is wrapped in `withAnimation`: each slide's transition, and
//  its points', bring their own animation (`Transition.animation(_:)`), so
//  the timing set on a slide is the timing the show runs at.
//

import NucleantUI

@View
struct Presenter {
    let deck: Deck
    @FocusState private var isFocused: Bool

    var body: some View {
        let deck = self.deck
        ZStack(alignment: .bottom) {
            Rectangle().fill(Color.black)
            Stage(deck: deck)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 52)
            PresenterBar(deck: deck)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { deck.advance() }
        .focusable()
        .focused($isFocused)
        .onKeyPress(keys: [.rightArrow, .downArrow, .space, .return]) { _ in
            deck.advance()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .upArrow, .delete]) { _ in
            deck.goBack()
            return .handled
        }
        .onKeyPress(.escape) {
            withAnimation(.smooth(duration: 0.5)) { deck.stopPresenting() }
            return .handled
        }
        .onAppear { isFocused = true }
    }
}

/// Where the show is: a progress line, the slide's number and the keys.
@View
struct PresenterBar {
    let deck: Deck

    var body: some View {
        let deck = self.deck
        VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(white: 1, opacity: 0.12))
                Rectangle()
                    .fill(Theme.accent)
                    .relativeSize(width: deck.progress)
            }
            .frame(height: 3)
            HStack(spacing: 14) {
                Text("\(deck.position + 1) of \(deck.slides.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Spacer()
                Text("Click or Space: next · Left Arrow: back · Esc: end")
                    .font(.system(size: 12))
                Button("End Show") {
                    withAnimation(.smooth(duration: 0.5)) { deck.stopPresenting() }
                }
                .font(.system(size: 12))
            }
            .foregroundStyle(Color(white: 1, opacity: 0.6))
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }
}
