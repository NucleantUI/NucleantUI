
# in NucleantUI and the Thor / Skia we use SIMD2 for size and postion

* how well is it even used... ?

if it requires to use apples simd lib then i guess 

https://github.com/keyvariable/kvSIMD.swift

should be used for none apple platforms...

since not everything supports avx512 lets leave that out of the picture for now...

figure out what intel / amd / apple range supports of 256 bit simd if that is a factor for 128 vs 256..

remember our swift code is only matters for nucleantui and nothing todo with skia own types or thorvg..
just internal between views and rendernodes and the pipeline between for skia / thorvg...

---

## Findings (2026-10-02)

### How much SIMD is used today

Hardly at all, and not where the math happens.

- `Point` / `Size` / `Rect` / `EdgeInsets` (`Geometry/Geometry.swift`) are plain
  `Double` fields. All layout and animation math (`StackLayouts`,
  `NodeMotion.displaced`, `Rect.intersection`, `AnimatablePair`) is scalar
  Swift on those.
- `SIMD2`/`SIMD4` only show up at the hand-off points: `compositeRect` /
  `compositeScissor` (`SIMD4<Double>`, read by `VulkanRenderEngine` and turned
  straight into a Float `VkViewport` / Int `VkRect2D`), `win_rect`,
  `ThorCanvas` sizes, and the arguments `SkiaDisplayRenderer` passes into the
  NucleantSkia / NucleantThorVG wrappers. Those wrappers unpack each vector to
  scalars for the C call (`pos.x, pos.y`), so the vector is just a tuple there.

### Apple `simd` / kvSIMD

Not needed. `SIMD2`/`SIMD4`/`SIMDScalar`, `.<`, `replacing(with:where:)`,
`.sum()` and the element-wise operators are in the Swift standard library on
every platform. Nothing in NucleantUI imports Apple's `simd` module (the
ThorVG wrapper already has it commented out). kvSIMD re-creates Apple's
`simd_*` functions and matrix types (`simd_dot`, `simd_float4x4`, …) for
Linux. We'd only need it if we started calling those, and dot/length/lerp
take a few lines each on top of the stdlib.

### 128 vs 256 bit

- **ARM (every Apple Silicon Mac, iPhone/iPad, Android):** NEON, 128 bit.
  Apple's cores don't run SVE outside SME streaming mode. Armv9 Android cores
  (Cortex-X2 / A710 and later) do have SVE2, but at a 128-bit vector length.
  So a 256-bit type is always two 128-bit ops on ARM.
- **x86:** AVX (256-bit float) arrived with Intel Sandy Bridge (2011) and AMD
  Bulldozer (2011). AVX2 came with Haswell (2013) and Excavator / Zen 1, and
  Zen 1 still splits 256-bit ops into two 128-bit halves. Low-end Atom-class
  Pentium/Celeron chips had no AVX until Gracemont (Alder Lake-N). More
  importantly, the default Swift x86_64 build targets an SSE-only baseline,
  so it never emits AVX unless the build passes `-target-cpu`.
- So 128 bit is the width that's native everywhere: `SIMD2<Double>` (a point
  or size) or `SIMD4<Float>` (a whole rect). `SIMD4<Double>` is 256 bit, and
  even with `-target-cpu haswell` it only helps in bulk loops over memory.
  For single-rect math it costs extra `vinsertf128`/`vextractf128` work,
  because the calling convention passes it as two xmm registers.

### Codegen (swiftc 6.3.3 `-O`, arm64 and x86_64)

Rect intersection written four ways:

