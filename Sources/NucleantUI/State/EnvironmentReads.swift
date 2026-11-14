//
//  EnvironmentReads.swift
//  NucleantUI
//
//  Which environment values each subtree read while it was built.
//
//  A view standing under a parent that re-ran is kept only if the values it
//  was built with are still the ones it would get. Asking that of the whole
//  environment rebuilds every view below any change — a re-applied closure,
//  a tint nobody in the subtree uses. So each read is noted, through the
//  `EnvironmentValues` subscript, and the builder keeps with each view the
//  keys read anywhere in its subtree: by its own `@Environment`s, by the
//  builtins it made (a `Text` reading its font), by everything below. Only
//  those are compared when the view is next asked to stand.
//

/// Notes environment reads against the views being built, innermost last.
///
/// `buildNode` opens a frame for each view it builds and closes it once the
/// view is built; closing hands back the keys read in that view's subtree
/// and adds them to the frame of the view around it. A reused view adds
/// what its subtree read when it was built. A read with no frame open — the
/// host, a window reading its own environment — is nobody's.
///
/// The keys are kept as bits (`EnvironmentKeySet`): each key gets a number
/// the first time it is read or written, so noting a read sets a bit,
/// closing a frame is an OR, and a view's record holds two words. An
/// environment's entries carry the same bits, for the keys written in them.
final class EnvironmentReads {

    /// The `EnvironmentValues` subscript is not isolated, and the reads it
    /// notes come from building views, which is on the main actor.
    nonisolated(unsafe) static let shared = EnvironmentReads()

    private init() {}

    private var frames: [EnvironmentKeySet] = []

    /// Each key's number, in the order keys were first read; the keys
    /// themselves by number, and those past the bits a set has, which share
    /// its last.
    private var indices: [ObjectIdentifier: Int] = [:]
    private var keys: [ObjectIdentifier] = []
    private var overflowKeys: [ObjectIdentifier] = []

    /// A view begins building.
    func begin() {
        frames.append(EnvironmentKeySet())
    }

    /// The view built: what it and everything under it read, added to the
    /// view around it as well.
    func end() -> EnvironmentKeySet {
        let keys = frames.removeLast()
        if !keys.isEmpty, !frames.isEmpty {
            frames[frames.count - 1].formUnion(keys)
        }
        return keys
    }

    /// `key` was read, by the view being built if there is one; its number.
    func noteRead(_ key: ObjectIdentifier) -> Int {
        let index = index(of: key)
        if !frames.isEmpty {
            frames[frames.count - 1].insert(index)
        }
        return index
    }

    /// A standing subtree that read `keys` is kept inside the view being
    /// built.
    func add(_ keys: EnvironmentKeySet) {
        guard !keys.isEmpty, !frames.isEmpty else { return }
        frames[frames.count - 1].formUnion(keys)
    }

    /// `key`'s number, given it the first time it is asked for — read or
    /// written.
    func index(of key: ObjectIdentifier) -> Int {
        if let known = indices[key] { return known }
        let index: Int
        if keys.count < EnvironmentKeySet.overflowBit {
            keys.append(key)
            index = keys.count - 1
        } else {
            overflowKeys.append(key)
            index = EnvironmentKeySet.overflowBit
        }
        indices[key] = index
        return index
    }

    /// Whether `body` holds for every key in `set` — for the last bit, for
    /// every key it stands for. Stops at the first that doesn't.
    func allKeys(in set: EnvironmentKeySet, satisfy body: (ObjectIdentifier) -> Bool) -> Bool {
        set.allIndices { index in
            guard index == EnvironmentKeySet.overflowBit else { return body(keys[index]) }
            return overflowKeys.allSatisfy(body)
        }
    }
}

/// Environment keys, as bits by the number `EnvironmentReads` gave each: two
/// words for the first 127 keys read, and a last bit that stands for every
/// key after them.
struct EnvironmentKeySet: Equatable, Sendable {
    private var low: UInt64 = 0
    private var high: UInt64 = 0

    /// The bit the keys past the others share.
    static let overflowBit = 127

    var isEmpty: Bool { low == 0 && high == 0 }

    @inline(__always)
    func contains(_ index: Int) -> Bool {
        index < 64 ? low & (1 << UInt64(index)) != 0 : high & (1 << UInt64(index - 64)) != 0
    }

    mutating func insert(_ index: Int) {
        if index < 64 {
            low |= 1 << UInt64(index)
        } else {
            high |= 1 << UInt64(index - 64)
        }
    }

    mutating func formUnion(_ other: EnvironmentKeySet) {
        low |= other.low
        high |= other.high
    }

    func isSubset(of other: EnvironmentKeySet) -> Bool {
        low & ~other.low == 0 && high & ~other.high == 0
    }

    /// Whether `body` holds for the number of every bit set, lowest first;
    /// stops at the first that doesn't.
    func allIndices(_ body: (Int) -> Bool) -> Bool {
        var bits = low
        while bits != 0 {
            guard body(bits.trailingZeroBitCount) else { return false }
            bits &= bits - 1
        }
        bits = high
        while bits != 0 {
            guard body(64 + bits.trailingZeroBitCount) else { return false }
            bits &= bits - 1
        }
        return true
    }
}
