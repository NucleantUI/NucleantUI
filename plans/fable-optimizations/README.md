# Fable review: what could be done better

A read-through of `Sources/NucleantUI` answering the two questions in
[plan.md](plan.md): where a generic type is erased too early, and where the
math or the structure costs more than it has to.

What is done so far, finding by finding: [progress.md](progress.md).

## How to read this

- Every finding comes from reading the code; the review itself measured
  nothing. The order is my judgment of where the cost is, and each phase
  says how to check it before and after. What was done has been measured
  since: see [Measuring](#measuring).
- About 10,000 of the 50,000 lines were read in full: `Core`, `Layout`,
  `State`, most of `Render`, `ViewHost`, the modifier and shape plumbing, and
  the animation value storage. The rest was only searched for patterns.
  **Not read:** the big views (`List`, `Table`, `Form`, `Navigation`,
  `TextField`, `Picker`), `ShaderSlotRegistry`, `HostingWindow`,
  `RenderNodeManager`, the transition types and most of `GestureArena`.
  Findings about those say so.
- Each phase file lists findings as: what the code does today, what it
  costs, what to do instead. Sketches of code show a shape, not a final API.

## The short version

The build step is already scoped well: a state write rebuilds one subtree,
equivalent views are kept, and environment reads are tracked per view. Three
things undo part of that work.

1. **Modifiers and nodes are erased the moment they are built.** Every
   modifier is one type, `_ModifierView<Content>`, holding a closure that
   returns `any NodeContent` and an `[AnyHashable]` key to tell modifiers
   apart. Shapes turn into a `(Rect) -> Path` closure. Nodes hold their
   content as an existential and are asked what they can do with `as?`.
   This is the pattern plan.md describes, and it is at the center of the
   framework. See [phase 1](phase-1-typed-modifiers-and-nodes.md).
2. **A view's identity is an `[Int]` array.** About twenty dictionaries and
   sets in eight subsystems are keyed by it. Each one hashes the array on
   every use and needs its own cleanup when views leave. See
   [phase 2](phase-2-view-positions.md).
3. **Everything after the build runs over the whole tree.** Each pass places
   every node, emits every draw command again, and compares the lists value
   by value to find out that most of them did not change. One knob animating
   pays for the whole window on every frame. Hit testing walks every node
   for every pointer event, several times. See
   [phase 4](phase-4-placement-and-display-list.md) and
   [phase 7](phase-7-input.md).

## Phases

| Phase | Topic | Why it is in this position | Size |
|---|---|---|---|
| [1](phase-1-typed-modifiers-and-nodes.md) | Typed modifiers and nodes | The erasure plan.md asks about. Later phases build on it: a typed node can hold its own layout cache and path cache. | Large, but one modifier at a time |
| [2](phase-2-view-positions.md) | A position object instead of `[Int]` paths | Removes hashing and cleanup code from every subsystem, and gives each view a place to cache what is looked up or worked out again today. | Large |
| [3](phase-3-layout.md) | Layout caches and stack math | Self-contained and low risk. | Medium |
| [4](phase-4-placement-and-display-list.md) | Placing and drawing only what changed | Probably the largest gain per frame, and the most work. | Large |
| [5](phase-5-skia-drawing-and-text.md) | Skia draw calls and text | Mostly local to the renderer. Text depends on moving measuring to Skia. | Medium |
| [6](phase-6-state-environment-bindings.md) | Environment storage, state writes, bindings | Several small independent items. | Medium |
| [7](phase-7-input.md) | Hit testing and focus lookups | Small once phase 1 gives nodes a trait mask. | Small |

Phases 3, 5, 6 and 7 each contain items that can be done on their own today.
They are marked **standalone** in the files.

## Where plan.md's two questions are answered

| Question in plan.md | Where |
|---|---|
| Bad type erasure, one type with all cases inside | [Phase 1](phase-1-typed-modifiers-and-nodes.md), plus 6.1 (environment values as `Any`) and 6.4 (holder objects) |
| Bad math patterns | [Phase 3](phase-3-layout.md) (stack probes, caches, transforms), 4.2, 4.5, 4.7 and 4.9, 5.2 to 5.5, 6.5 and 6.6 |
| General structure | [Phase 2](phase-2-view-positions.md), [phase 4](phase-4-placement-and-display-list.md), [phase 7](phase-7-input.md) |

## Small fixes that are certain

These are a few lines each and do not depend on any phase.

| Fix | Where | Finding |
|---|---|---|
| Return the style unchanged when opacity is 1, instead of rebuilding every gradient | `DrawContext.resolve(_:)` | 4.9 |
| Compute a rect under a transform without three temporary arrays | `Rect.applying(_:)` | 3.9 |
| Two stored bytes instead of a dictionary for a node's two flexibilities | `ViewNode.flexibilities` | 3.1 |
| Find a node by path through `RebuildRecords` instead of walking the tree | `focusTarget(at:)`, `focusNode(at:)`, `gestureAttachment(at:)` | 7.2 |
| Forget a replaced view's effects without filtering five dictionaries | `EffectQueue.forget(paths:)` | 2.3 |
| Keep a view's state reads on the tracker's stack frame instead of a dictionary keyed by path | `DependencyTracker` | 6.7 |

## Measuring

- `Scripts/bench_animations.py` before and after each phase, several runs,
  as for any larger framework change.
- `NUCLEANT_SWIFTUI_TRACE_PERF=1` prints, per pass, the time and the counts
  of nodes built, nodes reused, sizes measured and texts measured. Phases 3
  and 4 should move `measured` and the pass time; phase 1 should move the
  build time.
- Instruments on an example app, Allocations and Time Profiler, from
  outside. Phases 1, 2 and 6 are mostly about allocations per view built,
  which the trace does not count.

What was measured, step by step ([progress.md](progress.md) has every
metric):

<!-- measurements:summary -->
CPU per pass, mean of the launches (debug builds); in **bold** where the
launches before and after don't overlap. Written by
`Scripts/bench_animations.py tables` from [measurements.json](measurements.json).

| Measured | Before → after | Date | Load | `bookmarks-layout` | `bookmarks-scroll` | `reader-scroll` | `flashcards-card` |
|---|---|---|---|---|---|---|---|
| Before phase 2: phases 1 (but 1.4) and 3, 2.3, 2.7's `ForEach` comparison, 4.1 steps 1–2, 4.2–4.9, 5.1–5.3, 6 (6.4 in part), 7.1 steps 1–2, 7.2–7.5 | `4adf040` → `f6c6802` | 2026-11-14 | not recorded | 73.5 → 33 ms (**−55%**) |  |  | 3.33 → 2.95 ms (**−11%**) |
| 2.8 steps 5 and 6: `ForEach` rows by id, a scope per row, a modifier's environment write kept | `10a442a` → `a266d81` | 2026-11-14 | about 3–7 | 34.5 → 34.5 ms (+0%) |  |  | 2.91 → 2.72 ms (**−7%**) |
| 2.8 step 7: no paths in the build | `a266d81` → `fc626e4` | 2026-11-14 | about 12 | 34.8 → 32.7 ms (−6%) |  |  | 2.9 → 2.88 ms (**−1%**) |
| 4.1 step 3 (moved subtrees drawn moved), text measured and fonts read with Skia, 5.4–5.6 (text blobs, a text's face resolved once); 7.1 step 3 tried and taken out | `258f4e9` → `8f15bbc` | 2026-11-14 | 3.4–29.9 | 34.3 → 33.2 ms (**−3%**) | 13 → 13.6 ms (**+5%**) | 4.88 → 4.33 ms (**−11%**) |  |
<!-- /measurements:summary -->

## Every cache in this plan

What is kept so it is not looked up or computed again, where it lives, and
what drops it.

| What is kept | Where | Dropped when | Finding |
|---|---|---|---|
| Sizes for the last three or four proposals | the node, inline | the node is replaced, or a child's size changed | 3.1, 3.6 |
| A stack's last result: sizes, child proposals, total | the stack's node; `HStackLayout`'s own `Cache` | same | 3.3, 3.4 |
| Each stack child's shortest and longest length, per cross-axis proposal | the same cache | same | 3.2 |
| The flattened layout children | the node | its children change, a removal starts or ends | 3.8 |
| A shape's path for its size | the shape's node | the node is replaced, or the size changes | 4.3 |
| The Skia path for it | with the path | with the path | 5.2 |
| A command's paint bounds | the command | never, it is computed once | 4.7 |
| A boundary's commands and their version | the boundary | its subtree is marked for placement | 4.1 |
| A text's layout and its lines | the text's node | the node is replaced | 4.8 |
| The glyphs and positions of each laid-out line | the text layout entry | with the layout | 5.4, 5.5 |
| Gradient shaders and dash effects | the renderer | a render did not use them | 5.3 |
| A font's face index | resolved when `Text` builds | never | 5.6 |
| How two values of a type compare | per type; each state slot and environment entry takes it once | never | 1.8 |
| The traits found anywhere in a subtree | the node | a child is replaced | 1.3, 7.1 |
| A transform's kind, and its inverse | the transform; the node | the node is placed again | 3.9, 7.4 |
| A view's state slots, effects, animated values, render image | its position | another view takes the position, or the view leaves | 2.6 |
| The environment a modifier produced | its position | what came in or what it writes differs | 2.6 |
| A `ForEach`'s rows by id, and each row's element | the `ForEach`'s position and the row's | the row leaves | 2.7 |
| Which keys are set at or below an environment entry | the entry | never, an entry does not change | 6.1 |
| Which environment keys a view's subtree read, as bits | its record | the view is rebuilt | 6.2 |

## Decided

- **`ShapeStyle` becomes a protocol** (1.11), with generic `fill`,
  `stroke` and `foregroundStyle`, and one internal resolved paint for the
  display list.
- **`HStack` and `HStackLayout` stay two implementations** (3.4), as two
  SwiftUI API types. The stack caches of phase 3 are applied to each
  separately.
- **Phase 2 goes ahead with caching as a goal.** 2.5 gives the design: one
  trie of positions and a number per rebuild. 2.6 lists what each position
  holds.
