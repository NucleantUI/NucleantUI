//
//  NavigationStackTransition.swift
//  NucleantUI
//
//  A `NavigationStack` playing a push or a pop. The stack keeps every
//  screen in the tree and parks the covered ones (Navigation.swift); for
//  the length of a move it keeps both the screen underneath and the one
//  going on top of it — or coming off it — on screen, and a node over each
//  screen draws its part of the move:
//
//  * `.automatic`: the upper screen slides in from the trailing edge; the
//    lower one drifts a third as far the other way and dims a little.
//  * `.zoom`: the upper screen grows out of its source's frame on the
//    lower one, corners rounding off from the source's to the screen's,
//    over a fill of the source's background; the lower one recedes —
//    35 points across, never below 80% — and dims, and the source itself is
//    drawn as nothing meanwhile. With no source on screen it plays as
//    `.automatic`.
//  * `.shader`: the upper screen is drawn through the shader, its
//    `progress` how far in it is; the lower one stays as it is.
//
//  How far the upper screen is in is one animated number, 0 to 1: up on a
//  push, down on a pop. The springs are a zoom's usual ones — 0.34 s,
//  settling without a bounce going in and with a slight one coming out.
//  When it has run its course the stack is rebuilt once, to park the screen
//  underneath again or let the popped one go.
//

import Foundation

/// The push or pop a stack is playing, if any. Held in the stack's
/// `@State`; not observed — the screens' nodes read it as they are drawn.
@MainActor
final class NavigationStackTransition {

    /// A push or a pop.
    struct Move {
        /// The screen underneath.
        let lower: NavigationScreenID
        /// The screen going on top of it, or coming off it.
        let upper: NavigationScreenID
        let isPush: Bool
        /// A popped screen, kept on until its pop has played.
        let leaving: NavigationScreen?
        /// What a popped screen asked for, read before it is forgotten. A
        /// pushed screen says only as it is built — after the stack — so
        /// its transition is read when the move is first drawn.
        let poppedTransition: _NavigationTransitionContent?
    }

    /// What a move turned out to be when it began.
    enum Style {
        case automatic
        /// The source as it was found, for its corners and background.
        case zoom(MatchedTransitionSourceKey, _MatchedTransitionSourceStyle)
        /// The shader the upper screen is drawn through, and its arguments
        /// after `progress`.
        case shader(ShaderFunction, [ShaderArgument])
    }

    private(set) var move: Move?
    private var style: Style = .automatic
    /// How far the upper screen is in. `nil` until the move is first drawn.
    private var progress: AnimatedVector?
    private var lastTop: NavigationScreenID?
    private var lastScreens: [NavigationScreen] = []

    /// Rebuilds the stack once a move is over. Set by the stack each time it
    /// is built.
    var settle: () -> Void = {}

    /// A popped screen still on its way off.
    var leaving: NavigationScreen? { move?.leaving }

    /// Whether `screen` is part of the move under way — drawn, though not on
    /// top.
    func involves(_ screen: NavigationScreenID) -> Bool {
        guard let move else { return false }
        return move.lower == screen || move.upper == screen
    }

    /// Called by the stack as it is built, with the screens above the root:
    /// a new top is a push or a pop to play.
    func update(screens: [NavigationScreen], storage: NavigationStackStorage) {
        let top = screens.last?.id ?? .root
        defer {
            lastTop = top
            lastScreens = screens
        }
        guard let previous = lastTop, previous != top else { return }

        func depth(of id: NavigationScreenID, in list: [NavigationScreen]) -> Int? {
            id == .root ? 0 : list.firstIndex { $0.id == id }.map { $0 + 1 }
        }
        // A move already playing is cut short: the new one starts from
        // where the stack now stands.
        end(storage: storage)
        guard let oldDepth = depth(of: previous, in: lastScreens) else { return }
        if let stillThere = depth(of: previous, in: screens), stillThere < (depth(of: top, in: screens) ?? 0) {
            // The old top is underneath the new one: a push.
            move = Move(lower: previous, upper: top, isPush: true, leaving: nil, poppedTransition: nil)
        } else if (depth(of: top, in: screens) ?? 0) < oldDepth {
            // A pop — one screen or several at once.
            move = Move(
                lower: top,
                upper: previous,
                isPush: false,
                leaving: screens.contains { $0.id == previous } ? nil : lastScreens.first { $0.id == previous },
                poppedTransition: storage.transition(for: previous)
            )
        }
    }

