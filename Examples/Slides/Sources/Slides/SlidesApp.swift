//
//  SlidesApp.swift
//  Slides
//
//  A presentation app: a deck of slides edited on the left and right of a
//  stage, and played full-window. It is transitions doing a job:
//
//  * Every slide comes on with an entrance and goes off with an exit, and
//    brings in its points one by one with a build — each picked in the
//    inspector from the framework's transitions (`.opacity`, `.push(from:)`,
//    `.move(edge:)`, `.slide`, `.scale`, combinations of them) and the app's
//    own (Effects.swift): `Transition`s whose bodies are modifiers in a
//    phase — a fade and a turn, a flip, a drop, a hinge, a curtain that is
//    a view laid over the slide, and ink through
//    `AnyTransition.modifier(active:identity:)` with an `Animatable`
//    modifier.
//  * Each slide's choice is kept as an `AnyTransition`, the type eraser:
//    every slide's can be a different type, and the stage holds whichever.
//    Entrance and exit are one `.asymmetric` transition.
//  * The slide's duration and curve are attached to its transition with
//    `animation(_:)`, so picking a slide, or advancing the show, needs no
//    `withAnimation` — the transition brings its own timing.
//  * The stage is a `ForEach` over the one slide on it: a different slide
//    is a removal and an insertion. "Show Again" re-keys it, to watch a
//    slide's entrance and exit again.
//  * The slides in the strip arrive and leave with `.move(edge:)` combined
//    with `.opacity` as they are added and deleted; the inspector's fields
//    for a layout come and go with a fade; and the editor and the show
//    swap through an `if` with a transition of their own.
//
//  The model is one `@Observable` class, `Deck`, owned by the root view and
//  changed through its methods.
//

import NucleantUI
import Observation

struct Theme {
    static let accent = Color(hex: 0x4C6FFF)
    static let sidebar = ShapeStyle.secondaryBackground
    static let canvas = ShapeStyle.dynamic(light: Color(hex: 0xE4E6EC), dark: Color(hex: 0x101217))
}

@View
struct SlidesView {
    @State private var deck = Deck.sample()
    @Environment(\.colorScheme) private var system

    var body: some View {
        let deck = self.deck
        ZStack {
            if deck.isPresenting {
                Presenter(deck: deck)
                    .transition(.opacity.combined(with: .scale(1.06)))
            } else {
                Editor(deck: deck)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShapeStyle.background)
        .tint(Theme.accent)
        .colorScheme(AppearanceModel.shared.appearance.scheme ?? system)
    }
}

@main
struct SlidesApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Slides") {
            SlidesView()
        }
        .defaultSize(width: 1360, height: 820)
        .commands { AppearanceCommands() }
    }
}

// MARK: - The deck it opens with

extension Deck {
    static func sample() -> Deck {
        var id = 0
        func next() -> Int {
            id += 1
            return id
        }
        func points(_ texts: [String]) -> [Bullet] {
            texts.map { Bullet(id: next(), text: $0) }
        }
        let slides = [
            Slide(
                id: next(), layout: .title,
                title: "Comings and Goings", subtitle: "Every way a slide can arrive and leave",
                bullets: [], theme: 0,
                entrance: .dissolve, exit: .zoom, build: .rise,
                duration: 0.8, curve: .smooth
            ),
            Slide(
                id: next(), layout: .bullets,
                title: "Built in", subtitle: "",
                bullets: points(["Dissolve, push, move and slide", "Scale, and zoom: a scale with a fade", "Rise: an offset with a fade"]),
                theme: 2,
                entrance: .pushFromRight, exit: .pushFromRight, build: .rise,
                duration: 0.7, curve: .snappy
            ),
            Slide(
                id: next(), layout: .bullets,
                title: "Your own", subtitle: "",
                bullets: points(["A body: the content and a phase", "willAppear, identity, didDisappear", "Any modifier animates, even yours"]),
                theme: 5,
                entrance: .flip, exit: .flip, build: .drop,
                duration: 0.8, curve: .smooth
            ),
            Slide(
                id: next(), layout: .quote,
                title: "A transition should generally be made by applying one or more modifiers to the content.",
                subtitle: "Transition, documented",
                bullets: [], theme: 1,
                entrance: .curtain, exit: .curtain, build: .rise,
                duration: 1.0, curve: .easeInOut
            ),
            Slide(
                id: next(), layout: .statement,
                title: "AnyTransition", subtitle: "",
                bullets: [], theme: 4,
                entrance: .spin, exit: .spin, build: .rise,
                duration: 0.9, curve: .bouncy
            ),
            Slide(
                id: next(), layout: .bullets,
                title: "Timing travels with it", subtitle: "",
                bullets: points(["A duration and a curve per slide", "Attached with .animation(_:)", "No withAnimation to turn a slide"]),
                theme: 3,
                entrance: .ink, exit: .ink, build: .swing,
                duration: 1.1, curve: .smooth
            ),
            Slide(
                id: next(), layout: .title,
                title: "Thank you", subtitle: "Press esc to go back to the deck",
                bullets: [], theme: 0,
                entrance: .swing, exit: .dissolve, build: .rise,
                duration: 0.9, curve: .bouncy
            ),
        ]
        return Deck(name: "Comings and Goings", slides: slides)
    }
}