| variant | arm64 | x86_64 (SSE) | x86_64 haswell |
|---|---|---|---|
| scalar `Double` fields (today's `Rect`) | 21 instrs, no branches | ~30, **auto-vectorized** to `addpd/minpd/blendvpd` | 15 instrs, packed `xmm` |
| `SIMD2` + `pointwiseMin/Max` | ~50, branchy | ~60, branchy | ~55, branchy |
| `SIMD2` + `replacing(with:where:)` | 9, packed `.2d` | not compiled | **7** (`vmaxpd/vminpd`) |
| `SIMD4<Double>` box | packed, 2×`.2d` | not compiled | `ymm`, but insert/extract overhead |

- LLVM's SLP vectorizer already packs the scalar x/y pairs, and an array
  loop over scalar rects already compiles to `fadd.2d` / `addpd`.
- **`pointwiseMin`/`pointwiseMax` on floating-point SIMD are a trap.** They
  implement IEEE `minimum` NaN rules lane by lane, which compiles to scalar
  code with NaN-test branches. That's slower than the plain scalar struct. Use
  `a.replacing(with: b, where: b .< a)` to get one `minpd` / `fcmgt+bit`.

### Where animation + layout time actually goes

Measured from outside with no code changes: the release Bookmarks build,
Cards ⇄ List switched 20× by synthesized clicks (`.smooth(duration: 0.5)`
morph), `sample` at 1 ms for 17 s. That took about 9.4 s of process CPU.

Main thread: about 7.0k of 14.1k samples busy, almost all in `ViewHost.update`:
- `rebuildScoped` → `record.rebuild` (rebuilding bodies, `buildNode`): ~2.9k
  (~41%)
- `layoutAndRender` → `node.place`: ~3.1k (~45%). Within that:
  `sizeThatFits` ~0.9k, `TextMeasurer` ~0.26k, `NodePainter` ~0.17k,
  display renderer ~0.13k.

Self time (top of stack), all threads, ~5.8k busy samples:

| bucket | share |
|---|---|
| ARC retain/release | 27% |
| malloc/free/memmove | 18% |
| hashing / `Dictionary.find` | 14% |
| runtime metadata, conformance lookups, `tryCast` | 8% |
| text measuring / `String` | 7% |
| exclusivity checks (`swift_beginAccess`) | 3% |
| geometry / animation math functions (`animate`, `sizeThatFits` self, stack layout…) | **~1%** |

### Conclusion

- Moving the geometry types onto SIMD would save at most around 1% of a
  layout-morph frame, and on x86 the compiler already vectorizes that math.
  The public `Point/Size/Rect` should keep SwiftUI's `x/y/width/height`
  shape either way.
- If SIMD gets used internally anyway (for example, bulk loops over many
  rects or path points), stick to the 128-bit shapes (`SIMD2<Double>`,
  `SIMD4<Float>`) and never `pointwiseMin/Max` on floats. Don't add kvSIMD,
  don't target AVX/AVX-512.
- The real cost in animation and layout is per-node overhead in the
  rebuild + place passes: ARC traffic, allocation, dictionary hashing
  (`PathTrie`, `RebuildRecords`, `preference` lookups), dynamic casts and
  metadata lookups, and text re-measuring. That's where a performance plan
  should go next, and it's a different plan from this one.

### Follow-up: where the ARC comes from, and the real assembly

ARC samples traced back to the nearest NucleantUI caller (same Bookmarks
profile, about 1.6k samples). The RenderNode side (`NucleantRenderNode`,
`VulkanRenderEngine.drawFrame`, ~250 samples in total) has no ARC callers
anywhere in the list, so the unretained/borrowing approach there is working.
The ARC is all on the view side, in the rebuild/layout passes:

| caller | ARC samples |
|---|---|
| `TextMeasurer` (`wrap`, `measure`, `advance`, `width`): a `String` per word piece, `components`/`split`, `[String]` lines, run on every measure | ~350 |
| `PathTrie.node(at:)` / `makeNode(at:)`: a class `Node` per level, `[Int: Node]` per node, retain/release on every hop | ~210 |
| `ViewNode.layoutChildren` getter: builds a new `[ViewNode]` via `flatMap` every call | ~107 |
| `RebuildRecords` (`previousNode`, `Entry` copies/destroys) | ~130 |
| `buildNode`, `ViewNode.deinit`/`init`, `BuildContext` copies/destroys | ~170 |
| `ViewNode.preference`, `focusBindings` | ~85 |

Disassembly of the release `Bookmarks` binary (x86_64, default CPU):

- `Rect.intersection`: already packed SSE2 (`addpd`, `minpd`, `blendvpd`,
  `subpd`), no calls. As good as it gets at 128 bit.
- `ViewNode.animate` (553 instrs): its geometry is already packed (24 packed-
  double ops). It also makes 9 `swift_retain`/`release` calls, plus copies and
  destroys of `Animation?`/`AnyTransition`.
- `StackContent.layout` (1461 instrs): about 35 FP instructions total. It makes
  15 `Dictionary.find`, 5 dictionary copy/resize, 12 `swift_release`, 24
  `swift_beginAccess`/`endAccess`, and 5 `MainActor.shared` /
  `unownedExecutor` / `reportUnexpectedExecutor` runtime isolation checks.
  The math is a rounding error next to the bookkeeping.

Scope: none of this involves the app's `@Observable` model classes. None of
the ARC samples trace back to them, and Observation as a whole is about 129
samples, almost all of it the `withObservationTracking` wrapper around body
evaluation. If ARC work is done, it's on framework-internal classes only,
the ones on the hot path: `ViewNode`, `PathTrie` / `PathTrie.Node`,
`RebuildRecords`, `AnimationStore`, `AnimatableDataState` and
`OpaqueReference`. TextMeasurer's ARC is `String` storage, not a class.

## Execution (2026-10-02, branch `simd_optimizing`)

Measured from outside with no instrumentation added: a `NUCLEANT_TRACE=1`
release build of Bookmarks, run with `NUCLEANT_SWIFTUI_TRACE_PERF=1`, Cards ⇄
List switched 20× by synthesized clicks, and the per-pass times it already
logs. Total process CPU is the wrong number here: cheaper frames mean more of
them in each 0.5 s morph.

| step | passes / run | mean pass | build | layout + render |
|---|---|---|---|---|
| baseline | ~485 | 18.1 ms | 8.9 ms | 9.2 ms |
| TextMeasurer: face table, line breaking by ranges | ~670 | 14.3 ms | 8.6 ms | 5.7 ms |
| RebuildRecords: `RecordedView`, reuse check reads entry in place | ~740 | 13.5 ms | 7.7 ms | 5.7 ms |
| TextMeasurer ASCII-byte fast path + PathTrie unretained walks | ~880 | 11.7 ms | 6.7 ms | 5.0 ms |
| `layoutChildren` / `singleChild` / `isLeaving`, preference without cast | ~900 | 11.3 ms | 6.8 ms | 4.5 ms |
| per-type comparators + builtin makers | ~905 | **10.65 ms** | 6.0 ms | 4.7 ms |

That's −41% per pass. The baseline was over the 16.7 ms budget at 60 Hz.
The final screen after 20 morphs is pixel-identical to the baseline's.

What changed:

- `Render/TextMeasurer.swift`:
  - Faces are interned to an index, and each holds a 128-entry ASCII
    advance table plus a dictionary for other characters. This replaces
    hashing (family `String`, `Character`) per glyph.
  - Widths are summed a UTF-8 byte at a time while the text is ASCII, and
    character by character from the last safe boundary otherwise. Addition
    order is unchanged, so sums are bit-identical.
  - `breakLines` walks index ranges, and `measure` never builds the line
    strings.
- `Layout/BuildContext.swift`:
  - `PathTrie.Node` keeps its children in hand-managed buffers (raw
    pointers plus `Unmanaged`, scanned linearly, indexed past 16 children,
    swap-removed). Walks go through `Unmanaged._withUnsafeGuaranteedRef`,
    so there's no retain/release, hashing or struct copy per step.
  - `RebuildRecords.Entry` holds one `RecordedView` (`RecordedViewOf<V>`)
    instead of two closures. The reuse check compares through a typed
    pointer, which is sound because the identity, and with it the type, is
    matched first. It no longer boxes the view as `Any` and casts it back.
  - `Candidate` reads fields in place instead of copying the entry.
- `Layout/ViewNode.swift`:
  - `layoutChildren` returns `children` when there's nothing to flatten,
    using closure-free loops.
  - `singleChild` doesn't build the array.
  - `isLeaving` is a flag kept by `removal`'s `didSet`.
  - `buildNode` caches a `BuiltinMaker` per view type (no `as? BuiltinView`
    box or conformance lookup per build).
  - `NodeContent.preference(_:below:)` replaces the `PreferenceContent`
    protocol and its cast. Its two conformers keep their implementations.
- `Core/Equivalence.swift`: `_dynamicallyEquivalent` resolves how to
  compare once per type and caches a comparator (same order:
  `ViewInput`, class identity, `Equatable`).
- `FocusModifiers`, `LazyLayout`, `NodeMotion`: per-pass walks use
  `isLeaving`.

New tests: `TextMeasurerTests` (wrap, size and width against the old
algorithm), `PathTrieTests` (children against a dictionary model,
retain/release, file/detach/attach), and `PreferenceAndFlatteningTests`.
These pass on the original sources too, so they pin existing behavior.
96/96 tests pass.

Left, each under ~5% of a morph frame now:

- `_ModifierView._isEquivalent`: modifier keys are `[AnyHashable]` boxed in
  `AnyHashable`. Making them typed touches all 51 `_ModifierView` sites.
- Tearing down the previous frame's entries and node subtrees for views that
  really rebuild (`rebuildScoped`, `Entry` destroy).
- `ViewNode.preference` (an `OpaqueValue` box and dictionary write per node
  per key), `TextMeasurer.measure`'s `SizeKey` hashing, and `focusBindings`.
