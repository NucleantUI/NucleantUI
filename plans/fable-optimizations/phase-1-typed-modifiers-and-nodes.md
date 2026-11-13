# Phase 1: typed modifiers and nodes

This phase answers the "Generics usage" part of [plan.md](plan.md).

## The pattern

A public type is generic, and the first thing its `makeNode` does is turn
the generic part into a closure, an existential or an `AnyHashable`. From
there on, every layer handles one erased type and has to find out at run
time what the compiler already knew:

- a string in a key, to tell `.padding` from `.frame`;
- `as?`, to ask a node whether it has a layout cache;
- a dictionary keyed by type, to find how two values compare.

Signs of the pattern in a review:

- a stored property of type `(…) -> any P`, or a closure whose only job is
  to call a method on a captured generic value;
- a `key:` or `kind:` value that exists only to distinguish cases that
  would be different types;
- `as? SomeInternalProtocol` on a value the framework created itself;
- a `[ObjectIdentifier: …]` table looked up on every call.

## 1.1 `_ModifierView`: one type for every modifier

**Today.** [LayoutModifiers.swift](../../Sources/NucleantUI/Modifiers/LayoutModifiers.swift):

```swift
public struct _ModifierView<Content: View>: View {
    var content: Content
    let makeContent: @MainActor (inout BuildContext) -> any NodeContent
    let modifyEnvironment: (@MainActor (inout EnvironmentValues) -> Void)?
    let key: AnyHashable?
}

// .frame(width:height:alignment:)
_ModifierView(content: self, key: ["frame", width, height, alignment] as [AnyHashable]) { _ in
    FrameContent(…)
}
```

The file comment gives the reason: "keeps the type explosion down".
`_ModifierView(` is constructed in 66 places across 27 files.

**What it costs**, per modifier, every time a `body` that uses it runs:

- a closure context holding the captured arguments;
- an array, plus one `AnyHashable` box per element. A `ShapeStyle` or a
  `Font` in the key is larger than the inline buffer, so it is copied to the
  heap;
- the node content as `any NodeContent`, boxed again when it is larger than
  three words (`FrameContent` and `PaddingContent` are);
- comparing two applications means comparing two `[AnyHashable]`, a dynamic
  cast per element.

And two structural costs:

- The name string is there because, as the comment says, "two different
  modifiers over the same content are the same type". The type system was
  given up and a string does its job.
- A modifier holding something not `Hashable` passes `key: nil` and is
  never equivalent. `.environment(_:_:)` does this for any value that is
  not `Hashable`, and gestures always do. That modifier is then rebuilt on
  every pass of its parent. What is under it is still compared, so the cost
  is one level, not the subtree.

**Do instead.** One small struct per modifier, and a view generic over it:

```swift
protocol PrimitiveModifier: ViewInput {
    associatedtype Content: NodeContent
    func makeContent(_ context: inout BuildContext) -> Content
    func modifyEnvironment(_ environment: inout EnvironmentValues)   // default: nothing
}

struct FrameModifier: PrimitiveModifier, Equatable {
    var width: Double?, height: Double?, alignment: Alignment
    func makeContent(_ context: inout BuildContext) -> FrameContent { … }
}

public struct _ModifierView<Content: View, Modifier: PrimitiveModifier>: View {
    var content: Content
    var modifier: Modifier
}
```

- No closure, no key, no existential while building.
- Equivalence is `_areEquivalent(modifier, other.modifier)`, resolved at
  compile time. A modifier of plain numbers compares by its bytes.
- A modifier that stores a closure (a gesture, `onAppear`) gets the closure
  comparison `@View` already generates for stored closures, so it stops
  being "never equivalent".
- `.environment(keyPath, value)` becomes a modifier holding the key path
  and the value, compared with `_areEquivalent`, with no `as? AnyHashable`.
- Each modifier is its own type with its own code, which also fits the rule
  that each SwiftUI modifier is implemented on its own.

**About the type explosion.** The nesting depth does not change:
`_ModifierView<_ModifierView<Text>>` becomes
`_ModifierView<_ModifierView<Text, PaddingModifier>, FrameModifier>`. Call
sites still see `some View`. What grows is the number of specializations of
`makeNode`, so compile time and binary size go up somewhat. That
specialization is the point: it is what makes the node content static.
Measure the build time of the largest example before and after the first
ten modifiers.

**Order.** `padding`, `frame`, `opacity`, `offset`, the environment
writers, then the rest. The old initializer can stay until the last
modifier has moved.

## 1.2 `ViewNode.content` is an existential

