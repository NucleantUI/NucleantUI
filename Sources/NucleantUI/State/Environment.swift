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
///
/// The values are a chain of the writes made, newest first, each holding its
/// value as its key's type (`EnvironmentEntryOf`). A write puts one entry in
/// front and copies nothing: the environment it was made in keeps the chain
/// behind it, which the two now share. A read walks to the newest entry for
/// its key and takes the value as it is stored.
public struct EnvironmentValues: @unchecked Sendable {

    /// The newest write; nil when nothing was written.
    private(set) var head: EnvironmentEntry?

    /// A stamp taken by the last write, so two values with the same version
    /// are copies of one another. Different versions say nothing either way —
    /// see `agrees(with:on:)`.
    private(set) var version: UInt64 = 0

    nonisolated(unsafe) private static var nextStamp: UInt64 = 1

    static func takeStamp() -> UInt64 {
        defer { nextStamp &+= 1 }
        return nextStamp
    }

    /// Writes past this many in one chain are folded into a chain of one
    /// entry per key. Writes made on the way down are as many as the
    /// modifiers above a view; this only stops a value written over and
    /// over in place — a window following its system's settings — from
    /// growing without end.
    private static let longestChain = 64

    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get {
            let id = ObjectIdentifier(key)
            let index = EnvironmentReads.shared.noteRead(id)
            guard let entry = head?.newest(id, index: index) else { return K.defaultValue }
            // Only an entry for `K` is filed under `K`'s identifier.
            return unsafeDowncast(entry, to: EnvironmentEntryOf<K>.self).value
        }
        set {
            let stamp = Self.takeStamp()
            let id = ObjectIdentifier(key)
            let entry = EnvironmentEntryOf<K>(
                key: id, index: EnvironmentReads.shared.index(of: id), stamp: stamp, value: newValue, next: head
            )
            head = entry.depth > Self.longestChain ? entry.folded() : entry
            version = stamp
        }
    }

    /// Whether a view that read `keys` would see the same values under
    /// `other`.
    ///
    /// A parent that re-runs re-applies its `.font(…)` and produces a fresh
    /// write, so the stamps usually differ even when nothing did; the values
    /// are then compared. Only keys written in the parts of the two chains
    /// that are not shared can differ, so only those are looked at. A value
    /// the framework can't compare — a closure, a class it was handed anew —
    /// counts as changed, which only ever costs a rebuild, and only of the
    /// views that read it.
    @MainActor
    func agrees(with other: EnvironmentValues, on keys: EnvironmentKeySet) -> Bool {
        if version == other.version || keys.isEmpty { return true }
        var checked = EnvironmentKeySet()
        return EnvironmentEntry.allUnshared(head, other.head) { entry in
            guard keys.contains(entry.index) else { return true }
            if entry.index != EnvironmentKeySet.overflowBit {
                if checked.contains(entry.index) { return true }
                checked.insert(entry.index)
            }
            return hasSameValue(at: entry.key, index: entry.index, as: other)
        }
    }

    /// Whether any value differs between this and `other`, a key set in one
    /// and not the other included.
    @MainActor
    func differs(from other: EnvironmentValues) -> Bool {
        if version == other.version { return false }
        var checked = EnvironmentKeySet()
        return !EnvironmentEntry.allUnshared(head, other.head) { entry in
            if entry.index != EnvironmentKeySet.overflowBit {
                if checked.contains(entry.index) { return true }
                checked.insert(entry.index)
            }
            return hasSameValue(at: entry.key, index: entry.index, as: other)
        }
    }

    @MainActor
    private func hasSameValue(at key: ObjectIdentifier, index: Int, as other: EnvironmentValues) -> Bool {
        switch (head?.newest(key, index: index), other.head?.newest(key, index: index)) {
        case (nil, nil):
            return true
        case let (mine?, theirs?):
            return mine === theirs || mine.stamp == theirs.stamp || mine.hasSameValue(as: theirs)
        default:
            return false
        }
    }

    /// This environment, which was derived from `old`, as it would have been
    /// derived from `new`: a value written on the way down from `old` keeps
    /// its own, and one inherited from `old` is `new`'s.
    ///
    /// Derived means `old`'s chain is the tail of this one; the writes in
    /// front of it are put in front of `new`'s instead. `relinked` keeps the
    /// entries already moved, by the entry they were moved from, so the
    /// environments of a subtree — which share their writes from the top
    /// down — share them after as well. An environment not derived from
    /// `old` takes `new`'s value for each key that differs between the two
    /// and that it holds as `old` does.
    @MainActor
    func rebased(
        from old: EnvironmentValues,
        to new: EnvironmentValues,
        relinked: inout [ObjectIdentifier: (from: EnvironmentEntry, to: EnvironmentEntry)]
    ) -> EnvironmentValues {
        if version == old.version { return new }
        var result = self
        if let head = relink(head, from: old.head, to: new.head, relinked: &relinked) {
            result.head = head
        } else {
            result.head = rebasedKeyByKey(from: old, to: new)
        }
        result.version = Self.takeStamp()
        return result
    }

    /// `entry`'s chain up to `old`, in front of `new`; nil when the chain
    /// ends before it meets `old`.
    @MainActor
    private func relink(
        _ entry: EnvironmentEntry?,
        from old: EnvironmentEntry?,
        to new: EnvironmentEntry?,
        relinked: inout [ObjectIdentifier: (from: EnvironmentEntry, to: EnvironmentEntry)]
    ) -> EnvironmentEntry?? {
        if entry === old { return .some(new) }
        guard let entry else { return nil }
        if let moved = relinked[ObjectIdentifier(entry)], moved.from === entry { return .some(moved.to) }
        guard let next = relink(entry.next, from: old, to: new, relinked: &relinked) else { return nil }
        let moved = entry.relinked(onto: next)
        relinked[ObjectIdentifier(entry)] = (entry, moved)
        return .some(moved)
    }

    @MainActor
    private func rebasedKeyByKey(from old: EnvironmentValues, to new: EnvironmentValues) -> EnvironmentEntry? {
        var result = head
        var checked = EnvironmentKeySet()
        _ = EnvironmentEntry.allUnshared(old.head, new.head) { entry in
            if entry.index != EnvironmentKeySet.overflowBit {
                if checked.contains(entry.index) { return true }
                checked.insert(entry.index)
            }
            guard !old.hasSameValue(at: entry.key, index: entry.index, as: new) else { return true }
            let mine = head?.newest(entry.key, index: entry.index)
            let olds = old.head?.newest(entry.key, index: entry.index)
            guard mine === olds || (mine != nil && mine?.stamp == olds?.stamp) else { return true }
            if let theirs = new.head?.newest(entry.key, index: entry.index) {
                result = theirs.relinked(onto: result)
            } else {
                // `new` never wrote it: its default, over what this held.
                result = entry.defaulted(onto: result)
            }
            return true
        }
        return result
    }
}

