//
//  TransitionEffect.swift
//  NucleantUI
//
//  The framework's own transitions, as what they draw: an opacity, an
//  offset, a move by a fraction of the view's size, a scale about an
//  anchor — the effects their bodies' modifiers apply, in the same order.
//  A container's slot draws these itself around the view it stands on, so
//  a view arriving or leaving under one of them has no body built for it:
//  no modifier nodes, nothing built again from phase to phase, only one
//  vector of numbers animated (TransitionSlots.swift).
//
//  A transition that cannot say — one written outside the framework, or
//  one carrying an animation of its own — keeps its body.
//

/// One effect a built-in transition draws its view with.
enum TransitionEffect: Equatable {
    /// `.opacity(_:)`.
    case opacity(Double)
    /// `.offset(x:y:)`.
    case offset(x: Double, y: Double)
    /// `moveEffect(towards:)`: a fraction of the view's own size, (-1, 0)
    /// one width to the left.
    case move(x: Double, y: Double)
    /// `.scaleEffect(x:y:anchor:)`.
    case scale(x: Double, y: Double, anchor: UnitPoint)

    /// The numbers that animate.
    var values: [Double] {
        switch self {
        case .opacity(let opacity): return [opacity]
        case .offset(let x, let y), .move(let x, let y), .scale(let x, let y, _): return [x, y]
        }
    }

    /// Whether `other` is the same effect — so the two animate into each
    /// other — whatever its numbers.
    func hasShape(of other: TransitionEffect) -> Bool {
        switch (self, other) {
        case (.opacity, .opacity), (.offset, .offset), (.move, .move): return true
        case (.scale(_, _, let a), .scale(_, _, let b)): return a == b
        default: return false
        }
    }

    /// `context` with this effect applied, the view drawn in `rect` —
    /// exactly what the modifier it stands for does.
    func apply(_ values: ArraySlice<Double>, to context: inout DrawContext, in rect: Rect) {
        let first = values[values.startIndex]
        switch self {
        case .opacity:
            context.opacity *= min(max(first, 0), 1)
        case .offset:
            let y = values[values.startIndex + 1]
            if first != 0 || y != 0 {
                context.transform = context.transform.concatenating(.translation(x: first, y: y))
            }
        case .move:
            let dx = first * rect.width
            let dy = values[values.startIndex + 1] * rect.height
            if dx != 0 || dy != 0 {
                context.transform = context.transform.concatenating(.translation(x: dx, y: dy))
            }
        case .scale(_, _, let anchor):
            let y = values[values.startIndex + 1]
            context.transform = context.transform
                .concatenating(.around(anchor.resolved(in: rect), .scale(x: first, y: y)))
        }
    }
}

/// What a slot draws its view with while a built-in transition stands on
/// it: the effects, innermost first, and their numbers, animated from
/// phase to phase.
@MainActor
final class TransitionEffects {
    /// The effects as last set: their kinds and anchors. The numbers drawn
    /// are `values`'.
    private(set) var effects: [TransitionEffect]
    private var values: AnimatedVector

    init(_ effects: [TransitionEffect]) {
        self.effects = effects
        values = AnimatedVector(effects.flatMap(\.values))
    }

    /// Move to `newEffects` under `animation`: the numbers animate when the
    /// effects are the same ones, and change at once when they are not —
    /// the transition itself was swapped for another. `nil` is a
    /// transition that draws through its body: nothing drawn here.
    func update(to newEffects: [TransitionEffect]?, animation: Animation?, in store: AnimationStore) {
        guard let newEffects else {
            effects = []
            values = AnimatedVector([])
            return
        }
        let sameShape = newEffects.count == effects.count
            && zip(newEffects, effects).allSatisfy { $0.hasShape(of: $1) }
        if sameShape {
            values.update(to: newEffects.flatMap(\.values), animation: animation, in: store)
        } else {
            values = AnimatedVector(newEffects.flatMap(\.values))
        }
        effects = newEffects
    }

    /// `context` with every effect applied, outermost first — as the
    /// modifiers would be, each wrapping the ones inside it.
    func apply(to context: DrawContext, in rect: Rect) -> DrawContext {
        guard !effects.isEmpty else { return context }
        let numbers = values.current()
        var starts: [Int] = []
        starts.reserveCapacity(effects.count)
        var next = 0
        for effect in effects {
            starts.append(next)
            next += effect.values.count
        }
        guard numbers.count == next else { return context }
        var inner = context
        for index in effects.indices.reversed() {
            let start = starts[index]
            let count = effects[index].values.count
            effects[index].apply(numbers[start..<start + count], to: &inner, in: rect)
        }
        return inner
    }
}

// MARK: - What each built-in transition draws

extension Transition {
    /// What this transition draws in `phase`, when it is one of the
    /// framework's own that can say; `nil` when its body has to be built.
    func builtinEffects(in phase: TransitionPhase) -> [TransitionEffect]? {
        guard let type = Self.self as? any BuiltinTransition.Type else { return nil }
        return Self.effects(of: self, as: type, in: phase)
    }

    private static func effects<B: BuiltinTransition>(of transition: Self, as _: B.Type, in phase: TransitionPhase) -> [TransitionEffect]? {
        (transition as? B)?.effects(in: phase)
    }
}

extension BuiltinTransition {
    /// None by default: the body is built.
    func effects(in phase: TransitionPhase) -> [TransitionEffect]? { nil }
}
