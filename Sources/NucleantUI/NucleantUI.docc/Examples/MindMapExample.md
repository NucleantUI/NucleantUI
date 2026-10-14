# MindMap

A mind map whose topics are placed by position and tidied with animation.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/MindMap/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-mindmap", alt: "A Spring Launch topic with coloured branches to Marketing, Risks, Product, Support and Metrics, and a sticky note above.")
}

## Overview

@Image(source: "example-mindmap", alt: "A Spring Launch topic with coloured branches to Marketing, Risks, Product, Support and Metrics, and a sticky note above.")

What it shows:

- Every topic placed by `.position`, so its branch meets it in the middle whatever its title.
- Topics dragged with their whole branch, and the canvas dragged to pan.
- Tidy Up rewriting every point inside `withAnimation`, the branches following as a `Shape` whose ends are its `animatableData`.
- Folding a branch behind a badge, Tab and Return adding topics through one `@FocusState`, and arrow keys walking the map.
- The canvas's `.contextMenu { location in … }`, which puts a note down where the menu was opened.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/MindMap` folder:

```sh
cd Examples/MindMap
swift build && .build/debug/MindMap
```

## See Also

- <doc:ExampleApps>
