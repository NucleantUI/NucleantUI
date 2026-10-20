# Compositor

A layer compositor: view trees rendered into textures and blended by a generated shader.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Compositor/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-compositor", alt: "Four layers with blend controls beside a stage of glowing bars and rings composited from them, with each layer's texture below.")
}

## Overview

@Image(source: "example-compositor", alt: "Four layers with blend controls beside a stage of glowing bars and rings composited from them, with each layer's texture below.")

What it shows:

- Every layer a view tree rendered into a `RenderTexture` the document holds, shown through `tex.view()` and sampled by a shader.
- Nine artworks that take their colours from a palette, so one slider re-tints the whole tree.
- The stack composited by one PyShader module generated from it and compiled while the app runs by `PyShaderFunction` (NucleantUI_PyShader): a fold per layer with that layer's blend mode, the layer textures passed as named inputs.
- Adding, hiding or reordering a layer writes a new module; the mix sliders are its `Mix` class input, read through observation, and only dispatch it again.
- An export that flattens the same trees through `renderImage` at 1×, 2× and 3×.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Compositor` folder:

```sh
cd Examples/Compositor
swift build && .build/debug/Compositor
```

## See Also

- <doc:ExampleApps>
