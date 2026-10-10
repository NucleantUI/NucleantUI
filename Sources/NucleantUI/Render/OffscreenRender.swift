//
//  OffscreenRender.swift
//  NucleantUI
//
//  One view tree driven with no window: built, laid out at a given size, and
//  placed into a display list. What `RenderTexture` and `renderImage` both
//  stand on.
//
//  This is the only place a tree runs outside `ViewHost`, and it is
//  deliberately a *snapshot* rather than a second live host. Two things in the
//  framework are process-global by design: `Invalidator.shared`, the dirty set
//  every state write lands in, keyed by structural path; and
//  `ShaderHost.current`, the registry of the pass being laid out. A second
//  live tree would take the window's dirty paths for its own and nest a pass
//  inside a pass. So an offscreen tree renders when it is asked to and at no
//  other time, and its paths are rooted at `rootIndex` — a slot no window tree
//  can produce — so that nothing it reads can dirty anything.
//
//  What it keeps across renders is the tree itself: the same store, the same
//  records, so a second render reuses the views that are equivalent and the
//  `@State` inside them keeps its value. What it does not do is re-run for
//  that state. See `RenderTexture` for what that means in practice.
//

@MainActor
final class OffscreenRender {

    /// The root slot every offscreen path starts at. `Int.min` because a
    /// window tree's paths are built from child indices (0, 1, 2 …) and can
    /// never reach it: `@State` keys cannot collide with a window's, and
    /// `Invalidator` drops a dirty path that starts here (see its
    /// `invalidate(owner:)`).
    static let rootIndex = Int.min

    /// Everything a build pass needs, kept for the life of the tree rather
    /// than per render — this is what makes a re-render a rebuild of the same
    /// tree instead of a fresh one.
    private let store = StateStore()
    private let effects = EffectQueue()
    private let animations = AnimationStore()
    private let records = RebuildRecords()

    /// What the tree inherits. The display scale belongs to whoever is
    /// rendering — a texture's own scale, not the window's.
    var environment: EnvironmentValues

    init(environment: EnvironmentValues = EnvironmentValues()) {
        self.environment = environment
    }

    /// Build `view`, lay it out at `size` points, and place it — the display
    /// list in the tree's own coordinates, its origin at (0, 0).
    ///
    /// Nested render nodes are flattened (`flattensRenderNodes`), so a
    /// `.drawingGroup()` inside draws into this list rather than claiming a
    /// node of its own; `ShaderHost.current` is cleared for the walk, so a
    /// `Shader`, `VertexShader`, `TextureView` or `ThorCanvas` nested inside
    /// has no window slot to reach for and draws nothing.
    func list<Content: View>(of view: Content, size: Size) -> DisplayList {
        guard size.width > 0, size.height > 0 else { return DisplayList() }

        // Saved and restored rather than set and cleared: a render queued to
        // `endPass` runs with the window's own globals already down, but a
        // texture rendered from inside another texture's content would nest,
        // and this is what keeps that honest.
        let outerAnimations = AnimationStore.current
        let outerHost = ShaderHost.current
        AnimationStore.current = animations
        ShaderHost.current = nil
        defer {
            AnimationStore.current = outerAnimations
            ShaderHost.current = outerHost
        }

        animations.beginFrame()
        animations.beginPass(transaction: nil, isCommit: true)

        records.beginRebuild(under: [Self.rootIndex])
        var context = BuildContext(
            environment: environment,
            store: store,
            effects: effects,
            animations: animations,
            records: records
        )
        context.path = [Self.rootIndex]
        let node = buildNode(view, &context)
        releaseDeparted()

        var draw = DrawContext(colorScheme: environment.colorScheme)
        // The list is the texture: a drawing group inside draws into it.
        draw.flattensRenderNodes = true
        var list = DisplayList()
        node.place(
            in: Rect(origin: .zero, size: size),
            proposal: ProposedSize(size),
            context: draw,
            into: &list
        )
        animations.endPass()
        // `effects` is deliberately not drained: there is no appearance to
        // report. An `onAppear` body is for a view that is on screen and
        // routinely writes state — running it here would dirty the window's
        // frame for a tree the window cannot see.
        return list
    }

    /// Let go of what a render did not put back — the same bookkeeping
    /// `ViewHost` does after a rebuild, so a texture whose content changed
    /// shape does not keep the old subtree's state and reader registrations
    /// alive.
    private func releaseDeparted() {
        let departed = records.endRebuild()
        guard !departed.isEmpty else { return }
        for (path, entry) in departed {
            for storage in entry.reads {
                storage.readers.removeValue(forKey: path)
            }
            store.release(entry.stateKeys)
        }
        let paths = Set(departed.map { $0.0 })
        effects.forget(paths: paths)
        animations.forget(paths: paths)
    }
}
