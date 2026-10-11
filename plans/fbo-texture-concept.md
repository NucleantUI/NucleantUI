# FBO concept

i know we kinda are doing this already by the rendering to VKImage

but i would like the ability to be able to think like this


```swift

class RenderTexture {
    /* should work abit like the External Texture
     where we render things to the VKImage
     and then we can allow general more low level
     oprations with mixing textures together
     and as Shader Argument also..

     in general this should represent our most
     low level and efficient way to deal with texture
     manipulation and allow operations like 
     blending textures by generated shader 
     where they are inputs
     but we can make other layers later on that combine 
     multi RenderTexture
    */
}

// generic function to call.. returns RenderTexture
let renderedTexture = renderTexture(...) {
    // View Builder version
} // save it in DataModels and other places..
// or just 
let renderedTexture = RenderTexture(..., SomeView(...))


// or by ViewModifier

let renderedTexture = SomeView(....).texture()

```

and a image version (just a function to call)

```swift
let renderedImage = renderImage(...) {
    // View Builder version
} // save it in DataModels and other places..
// or just 
let renderedImage = renderImage(..., SomeView(...))


// or by ViewModifier

let renderedImage = SomeView(....).image()


```

but RenderTexture needs to be Shader Argument option now also..

and dont know if an option to call 

tex.view()

inside ViewBuilder stuff

and also option to call

tex.shader(....)

soo like when the VertFragShader is using View as vertex/fragment input
then it could also do it directly on a RenderTexture, and .shader just returns Some View as it normally does when being a view modifer..

---

## Notes — what executing this means (2026-10-06)

Read against the code as it stands: `App/ShaderSlotRegistry.swift`,
`App/RenderNodeManager.swift`, `App/CanvasNode.swift`,
`App/TextureNodeManager.swift`, `Views/TextureView/`,
`Modifiers/ShaderModifiers.swift`, `Render/ShaderPipeline.swift`,
`Render/ThorDisplayRenderer.swift`, plus `NucleantVulkan`'s
`Nodes/OGLShaderNode.swift` and `Nodes/VulkanRenderEngine+ExternalTexture.swift`.

### What is already in place (so most of this is wiring, not new engine work)

* **A view's subtree already renders into a VkImage of its own.** That is the
  `.shader(_:)` layer: `ShaderEffectContent.place` gives the child a
  `DisplayList` of its own, and `ShaderSlotRegistry.useLayer` draws it into a
  pooled canvas node (`RenderNodeManager.acquire(width:height:reusing:)`) with
  `compositesToWindow = false`. A `RenderTexture` is that canvas **without the
  shader on top of it, and without being keyed to a layout pass**.
* **Sampling an existing node's image is already a path.**
  `ShaderSlotRegistry.useCanvas` binds a `ThorCanvas` view's own image as
  `uContent` instead of a layer's, and the codegen already handles its
  orientation (`contentIsTopDown:` in `ShaderCode.compute` /
  `GraphicsShaderCode.graphics`). `tex.shader(fx)` is that call with a texture
  in place of the canvas node.
* **A worked example of the compute slot to write ours from.**
  `OGLShaderNode` (NucleantVulkan) is what the compute slot has been so far:
  an image it owns, pipeline handles installed from outside, a list of sampled
  `textureInputs`, and an `update` that barriers → dispatches 8×8 groups →
  barriers back → publishes in `engine.readable`. We are writing our own node
  rather than using it (see below), so it is a reference for the dispatch and
  barrier contract, not a dependency. The descriptor *layout* capped at one
  sampler lives in our `ShaderPipeline` anyway, which is where the "RenderTexture
  as shader argument" cap actually sits.
* **Readback exists, for one node kind.**
  `readExternalTexture` (blocking, `oneTimeSubmit`, BGRA rows top-first) is the
  shape `renderImage` wants; it needs generalising to any image. Thor node
  images already carry `TRANSFER_SRC | TRANSFER_DST | SAMPLED`
  (`VulkanRenderEngine+Thor.swift`), so a canvas-backed texture can be read
  back as it is. `ShaderSlotRegistry.makeImage` does **not** set
  `TRANSFER_SRC` — add it there if a shader-written texture must be readable.
