//
//  Environment.swift
//  NucleantUI
//

/// A key into `EnvironmentValues`.
public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

/// Values handed down a subtree — the foreground color a `Text` picks up, the
/// font it inherits, the tint a `Button` uses.
///
/// Every read of a value is noted against the view being built
/// (`EnvironmentReads`), so a view is rebuilt for a change of the values it
/// read, not of any value at all.
public struct EnvironmentValues: @unchecked Sendable {

    /// One value, with the write that put it there. Copies of an
    /// environment share their entries, so two entries with the same stamp
    /// are the same write — the same value, inherited — and need no
    /// comparing.
    struct Entry {
        var value: Any
        var stamp: UInt64
    }

    private var storage: [ObjectIdentifier: Entry] = [:]

    /// The stamp of the last write, so two values with the same version are
    /// copies of one another. Different versions say nothing either way —
    /// see `agrees(with:on:)`.
    private(set) var version: UInt64 = 0

    nonisolated(unsafe) private static var nextStamp: UInt64 = 1

    private static func takeStamp() -> UInt64 {
        defer { nextStamp &+= 1 }
        return nextStamp
    }

    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get {
            let id = ObjectIdentifier(key)
            EnvironmentReads.shared.note(id)
            return storage[id]?.value as? K.Value ?? K.defaultValue
        }
        set {
            let stamp = Self.takeStamp()
            storage[ObjectIdentifier(key)] = Entry(value: newValue, stamp: stamp)
            version = stamp
        }
    }

    /// Whether a view that read `keys` would see the same values under
    /// `other`.
    ///
    /// A parent that re-runs re-applies its `.font(…)` and produces a fresh
    /// write, so the stamps usually differ even when nothing did; the values
    /// are then compared. A value the framework can't compare — a closure,
    /// a class it was handed anew — counts as changed, which only ever costs
    /// a rebuild, and only of the views that read it.
    @MainActor
    func agrees(with other: EnvironmentValues, on keys: Set<ObjectIdentifier>) -> Bool {
        if version == other.version { return true }
        for key in keys where !hasSameValue(at: key, as: other) {
            return false
        }
        return true
    }

    /// The keys whose values differ between this and `other`, a key set in
    /// one and not the other included.
    @MainActor
    func keysDiffering(from other: EnvironmentValues) -> [ObjectIdentifier] {
        if version == other.version { return [] }
        var keys: [ObjectIdentifier] = []
        for key in storage.keys where !hasSameValue(at: key, as: other) {
            keys.append(key)
        }
        for key in other.storage.keys where storage[key] == nil {
            keys.append(key)
        }
        return keys
    }

    @MainActor
    private func hasSameValue(at key: ObjectIdentifier, as other: EnvironmentValues) -> Bool {
        switch (storage[key], other.storage[key]) {
        case (nil, nil):
            return true
        case let (mine?, theirs?):
            return mine.stamp == theirs.stamp || _dynamicallyEquivalent(mine.value, theirs.value)
        default:
            return false
        }
    }

    /// This environment, which was derived from `old`, as it would have been
    /// derived from `new`: each of `keys` this one inherited from `old`
    /// unchanged takes `new`'s value; one written on the way down keeps its
    /// own.
    func rebased(from old: EnvironmentValues, to new: EnvironmentValues, keys: [ObjectIdentifier]) -> EnvironmentValues {
        var result = self
        var changed = false
        for key in keys where storage[key]?.stamp == old.storage[key]?.stamp {
            result.storage[key] = new.storage[key]
            changed = true
        }
        if changed { result.version = Self.takeStamp() }
        return result
    }
}

/// Reads one environment value.
///
/// ```swift
/// @Environment(\.foregroundStyle) private var foreground
/// ```
@propertyWrapper
@MainActor
public struct Environment<Value>: DynamicProperty {

    final class Holder {
        var value: Value?
    }

    private let holder = Holder()
    private let read: (EnvironmentValues) -> Value

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.read = { $0[keyPath: keyPath] }
    }

    public var wrappedValue: Value {
        guard let value = holder.value else {
            preconditionFailure(
                "@Environment read before the view was built — environment values "
                + "are only available inside `body`."
            )
        }
        return value
    }

    public func _bind(to context: BindingContext) {
        holder.value = read(context.environment)
    }
}

// MARK: - Built-in keys

private struct ForegroundStyleKey: EnvironmentKey {
    static let defaultValue = ShapeStyle.primary
}

private struct FontKey: EnvironmentKey {
    static let defaultValue = Font.body
}

private struct TintKey: EnvironmentKey {
    static let defaultValue = ShapeStyle.color(.blue)
}

private struct IsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct MultilineTextAlignmentKey: EnvironmentKey {
    static let defaultValue = TextAlignment.leading
}

private struct LineLimitKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

private struct DisplayScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

private struct ColorSchemeKey: EnvironmentKey {
    static let defaultValue = ColorScheme.light
}

extension EnvironmentValues {
    public var foregroundStyle: ShapeStyle {
        get { self[ForegroundStyleKey.self] }
        set { self[ForegroundStyleKey.self] = newValue }
    }

    public var font: Font {
        get { self[FontKey.self] }
        set { self[FontKey.self] = newValue }
    }

    public var tint: ShapeStyle {
        get { self[TintKey.self] }
        set { self[TintKey.self] = newValue }
    }

    public var isEnabled: Bool {
        get { self[IsEnabledKey.self] }
        set { self[IsEnabledKey.self] = newValue }
    }

    public var multilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self] }
        set { self[MultilineTextAlignmentKey.self] = newValue }
    }

    public var lineLimit: Int? {
        get { self[LineLimitKey.self] }
        set { self[LineLimitKey.self] = newValue }
    }

    /// Backing-store pixels per point. The window seeds it from the layer's
    /// `contentsScale`; layout runs in points and the renderer scales up.
    public var displayScale: Double {
        get { self[DisplayScaleKey.self] }
        set { self[DisplayScaleKey.self] = newValue }
    }

    /// Light or dark. The window seeds it from the system and follows
    /// changes; `.colorScheme(_:)` overrides it below that point.
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }
}
