# Photos

Twenty thousand photos in lazy grids and stacks.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Photos/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-photos", alt: "A sidebar of albums beside a grid of landscape thumbnails under a September 2026 header and a zoom slider.")
}

## Overview

@Image(source: "example-photos", alt: "A sidebar of albums beside a grid of landscape thumbnails under a September 2026 header and a zoom slider.")

What it shows:

- The library as a `LazyVGrid` with `.adaptive` columns sized by a zoom `Slider`, a `Section` per month with its header pinned.
- Days as a sideways `LazyHGrid` of three rows, each day's header a pinned column.
- Albums as a `LazyHStack` strip of covers over a `LazyVStack` of rows.
- An info pane laid out by a `Grid`.
- Only the tiles near the visible part are ever built.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Photos` folder:

```sh
cd Examples/Photos
swift build && .build/debug/Photos
```

To build it step by step, follow <doc:Photos>.

## See Also

- <doc:ExampleApps>
