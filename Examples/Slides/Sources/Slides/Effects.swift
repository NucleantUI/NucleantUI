//
//  Effects.swift
//  Slides
//
//  How a slide comes on and goes off, and how its points come and go.
//
//  Every effect is a `Transition`. Most are the framework's own (`.opacity`,
//  `.push(from:)`, `.move(edge:)`, `.slide`, `.scale` and combinations of
//  them); the rest are this app's, each a struct whose `body(content:phase:)`
//  says what the slide looks like before it arrives, while it is shown and
//  after it leaves — the modifiers in that body animate their own values
//  from one phase to the next, and that is the effect. A slide keeps its
//  choice as an `Effect`; `Effect.transition` hands back the transition,
//  erased into an `AnyTransition`, since every slide's can be a different
//  type and the stage needs one type to hold whichever it is.
//

import NucleantUI

/// An effect a slide or a point can come and go with.
enum Effect: CaseIterable, Identifiable, Hashable {
    // The framework's.
    case none, dissolve, pushFromRight, pushFromLeft, moveUp, moveDown, slide, scale, zoom, rise
    // This app's own.
    case spin, flip, drop, swing, curtain, ink

    var id: Self { self }

    var name: String {
        switch self {
        case .none: return "None"
        case .dissolve: return "Dissolve"
        case .pushFromRight: return "Push from Right"
        case .pushFromLeft: return "Push from Left"
        case .moveUp: return "Move Up"
        case .moveDown: return "Move Down"
        case .slide: return "Slide"
        case .scale: return "Scale"
        case .zoom: return "Zoom"
        case .rise: return "Rise"
        case .spin: return "Spin"
        case .flip: return "Flip"
        case .drop: return "Drop"
        case .swing: return "Swing"
        case .curtain: return "Curtain"
        case .ink: return "Ink"
        }
    }

    /// The ones built from the framework's transitions, and the app's own.
    static let builtIn: [Effect] = [.none, .dissolve, .pushFromRight, .pushFromLeft, .moveUp, .moveDown, .slide, .scale, .zoom, .rise]
    static let custom: [Effect] = [.spin, .flip, .drop, .swing, .curtain, .ink]

    /// The transition, erased: whichever type it is, a slide's entrance and
    /// exit, and a point's build, are one `AnyTransition` each.
    @MainActor
    var transition: AnyTransition {
        switch self {
        case .none: return .identity
        case .dissolve: return .opacity
        case .pushFromRight: return .push(from: .trailing)
        case .pushFromLeft: return .push(from: .leading)
        case .moveUp: return .move(edge: .bottom)
        case .moveDown: return .move(edge: .top)
        case .slide: return .slide
        case .scale: return .scale
        case .zoom: return .scale(scale: 1.35).combined(with: .opacity)
        case .rise: return .offset(y: 70).combined(with: .opacity)
        case .spin: return AnyTransition(RotatingFade())
        case .flip: return AnyTransition(Flip())
        case .drop: return AnyTransition(Drop())
        case .swing: return AnyTransition(Swing())
        case .curtain: return AnyTransition(Curtain(color: SlideTheme.curtain))
        case .ink: return .modifier(active: Ink(amount: 1), identity: Ink(amount: 0))
        }
    }
}

extension Slide {
    /// How the slide comes on and goes off: its entrance on the way in, its
    /// exit on the way out, each run with the slide's own timing — brought
    /// with the transition, so turning a slide needs no `withAnimation`.
    @MainActor
    var transition: AnyTransition {
        .asymmetric(insertion: entrance.transition, removal: exit.transition)
            .animation(curve.animation(duration: duration))
    }

    /// How a point comes and goes, a little quicker than the slide.
    @MainActor
    var pointTransition: AnyTransition {
        build.transition.animation(curve.animation(duration: duration * 0.7))
    }
}

// MARK: - The app's own transitions

/// Fades in turning from 30°, and out turning on to -30° — the
/// `RotatingFadeTransition` of `Transition`'s documentation, with a little
/// scale for depth.
struct RotatingFade: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .rotationEffect(.degrees(-30 * phase.value))
            .scaleEffect(phase.isIdentity ? 1 : 0.85)
    }
}

/// Turned over like a card: squeezed to an edge, then opened out flat.
struct Flip: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(x: phase.isIdentity ? 1 : 0.02, y: phase.isIdentity ? 1 : 0.94)
            .opacity(phase.isIdentity ? 1 : 0.3)
    }
}

/// Falls in from above, tilted, and falls away below, tilted the other way
/// — the direction from `phase.value`, -1 on the way in and 1 on the way out.
struct Drop: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .offset(y: 160 * phase.value)
            .rotationEffect(.degrees(-5 * phase.value))
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// Swings in and out on a hinge at its top-leading corner.
struct Swing: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .rotationEffect(.degrees(phase.isIdentity ? 0 : -80), anchor: .topLeading)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// A curtain over the slide: drawn back to the right to reveal it, drawn
/// across from the left to hide it. The curtain is a view of the
/// transition's own, laid over the slide — a transition's body is any view.
struct Curtain: Transition {
    let color: Color

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.overlay(
            Rectangle()
                .fill(color)
                .scaleEffect(
                    x: phase.isIdentity ? 0 : 1,
                    y: 1,
                    anchor: phase == .didDisappear ? .leading : .trailing
                )
        )
    }
}

/// Ink washed over the view: thick at 1, gone at 0, the view itself only
/// fading in the thickest part. `Animatable`, so a change of `amount`
/// redraws it at every value in between — what
/// `AnyTransition.modifier(active: Ink(amount: 1), identity: Ink(amount: 0))`
/// animates.
struct Ink: ViewModifier, Animatable {
    var amount: Double

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        content
            .overlay(Rectangle().fill(SlideTheme.ink).opacity(min(1, amount * 1.6)))
            .opacity(1 - max(0, amount - 0.6) / 0.4)
    }
}
