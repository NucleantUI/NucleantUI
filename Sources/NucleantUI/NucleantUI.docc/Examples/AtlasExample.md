# Atlas

A travel guide whose pages zoom out of their cards.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Atlas/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-atlas", alt: "A grid of destination posters — Lofoten, Kyoto, Patagonia, Sahara — under region filters.")
}

## Overview

@Image(source: "example-atlas", alt: "A grid of destination posters — Lofoten, Kyoto, Patagonia, Sahara — under region filters.")

What it shows:

- A destination's page zooming out of its card and back into it: the card marked with `.matchedTransitionSource(id:in:)`, clipped to its corners with its colour behind, and the page asking for `.navigationTransition(.zoom(sourceID:in:))`, both naming one `@Namespace` the root owns.
- A highlight's page sliding in the stack's `.automatic` way, over the destination page.
- One `@Observable` model owned through `@State`, changed through its methods: saving destinations, filtering the gallery by region or to the saved ones, the cards fading and moving under `withAnimation`.
- Posters drawn from shapes and gradients rather than images, in a `LazyVGrid` with adaptive columns.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Atlas` folder:

```sh
cd Examples/Atlas
swift build && .build/debug/Atlas
```

## See Also

- <doc:NavigatingBetweenScreens>
- <doc:ExampleApps>
