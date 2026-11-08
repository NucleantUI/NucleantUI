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
final class EnvironmentReads {

    /// The `EnvironmentValues` subscript is not isolated, and the reads it
    /// notes come from building views, which is on the main actor.
    nonisolated(unsafe) static let shared = EnvironmentReads()

    private init() {}

    private var frames: [Set<ObjectIdentifier>] = []

    /// A view begins building.
    func begin() {
        frames.append([])
    }

    /// The view built: what it and everything under it read, added to the
    /// view around it as well.
    func end() -> Set<ObjectIdentifier> {
        let keys = frames.removeLast()
        if !keys.isEmpty, !frames.isEmpty {
            frames[frames.count - 1].formUnion(keys)
        }
        return keys
    }

    /// `key` was read by the view being built.
    func note(_ key: ObjectIdentifier) {
        guard !frames.isEmpty else { return }
        frames[frames.count - 1].insert(key)
    }

    /// A standing subtree that read `keys` is kept inside the view being
    /// built.
    func add(_ keys: Set<ObjectIdentifier>) {
        guard !keys.isEmpty, !frames.isEmpty else { return }
        frames[frames.count - 1].formUnion(keys)
    }
}