**Today.** [ViewNode.swift](../../Sources/NucleantUI/Layout/ViewNode.swift):
`let content: any NodeContent`.

- A content value larger than three words lives in a second heap block.
  `FrameContent`, `PaddingContent`, `TextContent` and `ShapeContent` all
  are, so those nodes cost two allocations.
- Every call goes through the witness table and can never be specialized
  or inlined into the node.
- Extra abilities are found by casting: `content as? LayoutCacheOwner`
  (once per ancestor in `invalidateMeasurementsUpwards`),
  `content as? LayoutSpacingSource` (per subview, per spacing question, in
  every stack layout run), `as? GridRowContent`, `as? LazyGapContent`.

**Do instead.** A base class with a generic subclass:

```swift
class ViewNode { /* frame, children, caches, overridable layout methods */ }

final class ContentNode<C: NodeContent>: ViewNode {
    let content: C          // stored inline in the object
    var cache: C.Cache      // see phase 3
}
```

- One allocation per node.
- A layout call is one class method call into code specialized for `C`.
- `subviewsChanged()` and `spacing` become requirements of `NodeContent`
  with empty defaults, so no cast is needed.

`AnyLayoutStorage` with `LayoutStorage<L>` and `RecordedView` with
`RecordedViewOf<V>` already use this shape in the tree.

## 1.3 `NodeContent` asks every node seventeen questions

**Today.** `NodeContent` has seventeen properties that nearly every content
type answers with the default: `hitTarget`, `dragSource`, `dropTarget`,
`contextMenuSource`, `hoverTarget`, `textureInput`, `focusTarget`,
`gestureAttachment`, `allowsHitTesting`, `hitShape`, `focusBinding`,
`keyPressHandler`, `transitionTrait`, `animatesSize`, `isParked`,
`clipsChildren`, `isTransparent`. Every tree walk asks several of them of
every node, through the existential.

**Do instead.** A trait set per node, filled once when the node is made:

```swift
struct NodeTraits: OptionSet {   // UInt32
    static let hitTarget, hover, dragSource, dropTarget, contextMenu,
               focusTarget, gesture, textureInput, clipsChildren,
               transparent, parked, blocksHitTesting, hitShape …
}
```

The node stores its own traits and the union of its subtree's. A walk tests
a bit before it calls anything. [Phase 7](phase-7-input.md) uses the
subtree union to skip whole subtrees.

## 1.4 Finding the builtin behind a view

**Today.** `buildNode` in
[ViewNode.swift](../../Sources/NucleantUI/Layout/ViewNode.swift) asks
`view as? BuiltinView` once per type, keeps the answer in
`builtinMakers: [ObjectIdentifier: BuiltinMaker?]`, and calls the builtin
through a closure taking an `UnsafeRawPointer`. `BuildContext.showing` does
the same for animation with `_AnimatableTypes.inanimate`,
`view is any Shape` and `view as? any Animatable`. That is two table
lookups for every view built, and a raw pointer round trip for every
builtin.

**Do instead.** Make it a requirement of `View`:

```swift
public protocol View: ViewInput {
    …
    static func _makeNode(_ view: Self, _ context: inout BuildContext) -> _ViewNodeRef
    static var _buildsUnderLazyCursor: Bool { get }
}

extension View {   // the default: a view with a body
    public static func _makeNode(_ view: Self, _ context: inout BuildContext) -> _ViewNodeRef {
        /* run body inside the observation scope, build its result at child 0 */
    }
}
```

Each builtin implements `_makeNode` itself. `buildNode<V>` calls
`V._makeNode`, which the compiler resolves once `buildNode` is specialized.
The dictionary, the pointer closure and the `BuiltinView` cast go away. A
second default constrained to `Self: Animatable` can replace the
`showing(_:)` lookup; check in a small test that the constrained default is
the one chosen as the witness for a `@View` type.

The requirement has to be public, since `View` is. `ViewNode` then needs a
public opaque wrapper, or becomes public with an underscore.

## 1.5 A shape becomes a closure

**Today.** `_ShapeView<S: Shape>` is generic. Its `makeNode` in
[Shape.swift](../../Sources/NucleantUI/Views/Shapes/Shape.swift) builds
`ShapeContent(makePath: { rect in drawn().path(in: rect) }, …)`, and
`drawn` is itself a closure from `BuildContext.drawnShape`. The comment on
`ShapeContent` says: "The shape itself is a closure so every concrete
`Shape` reduces to one node kind."

So the node cannot compare two shapes, cannot keep a path from one pass to
the next, and cannot know that it holds a plain rectangle.

