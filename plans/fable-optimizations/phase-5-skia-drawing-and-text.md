# Phase 5: Skia draw calls and text

All of this is in
[SkiaDisplayRenderer.swift](../../Sources/NucleantUI/Render/SkiaDisplayRenderer.swift)
unless a finding says otherwise. NucleantSkia already wraps every call
named here (`drawRect`, `drawRRect`, `drawOval`, `drawTextBlob`), so no
change is needed outside NucleantUI.

## 5.1 The state is set and torn down for every command

**Today.** Each `emit` does `canvas.save()`, `begin(on:…)`, which sets the
clip with anti-aliasing and concatenates the transform, then the draw, then
`canvas.restore()`. A row of twenty labels under one scroll view's clip
sets and drops that clip twenty times. A rounded clip is the expensive
kind.

**Do instead.** With the shared state of 4.4, the renderer walks runs of
commands that have the same state: one save, one clip, one transform, the
draws, one restore.

**Standalone version**, before 4.4: remember the last command's four state
fields, and keep the save open while the next command's are equal.

## 5.2 Every shape goes through a path object

**Today.** `emit(_ draw: ShapeDraw, …)` resets the shared `SkPath`, appends
the elements one call at a time, and calls `drawPath`. Rectangles, rounded
rectangles and ellipses are most of what a UI draws: backgrounds, borders,
dividers, the track and thumb of every control. Each takes three or more
calls into Skia where one would do.

**Do instead.**

- A path that is one rect, one rounded rect or one ellipse is drawn with
  `drawRect`, `drawRRect` or `drawOval`. With 1.5 the node knows this from
  the shape's type and does not have to inspect a path.
- A real path keeps its `SkPath` alongside it once the path is kept on the
  node (4.3), so an unchanged path is not appended again.

## 5.3 Paint objects are made per draw

**Today.**

- A gradient fill calls `SkGradientShader.makeLinear` or
  `makeTwoPointConical` for every draw in every render. `stops(_:)` builds
  two arrays for it.
- A dashed stroke builds a `[Float]` and an `SkDashPathEffect` for every
  draw.

**Do instead.** A small cache in the renderer keyed by the gradient with
its resolved points, and by the dash pattern, emptied of what a render did
not use, the way `images` is handled today.

## 5.4 Text is shaped again on every draw

**Today.** For each `TextDraw`, in every render that includes it:

- `FontRegistry.resolve(draw.font)`: a dictionary lookup keyed by a struct
  holding the family string;
- `font(family:size:slanted:)`: another lookup keyed by the family string
  and the size;
- the string is split into lines (4.8);
- `runs(of:in:family:style:)` scans the line for non-ASCII bytes;
- each run is measured with `measureText` to align the line, although
  layout already knows the line's width;
- `drawString` converts the text to glyphs and positions them.

Text is most of what is on screen, and most of it is the same from one
frame to the next.

**Do instead.** Keep an `SkTextBlob` per laid-out line: the glyph ids and
positions, made once. Drawing a line is then one `drawTextBlob` at its
origin. The blob belongs with the layout entry `TextMeasurer` already
keeps per text and proposal, so it lives exactly as long as the layout
does. The line's width is stored with it, so nothing is measured to align.

**This goes together with moving measuring to Skia.** CLAUDE.md lists
`TextMeasurer` and `FontRegistry` as code still to move. Once the advances
come from the same `SkFont` that draws, measuring a line and building its
blob are one step over the same glyphs, and the point-size factor
`thorPointScale` is no longer needed. Do the move first, or together with
this.

## 5.5 Letter spacing converts one character at a time

**Today.** `spaced(_:by:)` builds a `String` for each character, calls
`textToGlyphs` and `getWidths` on it, and appends to arrays. It runs for
every spaced line in every render.

**Do instead.** The same blob as 5.4: glyphs for the whole run in one call,
positions computed from the widths plus the spacing, built once.

## 5.6 A font is looked up by its strings

**Today.** A `Font` is a family string, a size, a weight, a design and an
italic flag. In one pass one text has it hashed or compared in
`TextLayoutInput` (the layout cache), `FontRegistry.resolutions`,
`TextMeasurer.faceIndices`, and the renderer's `fonts` and `typefaces`.

**Do instead.** Resolve the font to a small integer once, when `Text`
builds its node. `TextMeasurer` already works with face indices
internally. `TextContent` and `TextDraw` carry the index, and every table
after that is an array.

## 5.7 A raster surface initializer

`SkiaDisplayRenderer.init(surface: SkRasterSurface)` draws into a CPU
surface, for tests that read pixels back. CLAUDE.md says there is no CPU
rendering path, tests included, and that such tests use a software Vulkan
driver. Not a performance item. It should go when those tests move.

## Order

1. 5.1 standalone version, and 5.3.
2. 5.2 for rects and ellipses.
3. 5.6.
4. Measuring moved to Skia, then 5.4 and 5.5.

## Checking

- Time Profiler on a text-heavy example (Reader) while scrolling: the
  share of time under `emit(_: TextDraw …)`.
- The render tests must produce the same pixels. 5.4 can move a glyph by a
  fraction of a pixel if blob positions round differently from
  `drawString`. Compare screenshots at 1x and 2x.