* **A CPU path for `renderImage` is available without the GPU at all.**
  `ThorDisplayRenderer.init(canvas:)` takes a bare `Tvg_Canvas`, and
  `tvg_swcanvas_create` / `tvg_swcanvas_set_target` are in
  `CThorVG/include/thorvg_capi.h`. ThorVG's `ARGB8888` is exactly
  `RasterImage`'s contract (`Graphics/RasterImage.swift`), so a display list
  can be rasterized straight into `[UInt32]` and handed to `Image`. That makes
  `renderImage` headless, cross-platform and unit-testable — the GPU path never
  is, since the test target has no engine.

### Our own node types — `Context` is ours, so we pick

`NucleantRenderNode.Context` (`App/NucleantRenderNode.swift`) is **NucleantUI's
enum**, and `VulkanRenderEngine` is generic over its container node precisely
so each host picks its own set of backends. Nothing on the NucleantVulkan side
requires `OGLShaderNode` to appear in it. So: **we write our own nodes in
NucleantUI and put those in `Context`, and `OGLShaderNode` leaves it
altogether.** It stays where it is in NucleantVulkan, untouched, for whatever
else uses it — we simply stop being one of its callers.

Decided: the new node takes over the compute slot outright — `Shader` views,
`.shader(_:)` effects and `RenderTexture` all run on it.

```swift
enum Context {
    case thor(ThorShaderNode<NucleantRenderNode>)
    case skia(SkiaShaderNode<NucleantRenderNode>)
    case compute(ComputeShaderNode)            // ours — replaces .shader
    case vertexShader(VertFragShaderNode<NucleantRenderNode>)
    case image(ImageNode<NucleantRenderNode>)
    case externalTexture(ExternalTextureNode<NucleantRenderNode>)
    case renderTexture(RenderTextureNode)      // ours — a borrowed image
}
```

**`ComputeShaderNode`** (`Render/ComputeShaderNode.swift`, new): an
`@Observable final class` conforming to `NucleantVulkan.VulkanRenderNode` —
which is all `NucleantRenderNode.observe(_:)` and the engine ever ask of a
node. It owns its image/view/memory, carries the pipeline handles the
`ShaderPipeline` installs, holds its sampled inputs as a plain
`[(name: String, imageView: VkImageView)]` in binding order with a
`descriptorsNeedRebind` flag, and its `update` barriers from its tracked
layout, dispatches `(w + 7) / 8` groups, barriers back and publishes
`engine.readable` — staying unpublished while it has no pipeline, as the slot
does today. Two things it does that the old node does not, both of which were
"fix it in NucleantVulkan" items a moment ago and are now simply ours:

* its tail barrier names **`COMPUTE | FRAGMENT`** as the image's readers, so a
  texture a shader wrote can be sampled by another shader in the same frame
  (§19 made the same fix for the thor node);
* `descriptorsNeedRebind` is a plain flag the registry sets and consumes —
  the registry is the one that knows a texture changed, so there is no
  Observation round-trip to arrange.

**`RenderTextureNode`** (same file or beside it, new): the borrowed-image
container — `update` only publishes `readable` once the texture has content,
`destroyResources` frees nothing, because the texture owns the image and frees
it once through the deferred-release queue. That is what lets several
placements, and a shader sampling it, all point at one image.

Both are standalone code written fresh against the protocol, not a refactor of
anything in NucleantVulkan. The whole of phase 0 lands inside this repo
because of it: raw Vulkan from NucleantUI is already how
`ShaderSlotRegistry.makeImage` works (`engine.device`, `engine.findMemoryType`,
`engine.oneTimeSubmit` are all public), so even the readback helper
`renderImage`/`tex.image()` needs can be ours rather than a new public API on
the engine.

One gap to note rather than fix now: `VertFragShaderNode` stays NucleantVulkan's
(the `.vertexShader` case is unchanged), and its own tail barrier names the
fragment stage only. The day a *graphics*-written `RenderTexture` has to be
sampled by a compute shader, that is either a NucleantVulkan change or — the
same trick again — our own graphics node in `Context`.

### Decisions

1. **`RenderTexture` is a `@MainActor final class` that owns its image and
   lives outside the layout pass.** Everything else GPU-side in the framework
   is keyed to a view and retired when the view is not seen in a pass
   (`ShaderSlotRegistry.endPass`, `RenderNodeManager.retireUnused`). A texture
   a data model holds has no view, so its owner is the Swift reference: on
   `deinit` it hands its node to the registry's pending-release queue and the
   GPU objects are freed at the top of the next frame — the same detach-now,
   free-later rule as `retire` / `releasePending`, for the same MoltenVK
   use-after-free reason. Never freed inside a pass.
