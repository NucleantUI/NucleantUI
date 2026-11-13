//
//  PreferenceKey.swift
//  NucleantUI
//
//  Values handed *up* the tree — the opposite of `EnvironmentValues`. A view
//  sets one with `.preference(key:value:)`; every ancestor sees the values
//  of its subtree combined by the key's `reduce`, and `.onPreferenceChange`
//  is told when that combination changes.
//
//  Preferences are read off the built node tree rather than carried through
//  the build: a scoped rebuild replaces a subtree without its ancestors
//  running again, so an ancestor can only learn the new value by looking
//  down. Each node caches what it reduced to per key, and a graft clears the
//  caches along the path above it (`invalidateMeasurementsUpwards`), so a
//  lookup only walks what changed.
//

/// A named value produced by a view, combined across a subtree.
///
/// ```swift
/// struct TitleKey: PreferenceKey {
///     static let defaultValue = ""
///     static func reduce(value: inout String, nextValue: () -> String) {
///         if value.isEmpty { value = nextValue() }
///     }
/// }
///
/// Page().preference(key: TitleKey.self, value: "Inbox")
/// ```
public protocol PreferenceKey {
    /// The type of value produced by this preference.
    associatedtype Value

    /// The value a subtree has when no view in it sets one.
    static var defaultValue: Value { get }

    /// Combine the value accumulated so far with the next one, in view-tree
    /// order — conceptually, a subtree's value with its next sibling's.
    static func reduce(value: inout Value, nextValue: () -> Value)
}

extension PreferenceKey where Value: ExpressibleByNilLiteral {
    /// Let nil-expressible values default to nil.
    public static var defaultValue: Value { nil }
}

// MARK: - Reading the tree

extension ViewNode {

    /// What this subtree's views set for `key`, combined — `nil` when none
    /// of them set anything. Views that set nothing take no part in the
    /// reduction, so `reduce` only ever sees values someone wrote.
    func preference<K: PreferenceKey>(_ key: K.Type) -> K.Value? {
        let id = ObjectIdentifier(key)
        if let cached = preferenceCache[id], let value = cached.value(as: K.Value?.self) {
            return value
        }
        var combined: K.Value?
        for child in children where !child.isLeaving {
            guard let next = child.preference(key) else { continue }
            if combined == nil {
                combined = next
            } else {
                K.reduce(value: &combined!) { next }
            }
        }
        // Each node says what flows up through it — see
        // `NodeContent.preference(_:below:)`.
        combined = contentPreference(key, below: combined)
        preferenceCache[id] = Box(combined)
        return combined
    }
}

// MARK: - Observing

/// One `.onPreferenceChange`: the node whose subtree it watches, and the
/// value its action was last handed.
@MainActor
final class PreferenceObservation {
    weak var node: ViewNode?
    /// The value last delivered, kept across rebuilds of the observing view
    /// so a parent re-running doesn't re-deliver an unchanged value.
    var delivered: AnyBox?
    /// The action to run if the value has changed since `delivered`.
    private let check: @MainActor (PreferenceObservation) -> (@MainActor () -> Void)?

    init<K: PreferenceKey>(
        _ key: K.Type,
        node: ViewNode,
        action: @escaping @MainActor (K.Value) -> Void
    ) where K.Value: Equatable {
        self.node = node
        self.check = { observation in
            guard let node = observation.node else { return nil }
            let value = node.preference(K.self) ?? K.defaultValue
            if let previous = observation.delivered?.value(as: K.Value.self), previous == value {
                return nil
            }
            observation.delivered = Box(value)
            return { action(value) }
        }
    }

    func change() -> (@MainActor () -> Void)? { check(self) }
}

/// Every `.onPreferenceChange` standing, by the path of the view that
/// attached it. Owned by the `EffectQueue`, whose `forget(paths:)` is what
/// drops the ones that leave the tree.
@MainActor
final class PreferenceObservers {
    private var observations: [[Int]: PreferenceObservation] = [:]

    /// The paths of `observations`, outermost first: a stable order, rather
    /// than dictionary order. Sorted again only after one came or went — a
    /// view that re-runs files its observation at the path it had.
    private var order: [[Int]]?

    func observe(_ observation: PreferenceObservation, at path: [Int]) {
        let previous = observations.updateValue(observation, forKey: path)
        observation.delivered = previous?.delivered
        if previous == nil { order = nil }
    }

    func forget(paths: Set<[Int]>) {
        guard !observations.isEmpty else { return }
        for path in paths where observations.removeValue(forKey: path) != nil {
            order = nil
        }
    }

    /// The actions whose values changed in the tree as it now stands — run
    /// with the pass's other effects, after the tree is built and placed.
    func changes() -> [@MainActor () -> Void] {
        guard !observations.isEmpty else { return [] }
        let order = self.order ?? observations.keys.sorted { $0.lexicographicallyPrecedes($1) }
        self.order = order
        return order.compactMap { observations[$0]?.change() }
    }
}