/// One write into an environment: its key, its stamp, and the write before
/// it. The value is on `EnvironmentEntryOf`, as its key's type.
///
/// An entry never changes, so environments share them: one derived from
/// another holds the other's chain as its tail.
class EnvironmentEntry {
    let key: ObjectIdentifier
    /// The key's bit (`EnvironmentReads.index(of:)`).
    let index: Int
    /// The write that made the value. A copy of the entry — moved in front
    /// of another chain — keeps it: the same stamp is the same value.
    let stamp: UInt64
    let next: EnvironmentEntry?
    /// How many entries there are from this one to the end of the chain.
    let depth: Int
    /// The bits of the keys in this entry and every one after it, so a read
    /// of a key nobody wrote ends at once.
    let keys: EnvironmentKeySet

    init(key: ObjectIdentifier, index: Int, stamp: UInt64, next: EnvironmentEntry?) {
        self.key = key
        self.index = index
        self.stamp = stamp
        self.next = next
        self.depth = (next?.depth ?? 0) + 1
        var keys = next?.keys ?? EnvironmentKeySet()
        keys.insert(index)
        self.keys = keys
    }

    /// The newest entry for `key`, from this one on.
    @inline(__always)
    final func newest(_ key: ObjectIdentifier, index: Int) -> EnvironmentEntry? {
        var entry: EnvironmentEntry? = self
        while let current = entry, current.keys.contains(index) {
            if current.key == key { return current }
            entry = current.next
        }
        return nil
    }

    /// Whether this entry's value is the same view input as `other`'s, an
    /// entry for the same key.
    @MainActor
    func hasSameValue(as other: EnvironmentEntry) -> Bool {
        fatalError("EnvironmentEntryOf overrides it")
    }

