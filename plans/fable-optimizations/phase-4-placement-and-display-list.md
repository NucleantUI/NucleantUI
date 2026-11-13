# Phase 4: placing and drawing only what changed

## 4.1 Every pass places the whole tree

**Today.** `ViewHost.layoutAndRender` in
[ViewHost.swift](../../Sources/NucleantUI/App/ViewHost.swift) calls
`node.place(in: window, …)` on the root in every pass. Every node runs
`place`, and every leaf appends its commands again. Then the results are
compared by value to find out what changed:

- the window's list against `windowContent`;
- for each render boundary, its list, translated into the image's space,
  against `entry.content` (`NodePainter.schedule`).

A pass runs whenever something is dirty or anything is animating. So one
knob animating at 120 Hz places the whole window, rebuilds every path and
every command, and compares them all, 120 times a second, to conclude that
one image changed. The build is scoped to what changed. Placement is not.

**Do instead**, in three steps, each useful alone.

**Step 1: a version in place of a deep comparison.** Each list a boundary
produces gets a number that changes only when its content does. Comparing
two lists is then comparing two numbers. To have a number to trust, a leaf
must know whether what it emits is what it emitted last pass. It can tell: it is the
same node as last pass, its rect and context are the same, and nothing it
reads is moving.

**Step 2: skip placing a clean subtree.** A subtree can keep the commands
it produced last pass when all of these hold:

- nothing in it was rebuilt since;
- nothing in it has an animated value or a node motion in flight;
- nothing in it read state while being placed;
- it is placed with the same rect, proposal and draw context as last time.

That needs a "needs placement" mark that a graft, an animation start and a
placement-time state read set on a node and on its ancestors, in the way
`invalidateMeasurementsUpwards` already walks up. And a record on each
boundary of what it was last placed with.

**Step 3: frames relative to the boundary.** `ViewNode.frame` is in window
coordinates, so a scroll changes every frame under it and nothing below a
moving view can be skipped by step 2. With frames kept relative to the
nearest boundary, a moved subtree is the same subtree at another origin:
its commands stay, and only where its image is composited changes. This is
the deepest of the three, and hit testing has to learn to add the origins
up.

## 4.2 Paths are made absolute, then moved back

**Today.**

- `Shape.path(in:)` is handed the placed rect in window coordinates. The
  comment in [Shape.swift](../../Sources/NucleantUI/Views/Shapes/Shape.swift)
  says this "saves a translate per shape".
- `RenderBoundaries.useImage` in
  [RenderBoundary.swift](../../Sources/NucleantUI/Layout/RenderBoundary.swift)
  then calls `DisplayList(commands:).translated(dx:dy:)` on every
  boundary's commands, every pass, so that content which only moved
  compares equal. That makes a new command array, and for every shape
  `Path.offsetBy` makes a new element array.

So each shape, each pass: a path built at an absolute position (one
allocation), the same path rebuilt shifted (another), then compared element
by element with last pass's.

**Do instead.** Build a path in the shape's own space, with the rect's
origin at zero, and carry the position in the command. The path then
depends only on the shape's value and its size. Nothing is translated, and
content that only moved is equal without any work. This also brings
`path(in:)` in line with SwiftUI, where the rect is in the shape's own
coordinate space.

## 4.3 Keep the path on the node

With 1.5 (`ShapeContent<S>`) and 4.2 (local paths), a shape node can keep
the last path it made and the size it was made for. A shape placed again at
the same size reuses it. Today `makePath(rect)` runs for every shape in
every pass.

## 4.4 Five commands repeat the same four fields

**Today.** [DisplayList.swift](../../Sources/NucleantUI/Render/DisplayList.swift):
`ShapeDraw`, `TextDraw`, `ImageDraw`, `SvgDraw` and `CanvasDraw` each carry
`transform`, `clip`, `clipCornerRadius` and `transformedClips`. Every
function over commands has five arms with the same body:
`transformed(by:)`, `clipped(to:)`, `paintBounds`, and the clip check in
`NodePainter.damage`.