    typealias Sample = (move: Move, style: Style, progress: Double)

    /// The frame `sampled` was worked out for: every screen drawn in one
    /// pass sees the same move at the same point — the last frame of it
    /// included, though the move ends as that frame is worked out.
    private var sampledFrame = -1
    private var sampled: Sample?

    /// How far the upper screen is in for the pass under way, starting the
    /// move the first time it is drawn — and ending it once it has arrived,
    /// that last frame still drawn as the move has it. `nil` with no move
    /// playing.
    func sample(store: AnimationStore, storage: NavigationStackStorage) -> Sample? {
        if store.frame == sampledFrame { return sampled }
        sampledFrame = store.frame
        sampled = nil
        guard let move else { return nil }
        if progress == nil {
            begin(move, store: store, storage: storage)
        }
        guard let progress else { return nil }
        let value = progress.current()[0]
        sampled = (move, style, value)
        if !progress.isMoving {
            finish(storage: storage)
        }
        return sampled
    }

    private func begin(_ move: Move, store: AnimationStore, storage: NavigationStackStorage) {
        let asked = move.isPush ? storage.transition(for: move.upper) : move.poppedTransition
        style = .automatic
        var animation = Animation.smooth(duration: 0.4)
        if case .zoom(let namespace, let id)? = asked?.kind {
            let key = MatchedTransitionSourceKey(namespace: namespace, id: id)
            if let source = storage.source(key) {
                style = .zoom(key, source.style)
                storage.hiddenSource = key
                // In without a bounce; out with a slight one.
                animation = .spring(Spring(response: 0.34, dampingRatio: move.isPush ? 1 : 0.92))
            }
        }
        if case .shader(let function, let arguments, let timing)? = asked?.kind {
            style = .shader(function, arguments)
            animation = timing.animation
        }
        let vector = AnimatedVector([move.isPush ? 0 : 1])
        progress = vector
        // Not under a transaction that asks for no animation: then the move
        // is over at once.
        let animates = store.isCommitPass && !store.transaction.disablesAnimations
        vector.update(to: [move.isPush ? 1 : 0], animation: animates ? animation : nil, in: store)
    }

    /// The move has played: forget it and rebuild the stack, which parks
    /// the screen underneath again or lets the popped one go.
    private func finish(storage: NavigationStackStorage) {
        end(storage: storage)
        settle()
    }

    private func end(storage: NavigationStackStorage) {
        if case .zoom(let key, _) = style, storage.hiddenSource == key {
            storage.hiddenSource = nil
        }
        move = nil
        progress = nil
        style = .automatic
    }
}

// MARK: - Drawing a screen's part

/// The node over each of a stack's screens: draws it as the move under way
/// has it — or as it is, with no move or no part in it.
struct NavigationScreenTransitionContent: NodeContent {
    /// The node's path: where a shader move keeps its module.
    let path: [Int]
    let screen: NavigationScreenID
    let transition: NavigationStackTransition
    let storage: NavigationStackStorage
    /// The window background a zoom's card is filled with when its style
    /// names no color, resolved where the stack was built.
    let windowBackground: _ResolvedPaint

    /// How far the lower screen recedes under a zoom: 35 points across, but
    /// never below 80%.
    static func recededScale(width: Double) -> Double {
        guard width > 0 else { return 1 }
        return max((width - 34 - 2.0 / 3) / width, 0.8)
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let store = AnimationStore.current,
              let sample = transition.sample(store: store, storage: storage),
              screen == sample.move.lower || screen == sample.move.upper
        else {
            node.singleChild?.place(in: rect, proposal: proposal, context: context, into: &list)
            return
        }
        let p = sample.progress
        let isUpper = screen == sample.move.upper

        switch sample.style {
        case .automatic:
            var inner = context
            let dx = isUpper ? (1 - p) * rect.width : -0.3 * p * rect.width
            inner.transform = context.transform.concatenating(.translation(x: dx, y: 0))
            node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
            if !isUpper {
                dim(rect, opacity: 0.1 * p, context: inner, into: &list)
            }

        case .zoom(let key, let style):
            if isUpper {
                placeZoomed(node: node, in: rect, proposal: proposal, context: context, key: key, style: style, p: p, into: &list)
            } else {
                var inner = context
                let scale = 1 - (1 - Self.recededScale(width: rect.width)) * p
                inner.transform = context.transform.concatenating(
                    .around(Point(x: rect.midX, y: rect.midY), .scale(x: scale, y: scale))
                )
                node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
                dim(rect, opacity: 0.15 * p, context: inner, into: &list)
            }

        case .shader(let function, let arguments):
            guard isUpper else {
                node.singleChild?.place(in: rect, proposal: proposal, context: context, into: &list)
                return
            }
            let reading = function.reading(
                [.float("progress", Float(p))] + arguments,
                textures: [],
                content: true
            )
            ShaderEffectContent(
                path: path,
                module: (reading.spirv, reading.input, reading.isAnimated),
                draw: ShaderDraw(vertices: 6, instances: 1),
                textures: ShaderTextures(),
                backdrop: false
            ).place(node: node, in: rect, proposal: proposal, context: context, into: &list)
        }
    }

