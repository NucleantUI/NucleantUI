# Calculator

A keypad of custom controls over a value-type engine.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Calculator/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-calculator", alt: "A display reading 0 over a keypad of round grey and orange buttons.")
}

## Overview

@Image(source: "example-calculator", alt: "A display reading 0 over a keypad of round grey and orange buttons.")

What it shows:

- Custom buttons built from a `DragGesture`: a pressed state while held, and the action fires on release inside.
- The arithmetic is a value-type engine; the view only sends it key presses and shows its display.
- Rows of keys that share the width, with the zero key spanning two.
- A window held to its content's size: `.windowResizability(.contentSize)` and `.windowIdealSize(.maximum)`.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Calculator` folder:

```sh
cd Examples/Calculator
swift build && .build/debug/Calculator
```

To build it step by step, follow <doc:Calculator>.

## See Also

- <doc:ExampleApps>
