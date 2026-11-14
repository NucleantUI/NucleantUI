# Progress

What of [the review](README.md) is done, on the `optimizations` branch.
Each finding links its phase file; the hash is the commit that did it.

- [x] done
- [~] partly done — the note says what is left
- [ ] not started

Last updated after `a0f05ce`.

## Small fixes that are certain

- [x] Style unchanged at opacity 1, no gradient rebuilt (4.9) — `d350522`
- [x] `Rect.applying(_:)` without temporary arrays (3.9) — `d350522`
- [x] A node's two flexibilities as two stored values (3.1) — `d350522`
- [x] Focus and gesture targets found through `RebuildRecords` (7.2) — `d350522`
- [x] `EffectQueue.forget(paths:)` without filtering every table (2.3) — `d350522`
- [x] State reads kept on the tracker's stack frame (6.7) — `d350522`

## [Phase 1](phase-1-typed-modifiers-and-nodes.md): typed modifiers and nodes

- [x] **1.1** One type per modifier, compared by its values — `d1e038c`
- [x] **1.2** `ContentNode<C>` holds its content by type — `d24813b`
- [x] **1.3** Traits read once per node, unioned over the subtree — `d24813b`
- [ ] **1.4** Finding the builtin behind a view (`_makeNode`). Last in the
  plan's order: it changes the public `View` protocol.
- [x] **1.5** `ShapeContent<S>` holds the shape — `d6af0fd`
- [x] **1.6** `AnyView` as one storage object, equivalent as what it holds — `9914771`
- [x] **1.7** `OpaqueValue`/`OpaqueReference` as one `Box<T>` — `9914771`
- [x] **1.8** Comparing by a per-type witness, not through `Any` — `d1e038c`
- [x] **1.9** Built-in animated values as their own types — `f8eb992`.
  Colors and transitions keep their vector, as the commit says.
- [ ] **1.10** Enums inside one content type. Did not fall out of 1.1:
  `TransformContent.Kind` and `DecorationContent.Order` are still there.
- [x] **1.11** `ShapeStyle` is a protocol — `25eeafe`. Styles resolve
  where their view is built; examples, demo and tests moved over.

## [Phase 2](phase-2-view-positions.md): a position object instead of `[Int]` paths

- [x] **2.3** Forgetting without a scan — `d350522`
- [~] **2.4 / 2.5** The position object and one trie. Not started as
  designed; `0f10917` gives the builder a cursor into the record tries, so
  finding a view's place is one step per child instead of a walk from the
  root. Paths are still the keys everywhere.
- [ ] **2.6** What a position caches — waits on 2.4.
- [~] **2.7** `ForEach` rows
  - [ ] a row's slot is the hash of its id
  - [ ] a change read in one row closure re-runs every row closure
  - [x] a `ForEach` compared like any other input — `5ce17e3`
- Steps of 2.8: 1 and 2 done (2.3, 6.7); 3 to 7 not started.

## [Phase 3](phase-3-layout.md): layout caches and stack math

- [x] **3.1** A node's caches inline, not dictionaries — `d350522`
- [x] **3.2** A stack's children's stretch measured once — `d27ea61`
- [x] **3.3** A stack's last run kept for placing — `d27ea61`
- [x] **3.4** The same for `HStackLayout`/`VStackLayout`, separately — `d27ea61`
- [x] **3.5** Capabilities found by casting — no commit of its own: since
  1.3 both casts run only on nodes whose traits say they have the
  capability.
- [ ] **3.6** A scoped rebuild keeps the ancestors' caches when the new
  subtree measures the same.
- [x] **3.7** Nothing to do, by the plan.
- [x] **3.8** Flattened layout children kept on the node — `d27ea61`
- [x] **3.9** Transform math — `d350522`

## [Phase 4](phase-4-placement-and-display-list.md): placing and drawing only what changed