2. **Phase 1 backing is a pooled canvas node** (`RenderNodeManager.CanvasNode`:
   image + `DisplayRenderer` + container), taken through the existing
   `acquire`/`recycle` pool, so a texture costs ~1ms after the first one
   (PROCESS §19's 60ms is a *fresh* ThorVG target) and brings its renderer with
   it. No new image-allocation code and no new backend code: a Skia build gets
   Skia's canvas for free, because `CanvasBackend` is already the seam.
3. **The texture is stored top-down**, like a `ThorCanvas` image, not y-up like
   a `.shader` layer. So `tex.view()` composites it with no flip, readback rows
   come out top-first, and the flip happens only where it already does — in
   shader codegen, through `contentIsTopDown: true`, which §19 verified on the
   `useCanvas` path.
4. **An offscreen tree is a snapshot, not a second live host.**
   `Invalidator.shared` (`State/StateStore.swift`) is process-global and keyed
   by structural path, and `ShaderHost.current` is a single current-pass
   reference. A live second tree would steal the window's dirty paths and nest
   a pass inside a pass. So: `renderTexture(...) { ... }` builds its own
   `ViewNode`, lays it out at the given size, places it into a `DisplayList`,
   draws that into the texture's canvas, and stops. It re-renders when asked
   (`tex.render()`, or `tex.update { ... }` with a new view), not when state
   inside it changes. `@State` inside such a tree holds its value but nothing
   re-runs the tree for it — that is a documented limit, not a bug to chase.
   A real offscreen host (per-host invalidator) is phase 4 if it is ever wanted.
5. **Calling it during a pass is handled, not forbidden.** If
   `ShaderHost.current != nil` the call is inside the window's layout walk, so
   the render is queued and run at `endPass` rather than nested. `.texture()`
   and `.image()` are therefore *not* `ViewModifier`s — they are `View`
   extensions returning a `RenderTexture` / `RasterImage`, the way SwiftUI's
   `ImageRenderer` is a separate object rather than a modifier. Worth saying
   out loud in the doc comment, since `view.texture()` reads like one.
6. **Nested render nodes inside an offscreen tree are flattened**
   (`DrawContext.flattensRenderNodes = true`, as `ShaderEffectContent` already
   sets): a `.drawingGroup()` inside draws into the texture. A `Shader`,
   `VertexShader`, `TextureView` or `ThorCanvas` nested inside a
   `RenderTexture` has no window rect to composite into and is **out of scope
   for phase 1** — it draws nothing and logs once. (The sole-`ThorCanvas` case
   could later be served by the `useCanvas` trick: its image *is* the texture.)
7. **Textures reach a shader as their own parameter, not as a
   `ShaderArgument`.** `ShaderArgument` is `Hashable, Sendable` and packs into
   one float buffer at binding 3; a texture is a reference with an image view
   and belongs in a descriptor. So a parallel `textures:` parameter on
   `.shader(_:)` / `Shader` / `VertexShader`, with a `ShaderTextures`
   companion to `ShaderArguments` carrying name + texture in binding order.
   Bindings: 0 output, 1 uniforms, 2 content (`layer(uv)` — unchanged, so
   every shader that exists keeps working), 3 arguments, **4+ the named
   textures**. In a PyShader module each named texture is a parameter the
   entry point takes, sampled as `a(uv)` with `a_size` beside it, the way the
   interface's `arguments` already become parameters; the GLSL wrapper's
   mirror of that (`sampler2D uTex_<name>`, `vec4 <name>(vec2 p)`) is kept in
   step so the legacy inlet still compiles.
8. **Rebuild vs re-bind.** A changed texture *set* (names, order, count) changes
   the slot's `argumentSignature` and rebuilds the pipeline. A texture that
   merely got a new image (resize) writes its new image view into the node's
   input list and sets `descriptorsNeedRebind`; `ShaderPipeline` grows a
   `rebindDescriptors()` behind a drain and the registry consumes the flag,
   instead of rebuilding the whole slot the way today's `canvasView` check
   does.
9. **Ordering and barriers.** The engine updates nodes in `engine.nodes` order
   and `RenderNodeManager.endPass` sorts by this pass's paint order, with
   anything unplaced ranked `-1` — first. A `RenderTexture`'s node is never
   placed by the tree, so it lands there naturally: written before anything
   that samples it, in the same frame. The two sync details are both inside our
   own nodes now: `ComputeShaderNode`'s tail barrier names `COMPUTE | FRAGMENT`
   as the image's readers, so a texture one shader wrote can be sampled by
   another in the same frame; and `RenderTextureNode.update` inserts
   `engine.readable` itself, without which the composite skips it
   (`recordComposite` gates on `readable`).
10. **A texture is never a shader's input and output in the same pass.** The
    two-image rule from §19 stands: `tex.shader(fx)` *reads* `tex` and writes
    the slot's own image. Feedback is an explicit ping-pong pair, which is a
    later API (`RenderTexture.pair(...)`), not an accident.
11. **Showing one texture in two places** is one container node per
    *placement*, all borrowing one image — the `.renderTexture` case above.
    Since that case is ours to add, it comes with phase 1 rather than waiting:
    a placement takes a container, points it at the texture's current image
    view, and places it the way `DrawingGroupContent` places its node. The
    texture frees the image once, whatever is borrowing it.
12. **macOS only**, per the standing rule: the GPU path is the Vulkan/MoltenVK
    one we run; no other platform files are touched. The CPU `renderImage`
    path happens to be portable anyway (ThorVG SW canvas, Foundation only) —
    no `#if` anywhere, nothing Apple-only in a signature.

### The API, as it will read

```swift
// Produced outside the view tree — a model's property, not a view's.
let tex = renderTexture(size: Size(width: 512, height: 512), scale: 2) {
    Badge(level: level)                  // laid out at that size, drawn once
}
let tex = RenderTexture(size: ..., scale: 1, content: Badge(level: level))
let tex = Badge(level: level).texture(size: ...)     // same thing, trailing

tex.render()                              // draw it again, same content
tex.update { Badge(level: level + 1) }    // new content, same image
tex.size; tex.pixelWidth; tex.pixelHeight; tex.scale
tex.image()                               // RasterImage, GPU readback (blocking)

// CPU, no engine, no window — works in tests and on every platform.
let image = renderImage(size: ..., scale: 2) { Badge(level: level) }
let image = Badge(level: level).image(size: ...)

// Back into the tree.
tex.view()                                // some View: composites the image
tex.shader(ShaderLibrary.crt)             // some View: tex is uContent/layer(uv)

// As a named input to any shader, alongside the float arguments.
Shader(mix, arguments: [.float("blend", t)],
            textures: [.init("a", texA), .init("b", texB)])
panel.shader(fx, textures: [.init("noise", noise)])
```

In the shader body: `a(uv)`, `b(uv)`, `aSize`, `bSize` — `layer(uv)` keeps
meaning "the view this effect is applied to", so nothing that exists today
changes meaning.

### Work, in order

**Phase 0 — our own compute node, and the slot moved onto it.** All in this
repo, nothing in NucleantVulkan. New `Render/ComputeShaderNode.swift`
(`ComputeShaderNode` + `RenderTextureNode`); `Context.shader(OGLShaderNode)`
becomes `Context.compute(ComputeShaderNode)` and `.renderTexture` is added,
with the five switches in `NucleantRenderNode` following; `ShaderSlotRegistry`'s
`Backend.compute`, `makeSlot` and `destroy` carry our node instead.
`TRANSFER_SRC` added in `ShaderSlotRegistry.makeImage` so a shader-written
image can be read back. `ShaderPipeline` / `VertexShaderPipeline` descriptor
layouts take `[(name, VkImageView)]` in place of one optional `input`, and gain
`rebindDescriptors()`. A readback helper of ours (host buffer +
`engine.oneTimeSubmit` copy, as `readExternalTexture` does it) for
`tex.image()`.

The migration is verified before anything new is built on it: the `Shader`
gallery and the `.shader(_:)` effects screens behave exactly as they do today —
same output, same pooling figures, same resize cycling — with `OGLShaderNode`
no longer in `Context`.

**Phase 1 — the texture itself.** New `Sources/NucleantUI/Render/RenderTexture.swift`
(the class, its backing, its deferred release) and
`Sources/NucleantUI/Render/OffscreenRender.swift` (build + layout + place a
view tree into a `DisplayList` at a given size — the one place that drives a
tree with no window). `renderTexture`, `RenderTexture.init`, `.texture()`,
`tex.view()` (a `RenderTextureView` placed like a drawing group),
`renderImage` + `.image()` on the CPU canvas, `tex.image()` through readback.
A `renderTextures` collection on `ShaderSlotRegistry` for the pending-release
queue and the per-frame publish.

**Phase 2 — named samplers, in PyShader.** `ComputeImageInterface` and
`GraphicsInterface` (`PyShader/Sources/PyShader/Interface/`) carry a single
`contentBinding` today, so named extra textures start there: a
`textures: [(name: String, binding: Int, isTopDown: Bool)]` field, those names
in `EntrySignature`'s parameters, and the SPIR-V codegen that emits one
`sampler2D` per entry plus the `a(uv)` / `a_size` accessors. That is work in
the PyShader repo, on its own, with its own tests — a shader written against
the new interface compiling to SPIR-V that samples two images is the
deliverable, before anything in NucleantUI binds one.

**Phase 3 — textures as shader inputs, in the view layer.** `ShaderTextures`,
the `textures:` parameter on `.shader(_:)`, `Shader` and `VertexShader`,
`useTexture` on the registry (the `useCanvas` sibling) for `tex.shader(fx)`,
the descriptor writes for bindings 4+, and the rebuild-vs-rebind rules of
decision 8 (the borrowed containers of decision 11 came with phase 1). The
GLSL wrapper in
`ShaderSource.compute` gets the matching declarations in the same pass — not
because anything new is written in GLSL, but so the legacy inlet does not
quietly diverge from the interface PyShader compiles against.

**Phase 4 — if wanted later.** A live offscreen host; host-side writes into a
`RenderTexture` (reuse `ViewTexture.write(ioSurface:)` / `write(bgra:)`);
ping-pong pairs; the "combine multi RenderTexture" layer the concept sketches.

### Tests

In `Tests/NucleantUITests/` (no engine there, so the CPU path carries the
coverage):

* `renderImage` over known trees — a `Color`, text in a stack, a clipped
  rounded card — asserted pixel by pixel at scale 1 and 2, including the empty
  tree and a zero size.
* Parity: the same tree through `renderImage` and through the existing
  renderer harness (`RendererParityTests` style), so the offscreen path is not
  quietly drawing something else.
* Layout: the offscreen tree gets exactly the proposal it was given, and
  `sizeThatFits`-driven content lands where the window path puts it.
* Identity/lifetime without the GPU: an offscreen render runs no window pass,
  takes no paths out of `Invalidator.shared`, and `ShaderHost.current` is
  unchanged after it.

GPU-side there is no unit coverage to add honestly: the test target has no
`NucleantRenderEngine`. That part is verified in the demo — a screen that
renders a view to a texture, shows it through `tex.view()`, mixes two textures
in a shader, and asserts `tex.image()` against the same tree's `renderImage`
output (the one place the two paths must agree) — plus the resize/retire
cycling PROCESS §19 ran for effects: window resized through several sizes with
textures live, then navigated away and back, watching for leaks and crashes
under `NUCLEANT_SWIFTUI_TRACE_PERF=1`.

### Example

Not a toolbar demo: a real app. A **Compositor** example under `Examples/` —
layers (each a view tree rendered to a texture), a blend mode and a mix slider
per layer, the stack composited by one generated shader with the layer
textures as its named inputs, and an export that writes the result out through
`renderImage`. That exercises every piece of this plan the way an app would,
and the `Shader` gallery screen in the demo gets a texture-mixing effect
alongside it. Also tick `ImageRenderer`-equivalent and the new entries in
`Checklist.md`, and write the outcome up as the next PROCESS.md section when
it lands.

### Limits to write down (in the doc comments, not just here)

An offscreen tree does not re-render for its own state; it has no input and no
hit testing; nested shader/texture/canvas views are flattened or skipped;
`tex.image()` blocks on the GPU and is for export and tests, never a frame
path; a texture is the size it was made at, so a 4000×4000 one is a 64MB
image; and a texture sampled by a shader must not also be its output.

### Still to decide — your call

* Should `.texture()` ever **re-render by itself** when the model it reads
  changes (phase 4's live host), or stay explicit forever? Explicit is what
  phase 1 ships either way.
* `tex.view()` default fit: drawn at its pixel size like `Image`, or
  `resizable()`-style stretched to the frame? Leaning `Image`'s rule, for
  consistency.
* Does a shader-written `RenderTexture` (`renderTexture(shader:)` — a texture
  whose content *is* a generated shader, with no view at all) belong in phase
  3, or is reading textures enough for now?
* Whether `VertFragShaderNode` eventually gets the same treatment — our own
  graphics node in `Context` — or stays NucleantVulkan's until something
  actually needs a graphics-written texture sampled by a compute shader.
