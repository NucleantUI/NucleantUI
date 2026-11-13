# Phase 6: environment storage, state writes, bindings

Independent items. Each can be done on its own unless it says otherwise.

## 6.1 Environment values are stored as `Any`

**Today.** [Environment.swift](../../Sources/NucleantUI/State/Environment.swift):

```swift
struct Entry { var value: Any; var stamp: UInt64 }
private var storage: [ObjectIdentifier: Entry] = [:]
```

- **A read** hashes the key, then casts with `as? K.Value`. That is a
  dynamic cast on every read of every environment value. A value larger
  than three words (`ShapeStyle`, `Font`) also sits in its own heap block.
- **A write** copies the whole dictionary. The parent's context still holds
  it, so `.font(…)` followed by `.foregroundStyle(…)` copies every key
  twice.
- **A comparison** goes through `_dynamicallyEquivalent(Any, Any)` (1.8).

**Do instead.** Typed entries in a linked chain, newest first:

```swift
class EnvironmentEntry {                 // base, not generic
    let key: ObjectIdentifier
    let stamp: UInt64
    let next: EnvironmentEntry?
    func hasSameValue(as other: EnvironmentEntry) -> Bool   // overridden
}
final class EnvironmentEntryOf<K: EnvironmentKey>: EnvironmentEntry {
    let value: K.Value
}
```

- A write allocates one entry in front of the chain. Nothing is copied,
  and the environment above is untouched because the chain is shared.
- A read walks until the key matches and downcasts to the typed entry. No
  dynamic cast, no box.
- A comparison is a method on the typed entry, using the witness of 1.8.
- Chains are as long as the number of writes above a view. If that grows,
  each entry can carry a bit mask of the keys at or below it, so asking for
  a key nobody set (the usual case: the default) ends at the first entry.

## 6.2 Environment reads are kept in `Set`s

**Today.** [EnvironmentReads.swift](../../Sources/NucleantUI/State/EnvironmentReads.swift)
keeps a stack of `Set<ObjectIdentifier>`. Closing a view's frame unions its
set into its parent's. One `Text` reading its font adds a key to a set at
every level up to the root of the build, and each record stores its own
copy.

**Do instead.** Give each key a small index the first time it is used, and
keep reads as a fixed-width bit mask, 128 or 256 bits. Noting a read sets a
bit, closing a frame is an OR, a record stores a few words, and "did any
key that changed matter to this view" is an AND against the mask of changed
keys. An app with more keys than bits needs an overflow rule: one bit that
means "compare the slow way".

## 6.3 Built-in modifiers write through a key path

**Today.** `.font`, `.foregroundStyle`, `.tint`, `.disabled` and others all
forward to `environment(_:_:)`, which stores a closure doing
`$0[keyPath: keyPath] = value`. Writing through a `WritableKeyPath` is much
slower than calling the setter. `Environment<Value>` reads the same way,
through a closure made in its initializer.

**Do instead.** With typed modifiers (1.1), each of these is its own
modifier that sets its own key directly. Only the public
`environment(_:_:)` keeps the key path, because its API takes one.

## 6.4 Property wrappers allocate a holder per view value

**Today.**

- `_StateProperty` creates a `Holder` object in its initializer
  ([State.swift](../../Sources/NucleantUI/State/State.swift)).
- `Environment` creates a `Holder` and a read closure.

A view value is constructed every time its parent's `body` runs, including
when the builder then finds it equivalent to the one standing and throws it
away. So each `@State` and `@Environment` allocates on every parent pass.

The holder exists because binding is done on an immutable copy of the view,
so the wrapper needs something shared to write into.

**Do instead.** Bind into the copy the builder owns. The builder already
keeps the view value (`RecordedViewOf<V>`). Make the generated
`_bindDynamicProperties` mutating, run it on that copy, and let each
wrapper store its storage reference, or its environment value, in a plain
field. `body` runs on the bound copy. Constructing a view then allocates
nothing for its wrappers.

To check before starting: every place that reads a wrapper outside `body`,
and the `pending` value `_StateProperty` keeps for a write before binding.

## 6.5 A write through a binding copies and compares the whole value

**Today.** For `$tracks[3].level = x`, the setter made by
`Binding.subscript(dynamicMember:)` in
[Binding.swift](../../Sources/NucleantUI/State/Binding.swift) does:

1. `var copy = rawGet(nil)`: reads the whole root value;
2. `copy[keyPath: keyPath] = newValue`: the storage still holds the array,
   so this copies the whole array;
3. `rawSet(copy, chain)`, which reaches `StateStorage.set`, which compares
   the old and the new root values in full before assigning.

One tick of a slider in row 3 copies every track and compares every track.

Each level of projection also wraps two more closures around the previous
level's.

**Do instead.**

- A binding projected from state is the storage plus one composed
  `WritableKeyPath` (`appending(path:)`), not closures inside closures.
- The storage gets a write that takes that key path and the new leaf. It
  compares the leaf only, and writes in place with
  `value[keyPath: path] = newLeaf`. The storage is the only holder at that
  moment, so nothing is copied.

How much this matters depends on the app. CLAUDE.md says a model that
changes should be an `@Observable` class, and writes to one do not come
through here. It is the path a struct or an array in `@State` takes.

## 6.6 A write visits every reader

**Today.** `StateStorage.set` loops over all of `readers` and, for each,
tests every chain it read with `starts(with:)` in both directions, which
compares key paths one by one. A list of 1,000 rows, each reading its own
element through a binding, has 1,000 readers. A write to one element tests
all of them.

**Do instead.** Group the readers by the first key path of their chain,
with whole-value readers in a group of their own. A write to `[3].level`
then looks at the group for `\.[3]` and at the whole-value group.

## 6.7 Reads are filed in a dictionary keyed by path (standalone)

**Today.** [StateStore.swift](../../Sources/NucleantUI/State/StateStore.swift):
`DependencyTracker.reads` is `[[Int]: [ObjectIdentifier: any AnyStateStorage]]`.
`buildNode` asks `hasReads(for: path)` and `takeReads(for: path)` for every
view it builds. Both hash the path, whether or not the view read anything.

**Do instead.** The tracker already has a stack with one entry per view
being built. Keep that view's reads in its stack entry. `hasReads` and
`takeReads` then read the top of the stack.

## Order

1. 6.7.
2. 6.1, then 6.2.
3. 6.5 and 6.6.
4. 6.3 with phase 1.
5. 6.4, after checking what reads wrappers outside `body`.

## Checking

- The build part of the pass time on an example with many `Text`s under
  several `.font` and `.foregroundStyle` modifiers (6.1 to 6.3).
- A list of a few thousand rows bound into an array in `@State`, one row's
  control dragged (6.5, 6.6).
- Allocations per pass in Instruments (6.4).
- The environment tests: a view is rebuilt when a value it read changes
  and kept when a value it did not read changes.