- [~] **4.1** Every pass places the whole tree
  - [x] step 1: a version per list in place of a deep comparison —
    `a0f05ce`. Per kept list rather than per leaf: a list that is a kept
    list, as it is or moved once (a boundary holding one kept subtree, in
    its image's space), compares by its number; any other list by its
    commands.
  - [x] step 2: skip a clean subtree — `ee269ed`. Kinds say whether they
    place purely (`NodeContent.placesPurely`, off by default); a clean,
    stable pure subtree appends what it kept. Clean means nothing asked for
    a frame and no state was read while it was placed. Checked in Bookmarks,
    Flashcards, MindMap and Reader by placing each appended subtree fresh
    too: about 70,000 appends, none different.
  - [ ] step 3: frames relative to the boundary, so a scrolled or moved
    subtree is kept too
- [x] **4.2** Paths in their own space — `d6af0fd`
- [x] **4.3** The path kept on the node — `d6af0fd`
- [x] **4.4** One draw state shared by the five commands — `5e8fe6e`. The
  list keeps a `DrawState` per run of commands; each command has an index
  into them. The payloads stay inline in the command enum, not in side
  arrays.
- [x] **4.5** A path's elements as flat arrays — `b42bfcf`. `elements`
  and `Path.Element` stay as public API, made from the storage on each ask.
- [x] **4.6** `DrawContext` split into plain data and one shared reference —
  `9fafb43`. Turned clips, the shader canvas input, the animation and the
  coordinate spaces sit behind one object; the rest is plain data.
- [x] **4.7** Paint bounds worked out once — `1280e85` (a shape's path box,
  kept on the node), `5e8fe6e` (each command's bounds under its state, kept
  by the list when the command is appended).
- [x] **4.8** Text drawn from its lines — `d9ceb03`
- [x] **4.9** No gradient rebuilt at full opacity — `d350522`

## [Phase 5](phase-5-skia-drawing-and-text.md): Skia draw calls and text

- [x] **5.1** State set once per run of commands — `d9ceb03`
- [x] **5.2** A rect, rounded rect or ellipse drawn in one call — `d6af0fd`
- [x] **5.3** Gradient shaders and dash effects kept — `d9ceb03`
- [ ] **5.4** A text blob per laid-out line. Goes with moving
  `TextMeasurer` and `FontRegistry` to Skia (CLAUDE.md).
- [ ] **5.5** Letter spacing in one call. With 5.4.
- [ ] **5.6** A font resolved to a small integer once.
- [ ] **5.7** The raster surface initializer. Not a performance item; goes
  when the pixel tests move to a software Vulkan driver.

## [Phase 6](phase-6-state-environment-bindings.md): environment, state writes, bindings

- [x] **6.1** Environment values as a chain of typed writes — `d46dd11`
- [x] **6.2** Environment reads as bits — `1bea9aa`
- [x] **6.3** Built-in modifiers write their own key — `d1e038c`
- [~] **6.4** Property wrappers without a holder — `7dd3cdc`.
  `@Environment`, `@Namespace` and `@FocusState` are bound in place and
  allocate nothing. `@State` keeps its holder: see the open decisions.
- [x] **6.5** A binding writes the part it points at — `e62b0b7`
- [x] **6.6** A write looks only at the readers it can reach — `e62b0b7`
- [x] **6.7** Reads on the tracker's stack frame — `d350522`

## [Phase 7](phase-7-input.md): hit testing and focus lookups

- [~] **7.1** Every hit test walks every node
  - [x] step 1: skip subtrees without the wanted trait — `d24813b`
  - [ ] step 2: one walk per pointer down
  - [ ] step 3: skip a boundary by its paint bounds (with 4.1)
- [x] **7.2** Finding a node by path — `d350522`; the focus-binding walk
  is skipped through the trait bit since `d24813b`.
- [x] **7.3** Covered by 3.8: the single-child loops read the cached
  layout children.
- [x] **7.4** A move undone by subtraction — `5ce17e3`. A general
  transform's inverse is still worked out when needed, not kept.
- [x] **7.5** Preference observers kept in order — `297141f`

## Not in the plan, done on the way

- `43a7f32` — closure equivalence read a context whose capture layout is
  only known at run time (one holding a Foundation `Date`) from its header.
  Bookmarks crashed comparing the inspector's buttons.
- `116a331` — `DrawContext` no longer carries the color scheme: since 1.11
  nothing read it there.

## Open decisions

- **`@State`'s holder (6.4).** A write in an initializer to a state that
  has an initial value (`self.value = start`) is the state's first value;
  it goes through a nonmutating setter before the view is bound, so it
  needs a shared reference. Removing the holder means dropping that
  feature, as SwiftUI ignores such writes.
- **`.primary`, `.secondary`, `.tertiary` (1.11).** Fixed light/dark grays,
  as before. In SwiftUI they derive from the foreground style in effect;
  switching changes how text looks in several examples.

## Measuring

- `Scripts/bench_animations.py` has a baseline from before the branch
  (`.build/bench/opt-before`: `bookmarks-layout`, `flashcards-card`). No
  run since; the comparison is still to do. Tried after `e24ea3d`
  (2026-11-14): the machine was busy (load around 6), so no numbers were
  taken.
- `0f10917` measured Bookmarks' Cards/List rebuild from samples: 1171
  before, 881 after (debug build).

## Outside this repo

These use the style API and need the same changes as the examples when
they move to this NucleantUI (1.11): NucleantCEF, NucleantLayouts,
NucleantMonaco, NucleantTransitions, NucleantUI_PyShader, PyShader.