**Do instead.** `ShapeContent<S: Shape>` holding the shape value, and the
animation state object while it is moving. This is what makes the path
cache (4.3) and direct drawing of rectangles and ellipses (5.2) possible.

## 1.6 `AnyView`

**Today.** [PrimitiveViews.swift](../../Sources/NucleantUI/Core/PrimitiveViews.swift):
`AnyView` stores two closures, `makeErasedNode` and `lowerMenuItems`, each
holding its own copy of the view. `AnyView._isEquivalent` always answers
false.

`ModifiedContent.body` wraps its content in `AnyView` every time it runs,
because `_ViewModifier_Content<Modifier>` cannot be generic over the
content. Every custom `ViewModifier` therefore allocates two closures per
`body` run and puts a level that is never equivalent into the tree.

**Do instead.** One storage object, the way `RecordedView` does it:

```swift
class AnyViewStorage { /* makeNode, lowerMenuItems, isEquivalent(to:) */ }
final class AnyViewStorageOf<V: View>: AnyViewStorage { let view: V }
```

One allocation, and `AnyView._isEquivalent` can give the real answer: the
same stored type, and equivalent values of it.

**Not audited.** `AnyView` appears 20 times in `Form.swift`, 11 in
`ContextMenu.swift`, 9 in `ListContent.swift`, 8 each in `Picker.swift` and
`Navigation.swift`. I did not read those files. Each use should be checked
against the rule in CLAUDE.md: a generic parameter or a parameter pack
first, `AnyView` only for a stored closure that different call sites fill
with different view types.

## 1.7 `OpaqueValue` and `OpaqueReference`

**Today.** [Animatable.swift](../../Sources/NucleantUI/Animation/Animatable.swift).
`OpaqueValue` is an object holding a type id, a separately allocated block
for the value and a destroy closure. `OpaqueReference` is an object holding
an unmanaged pointer to another object and a release closure. Storing one
value costs two allocations and a closure.

They are used in per-node `preferenceCache`, in `LayoutValues`, in four
tables of `EffectQueue`, and in `AnimationStore.observed` and
`animatableData`. Every `.onChange` whose value changed allocates a new one.

**Do instead.**

```swift
class AnyBox {}
final class Box<T>: AnyBox { var value: T }
```

One allocation, and reading is a class cast. For `animatableData`, give
`AnimatableDataState<Data>` a non-generic base class and store that; no
wrapper object is needed around something that is already an object.
[Phase 2](phase-2-view-positions.md) removes several of these tables
altogether.

## 1.8 Comparing through `Any`

**Today.** [Equivalence.swift](../../Sources/NucleantUI/Core/Equivalence.swift):
`_dynamicallyEquivalent(_ a: Any, _ b: Any)` boxes both values, reads
`type(of:)`, looks the type up in `comparators`, calls a closure, and that
closure casts both values back with `as!`.

It is called where the type is known statically:

- `StateStorage<Value>.set`, on every state write;
- `EnvironmentValues.hasSameValue`, per key compared;
- the unconstrained `_areEquivalent<T>`, which is what a closure capture of
  generic type goes through.

**Do instead.** One comparison per type, taking pointers:

```swift
typealias EquivalenceWitness = @MainActor (UnsafeRawPointer, UnsafeRawPointer) -> Bool
```

It is chosen once per type by the rules that exist today: `ViewInput`,
then object identity, then `Equatable`, then bytes for plain data, else not
equivalent. `StateStorage<Value>` takes its witness when it is created. An
environment entry keeps the witness of its key's value. A closure capture
layout keeps one per capture, which it nearly does already. No value is
boxed in `Any` to be compared.

## 1.9 `[Double]` for built-in animated values

**Today.** [AnimationStore.swift](../../Sources/NucleantUI/Animation/AnimationStore.swift):
`AnimatedVector` holds `target: [Double]`, and `current()` returns a
`[Double]`. `.opacity(0.5)` builds the array `[opacity]` on every build and
reads `current()[0]` on every placement. A color is an array of eight.

The generic `AnimatableDataState<Data: VectorArithmetic>` sits next to it
and needs no arrays.

**Do instead.** The built-in modifiers use the generic state:
`AnimatableDataState<Double>` for opacity and rotation,
`AnimatablePair<Double, Double>` for offset and scale, and a fixed
eight-lane value for a light and dark color pair.

## 1.10 Enums inside one content type

Small, listed because it is the same pattern: `TransformContent.Kind`
(`.rotation` or `.scale`), `StackContent.axis` (read through
`subscript(axis:)` in every loop), `DecorationContent.Order`,
`SpacerContent.axis`. With 1.1, rotation and scale are two modifier types
with two content types, and each `place` has no switch. Do not do these on
their own; they fall out of 1.1.

