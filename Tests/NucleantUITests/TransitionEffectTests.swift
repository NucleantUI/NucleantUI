//
//  TransitionEffectTests.swift
//  NucleantUITests
//
//  The framework's transitions drawn as effects, without a body: which
//  transitions say what they draw (and so build nothing), what they say in
//  each phase — the same as their bodies' modifiers — and that the effects
//  are drawn in the bodies' order, outermost first. How they look on screen
//  while a view arrives and leaves is in TransitionTests (fades, moves,
//  pushes and offsets, read off the pixels drawn and the views hit).
//

import Testing
@testable import NucleantUI

@Suite
@MainActor
struct TransitionEffectTests {

    // MARK: - Which transitions build nothing

    @Test func theFrameworksTransitionsSayWhatTheyDraw() {
        #expect(AnyTransition.opacity.box.effects(in: .willAppear) == [.opacity(0)])
        #expect(AnyTransition.opacity.box.effects(in: .identity) == [.opacity(1)])

        #expect(AnyTransition.move(edge: .leading).box.effects(in: .willAppear) == [.move(x: -1, y: 0)])
        #expect(AnyTransition.move(edge: .bottom).box.effects(in: .didDisappear) == [.move(x: 0, y: 1)])
        #expect(AnyTransition.move(edge: .bottom).box.effects(in: .identity) == [.move(x: 0, y: 0)])

        // In from the leading edge, out to the trailing.
        #expect(AnyTransition.slide.box.effects(in: .willAppear) == [.move(x: -1, y: 0)])
        #expect(AnyTransition.slide.box.effects(in: .didDisappear) == [.move(x: 1, y: 0)])

        // The move inside the fade, out through the far side.
        #expect(AnyTransition.push(from: .top).box.effects(in: .willAppear) == [.move(x: 0, y: -1), .opacity(0)])
        #expect(AnyTransition.push(from: .top).box.effects(in: .didDisappear) == [.move(x: 0, y: 1), .opacity(0)])

        #expect(AnyTransition.scale(scale: 0.5, anchor: .topLeading).box.effects(in: .willAppear)
            == [.scale(x: 0.5, y: 0.5, anchor: .topLeading)])
        #expect(AnyTransition.offset(x: 10, y: 20).box.effects(in: .didDisappear) == [.offset(x: 10, y: 20)])
    }

    @Test func compositionsSayWhatTheirHalvesDraw() {
        // Each half only in its own direction: the insertion inside.
        let asymmetric = AnyTransition.asymmetric(insertion: .move(edge: .leading), removal: .opacity)
        #expect(asymmetric.box.effects(in: .willAppear) == [.move(x: -1, y: 0), .opacity(1)])
        #expect(asymmetric.box.effects(in: .didDisappear) == [.move(x: 0, y: 0), .opacity(0)])

        // The receiver inside the argument.
        let combined = AnyTransition.opacity.combined(with: .scale(scale: 0.5, anchor: .center))
        #expect(combined.box.effects(in: .willAppear) == [.opacity(0), .scale(x: 0.5, y: 0.5, anchor: .center)])
    }

    @Test func transitionsThatCannotSayBuildTheirBody() {
        let log = Log()
        // Written outside the framework.
        #expect(AnyTransition(PhaseRecorder(name: "r", log: log)).box.effects(in: .willAppear) == nil)
        // An animation of its own.
        #expect(AnyTransition.opacity.animation(.linear(duration: 1)).box.effects(in: .willAppear) == nil)
        // Any modifier at all.
        #expect(AnyTransition.modifier(active: Probe(amount: 1, log: log), identity: Probe(amount: 0, log: log))
            .box.effects(in: .willAppear) == nil)
        // A built-in combined with one that cannot say.
        #expect(AnyTransition.opacity.combined(with: AnyTransition(PhaseRecorder(name: "r", log: log)))
            .box.effects(in: .willAppear) == nil)
        #expect(log.take().isEmpty, "asking builds nothing")
    }

    // MARK: - How they are drawn

    private let rect = Rect(x: 0, y: 0, width: 100, height: 100)

    @Test func effectsApplyOutermostFirstAsTheModifiersWould() {
        // `.scaleEffect(0.5)` inside `.offset(x: 10)`: the offset's
        // translation first, then the scale about the centre.
        let effects = TransitionEffects([.scale(x: 0.5, y: 0.5, anchor: .center), .offset(x: 10, y: 0)])
        let drawn = effects.apply(to: DrawContext(), in: rect)
        let expected = Transform.identity
            .concatenating(.translation(x: 10, y: 0))
            .concatenating(.around(Point(x: 50, y: 50), .scale(x: 0.5, y: 0.5)))
        #expect(drawn.transform == expected)

        // The other way round is a different picture.
        let reversed = TransitionEffects([.offset(x: 10, y: 0), .scale(x: 0.5, y: 0.5, anchor: .center)])
        #expect(reversed.apply(to: DrawContext(), in: rect).transform != expected)
    }

    @Test func aMoveIsAFractionOfTheViewsOwnSize() {
        let effects = TransitionEffects([.move(x: -1, y: 0.5)])
        let drawn = effects.apply(to: DrawContext(), in: Rect(x: 0, y: 0, width: 80, height: 40))
        #expect(drawn.transform == Transform.identity.concatenating(.translation(x: -80, y: 20)))
    }

    @Test func anOpacityMultipliesTheOneDrawnUnder() {
        var context = DrawContext()
        context.opacity = 0.5
        let drawn = TransitionEffects([.opacity(0.5)]).apply(to: context, in: rect)
        #expect(drawn.opacity == 0.25)
        #expect(drawn.transform == .identity)
    }

    @Test func aSwappedTransitionChangesItsEffectsAtOnce() {
        let store = AnimationStore()
        let effects = TransitionEffects([.opacity(0)])
        effects.update(to: [.move(x: -1, y: 0)], animation: .linear(duration: 1), in: store)
        #expect(effects.effects == [.move(x: -1, y: 0)])
        // Not animating from the fade's numbers: drawn where it says.
        #expect(effects.apply(to: DrawContext(), in: rect).transform
            == Transform.identity.concatenating(.translation(x: -100, y: 0)))
        // A transition that has to build its body: nothing drawn here.
        effects.update(to: nil, animation: nil, in: store)
        #expect(effects.effects.isEmpty)
        #expect(effects.apply(to: DrawContext(), in: rect).transform == .identity)
    }
}