    /// This entry's value and stamp, in front of `next`.
    func relinked(onto next: EnvironmentEntry?) -> EnvironmentEntry {
        fatalError("EnvironmentEntryOf overrides it")
    }

    /// This entry's key at its default value, with a stamp of its own, in
    /// front of `next`.
    func defaulted(onto next: EnvironmentEntry?) -> EnvironmentEntry {
        fatalError("EnvironmentEntryOf overrides it")
    }

    /// The same values in a chain of one entry per key: the newest of each,
    /// in the order they were written.
    final func folded() -> EnvironmentEntry {
        var newest: [EnvironmentEntry] = []
        var seen: Set<ObjectIdentifier> = []
        var entry: EnvironmentEntry? = self
        while let current = entry {
            if seen.insert(current.key).inserted { newest.append(current) }
            entry = current.next
        }
        var chain: EnvironmentEntry?
        for current in newest.reversed() {
            chain = current.relinked(onto: chain)
        }
        return chain!
    }

    /// Whether `body` holds for every entry of `a` and of `b` that the two
    /// do not share. Chains share their tails: the longer one is walked
    /// down to the other's length, then both together until they meet.
    @inline(__always)
    static func allUnshared(
        _ a: EnvironmentEntry?, _ b: EnvironmentEntry?, _ body: (EnvironmentEntry) -> Bool
    ) -> Bool {
        var a = a, b = b
        var depthA = a?.depth ?? 0, depthB = b?.depth ?? 0
        while depthA > depthB, let entry = a {
            guard body(entry) else { return false }
            a = entry.next
            depthA -= 1
        }
        while depthB > depthA, let entry = b {
            guard body(entry) else { return false }
            b = entry.next
            depthB -= 1
        }
        while a !== b, let x = a, let y = b {
            guard body(x), body(y) else { return false }
            a = x.next
            b = y.next
        }
        return true
    }
}

/// A write of `K`'s value.
final class EnvironmentEntryOf<K: EnvironmentKey>: EnvironmentEntry {
    let value: K.Value

    init(key: ObjectIdentifier, index: Int, stamp: UInt64, value: K.Value, next: EnvironmentEntry?) {
        self.value = value
        super.init(key: key, index: index, stamp: stamp, next: next)
    }

    @MainActor
    override func hasSameValue(as other: EnvironmentEntry) -> Bool {
        _areEquivalent(value, unsafeDowncast(other, to: EnvironmentEntryOf<K>.self).value)
    }

    override func relinked(onto next: EnvironmentEntry?) -> EnvironmentEntry {
        EnvironmentEntryOf(key: key, index: index, stamp: stamp, value: value, next: next)
    }

    override func defaulted(onto next: EnvironmentEntry?) -> EnvironmentEntry {
        EnvironmentEntryOf(
            key: key, index: index, stamp: EnvironmentValues.takeStamp(), value: K.defaultValue, next: next
        )
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

    private let keyPath: KeyPath<EnvironmentValues, Value>

    /// The value, once the view is bound.
    private var value: Value?

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        guard let value else {
            preconditionFailure(
                "@Environment read before the view was built — environment values "
                + "are only available inside `body`."
            )
        }
        return value
    }

    public mutating func _bind(to context: BindingContext) {
        value = context.environment[keyPath: keyPath]
    }
}

// MARK: - Built-in keys

private struct ForegroundStyleKey: EnvironmentKey {
    static let defaultValue = AnyShapeStyle(HierarchicalShapeStyle.primary)
}

private struct FontKey: EnvironmentKey {
    static let defaultValue = Font.body
}

private struct TintKey: EnvironmentKey {
    static let defaultValue = AnyShapeStyle(Color.blue)
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
    /// The style foreground content is drawn with: a shape used as a view,
    /// a `Text`, a control's label — `.foreground` where it is drawn.
    public var foregroundStyle: AnyShapeStyle {
        get { self[ForegroundStyleKey.self] }
        set { self[ForegroundStyleKey.self] = newValue }
    }

    public var font: Font {
        get { self[FontKey.self] }
        set { self[FontKey.self] = newValue }
    }

    /// The style controls are tinted with — `.tint` where it is drawn.
    public var tint: AnyShapeStyle {
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