Each element of `[DrawCommand]` is as large as the largest case, which is
`TextDraw` at a few hundred bytes. Check with
`MemoryLayout<DrawCommand>.stride`.

**Do instead.**

```swift
struct DrawState: Equatable { var transform; var clip; var clipCornerRadius; var transformedClips }

struct DrawCommand {
    var state: Int32        // index into the list's states
    var bounds: Rect        // where it can paint, computed once (4.7)
    var content: Content    // .shape, .text, .image, .svg, .canvas
}
```

- Functions over the state are written once.
- Commands placed under the same clip and transform share a state index.
  The renderer sets the state once per run of commands (5.1), and comparing
  states is comparing integers.
- The large payloads can live in side arrays, so the command array stays
  small and cheap to copy and compare.

## 4.5 A path element is as large as a text

**Today.** `Path.Element` has nine cases, among them
`.text(String, origin: Point, font: Font)` and `.image(RasterImage, in: Rect)`.
An enum is as large as its largest case, so a `.line(Point)`, sixteen bytes
of data, takes the room of a string, a point and a font. `Path` is
`Hashable`, and comparing or hashing walks every element through the enum.

**Do instead.**

- Geometry as two flat arrays, the way path libraries store it: a byte per
  verb, and the points.
- Text and images as a separate short list on the path. The renderer
  already draws them in a separate step after the geometry
  (`emitEmbedded`).
- The bounding box kept with the path, updated as elements are added, or
  computed by one sweep over the points array.

## 4.6 `DrawContext` is copied for every node

**Today.** `ViewNode.place` starts with `var context = context` for every
node, and most modifiers make another copy to change one field.
`DrawContext` has about fourteen fields. Two are arrays (`transformedClips`,
`coordinateSpaces`), and `shaderCanvasInput` and `animation` are optionals
of non-trivial types. Each copy retains and releases those.

**Do instead.** Split it. The part that changes often (opacity, transform,
clip, corner radius, color scheme, the flags) is plain data and is copied
freely. The rest sits behind one reference that most of the tree passes
along untouched.

## 4.7 Paint bounds are worked out again and again (standalone)

**Today.** `DrawCommand.paintBounds` is a computed property. For a shape it
walks every path element (`boundingBox`), and under a transform it runs
`Rect.applying` (3.9). It is called for each command in `splitRuns`, again
in `useImage`, again in `NodePainter.paintList`, and again in `damage`.

**Do instead.** Compute it once when the command is made and store it. The
leaf making the command has the rect and the stroke width at hand.

## 4.8 Text is joined to be split again (standalone)

**Today.** `TextContent.place` in
[LeafContent.swift](../../Sources/NucleantUI/Layout/LeafContent.swift):

- calls `TextMeasurer.layout(input, proposal:)` in every pass. That is a
  dictionary lookup keyed by `TextLayoutInput`, which hashes the whole
  string and the font's family name;
- builds `layout.lines.joined(separator: "\n")`, a new string, in every
  pass;
- the renderer then does `draw.string.split(separator: "\n")` and maps
  each piece back to a `String`.

**Do instead.** The node keeps the layout it was sized with (the cache of
3.3 does this), and `TextDraw` carries the lines as the array the layout
already holds.

## 4.9 A gradient is rebuilt at full opacity (standalone)

**Today.** `DrawContext.resolve(_ style:)` calls `faded(gradient)` for both
gradient cases without looking at the opacity. `faded` maps the stops into
a new array. At opacity 1 the result equals the input, and one array was
allocated per gradient shape per pass.

**Fix:** return the style as it is when `opacity >= 1`, as
`resolve(_ color:)` does.

## Order

1. 4.9, 4.7, 4.8: small and standalone.
2. 4.2 and 4.3, after 1.5.
3. 4.4 and 4.5, together with 5.1.
4. 4.6.
5. 4.1 step 1, then step 2, then step 3.

## Checking

- The pass time in the perf trace while one control animates on a busy
  screen. This is the number 4.1 is for.
- `Scripts/bench_animations.py`, all scenarios.
- The render tests must produce the same pixels. 4.2 changes coordinates
  in every command, so it is the one most likely to move a pixel.
