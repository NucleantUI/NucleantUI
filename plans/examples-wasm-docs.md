# Display NucleantUI/Examples as seperate pages..

all Examples that works today for wasm should be on a Examples section
where each example has own sub page

# Shared NucleantUI + Rest

figure out how we can build the wasm versions sooo they all rely on same shared
components else each wasm example will take up too much space in total..

## Outcome (2026-10-14)

* Docs: `NucleantUI.docc/Examples/` — `ExampleApps.md` (a grid of every
  example, under "Example apps" on the landing page) and one article per
  example (`<Name>Example.md`, named apart from the tutorials): what it
  shows, a screenshot of it running in the browser, and a "Run in your
  browser" call to action to `/NucleantUI/examples/<Name>/`.
* 16 of the 18 examples run in the browser; Metronome and Sampler wait on
  a browser backend for NucleantAudio (macOS only today). Issues formatted
  its relative dates with `RelativeDateTimeFormatter`, which Foundation on
  wasm lacks; it now uses `Date.RelativeFormatStyle`
  (`.formatted(.relative(…))`), the same on every platform.
* `Scripts/build_examples_wasm.py` builds them; `build-docs.sh` calls it
  (`SKIP_EXAMPLES=1` to leave out). `--check` opens every page in headless
  Chrome and fails unless each starts and draws; `--serve` serves the site.

### Shared: dynamic linking (verified)

Each example on its own is ~70 MB of wasm, of which its own code is
86–524 KB (Issues 522 KB). Now:

* `shared/nucleant-shared.wasm` — the *main* module: the Swift runtime,
  Foundation, NucleantUI and everything under it, at fixed addresses,
  exporting the 923 symbols the examples use from it. 75 MB, 23.6 MB gzipped.
* `<Example>/<Example>.wasm` — a *side* module (`wasm-ld -shared
  --experimental-pic`): only the example's own objects. 29–150 KB gzipped.
* The whole site is 29 MB, instead of ~350 MB for 16 standalone builds; the
  browser caches the shared module across examples.

Why this shape, and the catches:

* The SDK's Swift stdlib/Foundation and our own code are compiled PIC
  already; wasi-libc (and the prebuilt Skia/ThorVG/shaderc libs) are not —
  so the shared part has to be the main module (fixed addresses), and the
  apps the PIC side modules. The swift driver refuses `-emit-library` for
  wasm; wasm-ld is called directly.
* Several Swift images in one process work: each side module links its own
  `swiftrt.o`, whose constructor registers its metadata sections with the
  runtime (`swift_addNewDSOImage`). Checked: cross-module generics,
  conformances both ways, `as? any P`, type names.
* wasm-ld 21 bug: in side modules the runtime relocation for
  `R_WASM_MEMORY_ADDR_LOCREL_I32` (Swift's relative pointers) stores
  `__memory_base + (S - P)` instead of `S - P`. Workaround: the side
  module's data goes at address 0 (the main module is linked with
  `--global-base` above it; a 4 KB guard object keeps real data off
  address 0), where that relocation is right. `--emit-relocs`, which would
  allow fixing the places up instead, crashes wasm-ld on our objects.
* All examples are targets of one generated package
  (`.build/examples-wasm/package`, sources symlinked) — one build of
  NucleantUI for all, so the shared module and every side module come from
  the same objects. Separate example packages sharing a scratch path
  rebuilt the dependencies per example.
* `NucleantApplication/Web/nucleant-app.js`: `runNucleantApp({ app })`
  loads the side module after the main module's `_initialize`
  (`loadSideModule`: dylink.0, GOT.mem/GOT.func, table growth, relocations,
  constructors), and any `.gz` URL is inflated in the browser.

### Fixed along the way: a canvas resized mid-frame

In a page smaller than an example's window (Dashboard, Reader), WebGPU
rejected the first frames: the page fits the canvas while a frame is
suspended under JSPI, so that frame's canvas texture came back at the new
size after its swapchain image was acquired at the old one (the scissor no
longer fit the render area). `nucleant-app.js` now applies a canvas's new
drawing-buffer size between calls into the module — as the `before` step
of the `nucleant_window_resized` call — the way a native window's drawable
changes between frames. `--check` runs at 1024×768 to cover it.