## 1.11 `ShapeStyle` is a closed enum

**Today.** [Gradient.swift](../../Sources/NucleantUI/Graphics/Gradient.swift):
`enum ShapeStyle` with four cases. The comment says it is closed because
the renderer had to switch on it for another backend's gradients. Skia
draws everything now, so that reason is gone.

SwiftUI's public API has `protocol ShapeStyle` with `resolve(in:)`, and
`fill<S: ShapeStyle>`. A closed enum cannot express a style a user defines,
or one that resolves from the environment such as `.tint`. It is also the
pattern of this phase in its plainest form: one type with every case
inside, and a `switch` in each function that touches it
(`DrawContext.resolve`, `flatColor`, `isClear`, `opacity`,
`animatableVector`, the renderer's `apply`).

**Decided: `ShapeStyle` becomes a protocol.**

```swift
public protocol ShapeStyle: Sendable {
    associatedtype Resolved: ShapeStyle = Never
    func resolve(in environment: EnvironmentValues) -> Resolved
}
```

- **Concrete styles**, each its own type, as in SwiftUI's API: `Color`,
  `LinearGradient`, `RadialGradient`, `ForegroundStyle`, `BackgroundStyle`,
  `TintShapeStyle`, `HierarchicalShapeStyle` (`.primary`, `.secondary`,
  `.tertiary`), and `AnyShapeStyle`. The light and dark pair that
  `.dynamic(light:dark:)` makes today becomes a concrete style of
  NucleantUI's own. `Color` stays four stored floats; the scheme stays in
  the style.
- **Generic API**: `fill<S: ShapeStyle>`, `stroke<S: ShapeStyle>`,
  `foregroundStyle<S: ShapeStyle>`, `background<S: ShapeStyle>`,
  `Text.foregroundStyle<S: ShapeStyle>`, and `_ShapeView<S: Shape, Style: ShapeStyle>`.
  The fill's type is then known where the node is built, and comparing two
  fills is resolved at compile time.
- **One internal resolved paint** that the display list holds and the
  renderer switches on: a flat color, a linear gradient, a radial gradient.
  That set is closed because the renderer's is, and it is not public.
- **The environment** stores the foreground style and the tint as
  `AnyShapeStyle`. This is a real erasure boundary: one stored value that
  different call sites fill with different concrete types. Its storage is a
  base class with a generic subclass, as in 1.6, compared with the witness
  of 1.8.

**A point to settle while doing it: when a style is resolved.** Today a
light and dark pair is resolved when it is drawn, from
`DrawContext.colorScheme`, and `EnvironmentContent` exists to carry the
scheme down the draw context. `resolve(in:)` takes the environment, which
exists when the view is built. Resolving at build makes the color scheme an
environment value a view reads like any other, tracked by the environment
reads that already exist: a scheme change then rebuilds exactly the views
that resolved a style from it, and the draw context no longer carries the
scheme.

**Size of the change.** The enum's cases are written out in about 80 places
in the framework, 40 in the tests and 230 across the examples.

- Call sites written with a leading dot, `.linearGradient(…)`,
  `.radialGradient(…)` and `.dynamic(light:dark:)`, keep compiling when
  those become static functions on `ShapeStyle where Self == LinearGradient`
  and so on, each returning its concrete style.
- Call sites that spell out `ShapeStyle.dynamic(…)` or
  `ShapeStyle.color(…)` name the concrete type instead.
- `.color(x)` is not SwiftUI's spelling. Those sites pass `x`.

## Order inside this phase

1. 1.8, the comparison witness. Small, and the rest uses it.
2. 1.1, modifiers, a few at a time.
3. 1.2 and 1.3, the generic node and the trait set.
4. 1.5, shapes.
5. 1.6 and 1.7, the storage classes.
6. 1.11, `ShapeStyle` as a protocol. After 1.1 and 1.5, which give it the
   typed modifiers and the generic shape node to plug into. The examples
   and the tests change with it, in the same step.
7. 1.4, `_makeNode`, last: it changes the public `View` protocol.
8. 1.9 with whichever modifier it belongs to.

## Checking

- The build part of the pass time in `NUCLEANT_SWIFTUI_TRACE_PERF=1`.
- Allocations per pass in Instruments, on an example with many modifiers.
- The existing tests on reuse must still pass: a view under a typed
  modifier is kept when its inputs are equivalent and rebuilt when they are
  not.
