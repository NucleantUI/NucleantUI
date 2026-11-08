//
//  SlideView.swift
//  Slides
//
//  A slide as it is shown, at its design size (960 × 540) — the stage, the
//  presenter and the thumbnails scale it to fit — and the stage that shows
//  one at a time.
//
//  The stage is a `ForEach` over the one slide on it, keyed by that slide
//  and by which time it is shown: a different slide, or the same one shown
//  again, is a removal and an insertion, so the slide leaving goes off with
//  its exit and the one arriving comes on with its entrance. The points of
//  a slide are a `ForEach` over the ones revealed so far, so each point the
//  presenter reveals comes in with the slide's build, and each one taken
//  back goes out with it.
//

import NucleantUI

/// A palette a slide is drawn in.
struct SlideTheme {
    let name: String
    let background: Color
    let text: Color
    let accent: Color

    static let all: [SlideTheme] = [
        SlideTheme(name: "Midnight", background: Color(hex: 0x15171F), text: Color(hex: 0xF4F5F8), accent: Color(hex: 0x7C8CFF)),
        SlideTheme(name: "Paper", background: Color(hex: 0xF6F1E7), text: Color(hex: 0x2A2723), accent: Color(hex: 0xD9534F)),
        SlideTheme(name: "Ocean", background: Color(hex: 0x0F4C81), text: Color.white, accent: Color(hex: 0x7FDBFF)),
        SlideTheme(name: "Coral", background: Color(hex: 0xFF6F61), text: Color.white, accent: Color(hex: 0x2B2D42)),
        SlideTheme(name: "Forest", background: Color(hex: 0x1E4D3A), text: Color(hex: 0xEAF4EC), accent: Color(hex: 0xF4C95D)),
        SlideTheme(name: "Plum", background: Color(hex: 0x3D2352), text: Color(hex: 0xF7EEFB), accent: Color(hex: 0xFF9F1C)),
    ]

    static func of(_ slide: Slide) -> SlideTheme {
        all[slide.theme % all.count]
    }

    /// What `Curtain` and `Ink` cover a slide with.
    static let curtain = Color(hex: 0x0B0C10)
    static let ink = Color(hex: 0x4C6FFF)
}

/// One slide, `points` of its points out.
@View
struct SlideView {
    static let size = Size(width: 960, height: 540)

    let slide: Slide
    let points: Int

    var body: some View {
        let theme = SlideTheme.of(slide)
        ZStack {
            Rectangle().fill(theme.background)
            content(theme)
                .padding(64)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    @ViewBuilder
    private func content(_ theme: SlideTheme) -> some View {
        switch slide.layout {
        case .title:
            VStack(spacing: 22) {
                Rectangle().fill(theme.accent).frame(width: 96, height: 6)
                Text(slide.title)
                    .font(.system(size: 66, weight: .bold))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                Text(slide.subtitle)
                    .font(.system(size: 26))
                    .foregroundStyle(theme.text.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .bullets:
            VStack(alignment: .leading, spacing: 26) {
                Text(slide.title)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(theme.text)
                Rectangle().fill(theme.accent).frame(width: 64, height: 5)
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(slide.bullets.prefix(points))) { bullet in
                        HStack(alignment: .center, spacing: 18) {
                            Circle().fill(theme.accent).frame(width: 14, height: 14)
                            Text(bullet.text)
                                .font(.system(size: 32))
                                .foregroundStyle(theme.text)
                        }
                        .transition(slide.pointTransition)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        case .quote:
            VStack(alignment: .leading, spacing: 24) {
                Text("“")
                    .font(.system(size: 140, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .frame(height: 90, alignment: .top)
                Text(slide.title)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(theme.text)
                Text("— \(slide.subtitle)")
                    .font(.system(size: 26))
                    .foregroundStyle(theme.text.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        case .statement:
            Text(slide.title)
                .font(.system(size: 92, weight: .heavy))
                .foregroundStyle(theme.accent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The slide on stage, scaled to fit, keeping its shape.
@View
struct Stage {
    let deck: Deck

    var body: some View {
        let deck = self.deck
        GeometryReader { proxy in
            let scale = min(proxy.size.width / SlideView.size.width, proxy.size.height / SlideView.size.height)
            ZStack {
                ForEach(deck.staged) { staged in
                    SlideView(slide: staged.slide, points: deck.pointsOnStage)
                        .transition(staged.slide.transition)
                }
            }
            .frame(width: SlideView.size.width, height: SlideView.size.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: SlideView.size.width * scale, height: SlideView.size.height * scale, alignment: .topLeading)
            .clipped()
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// The slide on stage, with the key it is shown under.
struct StagedSlide: Identifiable {
    let id: StageKey
    let slide: Slide
}

extension Deck {
    /// The stage's one slide — none while the deck is empty.
    var staged: [StagedSlide] {
        guard let slide = onStage, let key = stageKey else { return [] }
        return [StagedSlide(id: key, slide: slide)]
    }
}

/// A slide drawn small, for the strip of slides.
@View
struct Thumbnail {
    let slide: Slide
    let width: Double

    var body: some View {
        let scale = width / SlideView.size.width
        SlideView(slide: slide, points: slide.steps)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: SlideView.size.height * scale, alignment: .topLeading)
            .clipped()
    }
}
