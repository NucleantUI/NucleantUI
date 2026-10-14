# Reader

An e-book reader whose navigation bar shows where it helps and hides where it's in the way.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Reader/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-reader", alt: "A library with Pride and Prejudice to continue reading over a shelf of three books.")
}

## Overview

@Image(source: "example-reader", alt: "A library with Pride and Prejudice to continue reading over a shelf of three books.")

What it shows:

- A library under a navigation bar, and a book's page with the bar hidden so the cover's colour runs to the top.
- The reading screen titled with the chapter by `.navigationTitle`, where a tap hides the bar with `.toolbarVisibility`.
- Screens pushed by value through `.navigationDestination(for:)`.
- The place recorded by `.onChange(of:initial:)`, and the time in each chapter counted by a `.task(id:)` that restarts on every turn.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Reader` folder:

```sh
cd Examples/Reader
swift build && .build/debug/Reader
```

## See Also

- <doc:ExampleApps>
