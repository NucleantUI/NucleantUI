//
//  Deck.swift
//  Slides
//
//  The deck being edited and shown — the app's model, one `@Observable`
//  class changed only through its methods. A slide is a value inside it:
//  what it says, how it looks, and how it comes on, goes off and brings in
//  its points (`Effect`, Effects.swift), with the timing those run at.
//

import NucleantUI
import Observation

/// One point of a slide, revealed on its own when presenting.
struct Bullet: Identifiable, Equatable {
    let id: Int
    var text: String
}

/// How a slide is laid out.
enum SlideLayout: CaseIterable, Identifiable {
    case title, bullets, quote, statement

    var id: Self { self }

    var name: String {
        switch self {
        case .title: return "Title"
        case .bullets: return "Points"
        case .quote: return "Quote"
        case .statement: return "Big"
        }
    }
}

/// The curve an effect runs on.
enum Curve: CaseIterable, Identifiable {
    case smooth, snappy, bouncy, easeInOut, linear

    var id: Self { self }

    var name: String {
        switch self {
        case .smooth: return "Smooth"
        case .snappy: return "Snappy"
        case .bouncy: return "Bouncy"
        case .easeInOut: return "Ease"
        case .linear: return "Linear"
        }
    }

    func animation(duration: Double) -> Animation {
        switch self {
        case .smooth: return .smooth(duration: duration)
        case .snappy: return .snappy(duration: duration)
        case .bouncy: return .bouncy(duration: duration)
        case .easeInOut: return .easeInOut(duration: duration)
        case .linear: return .linear(duration: duration)
        }
    }
}

struct Slide: Identifiable, Equatable {
    let id: Int
    var layout: SlideLayout
    var title: String
    var subtitle: String
    var bullets: [Bullet]
    /// Which of `SlideTheme.all` it is drawn in.
    var theme: Int
    /// How it comes on, how it goes off, and how its points come and go.
    var entrance: Effect
    var exit: Effect
    var build: Effect
    /// Seconds an entrance or an exit takes; a point takes a little less.
    var duration: Double
    var curve: Curve

    /// How many points there are to reveal one by one.
    var steps: Int { layout == .bullets ? bullets.count : 0 }
}

/// What the stage shows: a slide, and which time it is shown — a replay
/// shows the same slide anew, so it comes on again.
struct StageKey: Hashable {
    let slide: Int
    let showing: Int
}

@MainActor
@Observable
final class Deck {
    var name: String
    private(set) var slides: [Slide]
    private(set) var selection: Int

    /// Presenting: the whole window is the show, and these say where it is.
    private(set) var isPresenting = false
    private(set) var position = 0
    private(set) var revealed = 0

    /// Bumped to show the slide on stage again.
    private(set) var showing = 0

    private var nextID: Int

    init(name: String, slides: [Slide]) {
        self.name = name
        self.slides = slides
        self.selection = slides.first?.id ?? 0
        self.nextID = (slides.map(\.id).max() ?? 0) + 1
    }

    // MARK: Reading

    var selectedIndex: Int? { slides.firstIndex { $0.id == selection } }

    var selected: Slide? { selectedIndex.map { slides[$0] } }

    /// The slide on stage: where the show is while presenting, the selected
    /// one while editing.
    var onStage: Slide? {
        if isPresenting { return slides.indices.contains(position) ? slides[position] : nil }
        return selected
    }

    /// How many of the slide on stage's points are showing — all of them
    /// while editing.
    var pointsOnStage: Int {
        guard let slide = onStage else { return 0 }
        return isPresenting ? revealed : slide.steps
    }

    var stageKey: StageKey? {
        onStage.map { StageKey(slide: $0.id, showing: showing) }
    }

    func number(of id: Int) -> Int {
        (slides.firstIndex { $0.id == id } ?? 0) + 1
    }

    // MARK: Editing

    func select(_ id: Int) {
        guard slides.contains(where: { $0.id == id }) else { return }
        selection = id
    }

    /// Change the slide `id` — what the inspector's fields write through.
    func edit(_ id: Int, _ change: (inout Slide) -> Void) {
        guard let index = slides.firstIndex(where: { $0.id == id }) else { return }
        change(&slides[index])
    }

    /// A new slide after the selected one, like it, and selected.
    func addSlide() {
        let template = selected ?? slides.last
        let slide = Slide(
            id: takeID(),
            layout: .bullets,
            title: "New Slide",
            subtitle: "",
            bullets: [Bullet(id: takeID(), text: "A first point")],
            theme: template?.theme ?? 0,
            entrance: template?.entrance ?? .dissolve,
            exit: template?.exit ?? .dissolve,
            build: template?.build ?? .rise,
            duration: template?.duration ?? 0.6,
            curve: template?.curve ?? .smooth
        )
        insert(slide)
    }

    func duplicateSelection() {
        guard var copy = selected else { return }
        copy = Slide(
            id: takeID(),
            layout: copy.layout,
            title: copy.title,
            subtitle: copy.subtitle,
            bullets: copy.bullets.map { Bullet(id: takeID(), text: $0.text) },
            theme: copy.theme,
            entrance: copy.entrance,
            exit: copy.exit,
            build: copy.build,
            duration: copy.duration,
            curve: copy.curve
        )
        insert(copy)
    }

    func deleteSelection() {
        guard slides.count > 1, let index = selectedIndex else { return }
        slides.remove(at: index)
        selection = slides[min(index, slides.count - 1)].id
    }

    /// Move the selected slide `offset` places along the deck.
    func moveSelection(by offset: Int) {
        guard let index = selectedIndex else { return }
        let target = index + offset
        guard slides.indices.contains(target) else { return }
        slides.swapAt(index, target)
    }

    func addPoint(to id: Int) {
        let bullet = Bullet(id: takeID(), text: "Another point")
        edit(id) { $0.bullets.append(bullet) }
    }

    func removePoint(_ bullet: Int, from id: Int) {
        edit(id) { $0.bullets.removeAll { $0.id == bullet } }
    }

    /// Show the slide on stage again: off with its exit, on with its
    /// entrance.
    func replay() {
        showing += 1
    }

    private func insert(_ slide: Slide) {
        let index = selectedIndex.map { $0 + 1 } ?? slides.count
        slides.insert(slide, at: index)
        selection = slide.id
    }

    private func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    // MARK: Presenting

    /// The show, from the selected slide or from the start, with no point
    /// of it revealed yet.
    func present(fromStart: Bool) {
        position = fromStart ? 0 : (selectedIndex ?? 0)
        revealed = 0
        isPresenting = true
    }

    /// Back to editing, at the slide the show was on.
    func stopPresenting() {
        if slides.indices.contains(position) {
            selection = slides[position].id
        }
        isPresenting = false
    }

    /// The next point, or the next slide once every point is out.
    func advance() {
        guard isPresenting, slides.indices.contains(position) else { return }
        if revealed < slides[position].steps {
            revealed += 1
        } else if position + 1 < slides.count {
            position += 1
            revealed = 0
        }
    }

    /// The last point back in, or the slide before — with all of its
    /// points out.
    func goBack() {
        guard isPresenting else { return }
        if revealed > 0 {
            revealed -= 1
        } else if position > 0 {
            position -= 1
            revealed = slides[position].steps
        }
    }

    var progress: Double {
        guard isPresenting, !slides.isEmpty else { return 0 }
        let steps = slides.map { $0.steps + 1 }
        let done = steps.prefix(position).reduce(0, +) + revealed + 1
        return Double(done) / Double(steps.reduce(0, +))
    }
}
