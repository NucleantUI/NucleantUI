# Sketch

A drawing canvas: strokes collected from a drag, with colours, brushes and undo.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Sketch/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-sketch", alt: "Red, blue, green and purple strokes on a dark canvas, under a toolbar of colours, brush sizes, Undo and Clear.")
}

## Overview

@Image(source: "example-sketch", alt: "Red, blue, green and purple strokes on a dark canvas, under a toolbar of colours, brush sizes, Undo and Clear.")

What it shows:

- A `DragGesture` collecting points into a `PathShape` stroke.
- Finished strokes kept as reusable child views.
- Colour and brush pickers, and undo.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Sketch` folder:

```sh
cd Examples/Sketch
swift build && .build/debug/Sketch
```

To build it step by step, follow <doc:Sketch>.

## See Also

- <doc:ExampleApps>
