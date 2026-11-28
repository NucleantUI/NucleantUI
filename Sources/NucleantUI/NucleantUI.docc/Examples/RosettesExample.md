# Rosettes

A guilloché designer: the woven line patterns of banknotes and watch dials, drawn with the Skia API itself.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Rosettes/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-rosettes", alt: "A green, a blue and a gold rosette of woven lines on a dark sheet, between a list of layers and the selected layer's sliders.")
}

## Overview

@Image(source: "example-rosettes", alt: "A green, a blue and a gold rosette of woven lines on a dark sheet, between a list of layers and the selected layer's sliders.")

What it shows:

- `SkiaCanvasView`: a view drawn with the Skia API by an object of your own. The drawing is a `SkiaRenderContext` that the `@Observable` design owns, so the view takes it by identity and the parent rebuilding with it changes nothing.
- Its `onAppear` setting up the `SkPaint`s once, and its `update` drawing on the canvas the views around it are drawn on, in paint order with them, cut by the `.cornerRadius` around it.
- Skia itself doing the drawing: a radial-gradient sheet, dashed guide circles (`SkDashPathEffect`), every line an `SkPath` stroked with a sweep-gradient `SkShader`, and crossings that add up (`.plus`) or darken (`.multiply`).
- Each layer's lines built once for its shape and kept, so only what changed is built again.
- `update` reading the design, so a `Stepper` or `Slider` on the selected layer, a segmented ink or paper `Picker`, a preset, or the engraving ticking on line by line from a `Task` draws it again, and nothing else does.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Rosettes` folder:

```sh
cd Examples/Rosettes
swift build && .build/debug/Rosettes
```

## See Also

- <doc:ExampleApps>