    /// The upper screen grown `p` of the way from its source's frame to its
    /// own: drawn at its own size, scaled to fill the frame in between and
    /// clipped to it, over the source's background.
    private func placeZoomed(
        node: ViewNode,
        in rect: Rect,
        proposal: ProposedSize,
        context: DrawContext,
        key: MatchedTransitionSourceKey,
        style: _MatchedTransitionSourceStyle,
        p: Double,
        into list: inout DisplayList
    ) {
        // Where the source stands now, in this screen's space — it may have
        // moved, the screen under it receding.
        guard let source = storage.source(key),
              let toLocal = context.transform.inverted()
        else {
            node.singleChild?.place(in: rect, proposal: proposal, context: context, into: &list)
            return
        }
        let from = source.frame.applying(toLocal)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * p }
        let frame = Rect(
            x: mix(from.minX, rect.minX),
            y: mix(from.minY, rect.minY),
            width: max(0, mix(from.width, rect.width)),
            height: max(0, mix(from.height, rect.height))
        )
        let radius = max(0, mix(style.cornerRadius, 0))
        let clipped = context.clipped(to: frame, cornerRadius: radius)
        let background = style.background.map { _ResolvedPaint.color($0) } ?? windowBackground

        list.append(.shape(ShapeDraw(
            path: Path { $0.addRect(frame, cornerRadius: radius) },
            bounds: frame,
            fill: clipped.resolve(background)
        )), under: clipped.drawState)

        let scale = rect.width > 0 && rect.height > 0
            ? max(frame.width / rect.width, frame.height / rect.height)
            : 1
        var inner = clipped
        inner.transform = clipped.transform
            .concatenating(.translation(x: frame.midX, y: frame.midY))
            .concatenating(.scale(x: scale, y: scale))
            .concatenating(.translation(x: -rect.midX, y: -rect.midY))
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }

    /// Black over `rect` at `opacity`: the screen underneath darkening.
    private func dim(_ rect: Rect, opacity: Double, context: DrawContext, into list: inout DisplayList) {
        guard opacity > 0 else { return }
        var shade = context
        shade.opacity *= opacity
        list.append(.shape(ShapeDraw(
            path: Path { $0.addRect(rect) },
            bounds: rect,
            fill: shade.resolve(.color(.black))
        )), under: shade.drawState)
    }
}

extension View {
    /// This screen of a stack, drawn as `transition`'s move has it.
    func navigationScreenTransition(
        _ screen: NavigationScreenID,
        _ transition: NavigationStackTransition,
        storage: NavigationStackStorage
    ) -> some View {
        _ModifierView(content: self, modifier: NavigationScreenTransitionModifier(
            screen: screen,
            transition: transition,
            storage: storage
        ))
    }
}

/// `navigationScreenTransition(_:_:storage:)`: the same screen is the same
/// modifier — its move and its stack are read as it is placed.
struct NavigationScreenTransitionModifier: PrimitiveModifier {
    let screen: NavigationScreenID
    let transition: NavigationStackTransition
    let storage: NavigationStackStorage

    func makeContent(_ context: inout BuildContext) -> NavigationScreenTransitionContent {
        NavigationScreenTransitionContent(
            path: context.path,
            screen: screen,
            transition: transition,
            storage: storage,
            windowBackground: BackgroundStyle().paint(in: context.environment)
        )
    }

    func _isEquivalent(to other: NavigationScreenTransitionModifier) -> Bool {
        screen == other.screen
    }
}
