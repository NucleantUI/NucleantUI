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
- A destination's page drawing its own back button: the stack's is hidden with `.navigationBarBackButtonHidden()`, and an ``ArrowBack``, the same chevron as a shape, filled with the destination's colour, takes its place in a `.navigation` toolbar item.
- One `@Observable` model owned through `@State`, changed through its methods: saving destinations, filtering the gallery by region or to the saved ones, the cards fading and moving under `withAnimation`.
- Posters drawn from shapes and gradients rather than images, in a `LazyVGrid` with adaptive columns.

## Its own back button

`DestinationScreen` swaps the stack's chevron for one in the destination's
sun colour: red over Kyoto, pale yellow over the Great Barrier Reef. The
bar, the title and the pop stay the stack's:

```swift
@View
struct DestinationScreen {
    let atlas: Atlas
    let destination: Destination
    @Environment(\.navigationRouter) private var router

    var body: some View {
        ScrollView {
            // The poster, the facts and the highlights.
        }
        .background(destination.palette.deep)
        .navigationTitle(destination.name)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ArrowBack()
                    .fill(destination.palette.sun)
                    .frame(width: 20, height: 20)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                    .onTapGesture { router?.pop() }
            }
        }
    }
}
```

`ArrowBack` in a 20-point frame is the stack's chevron, point for point,
and the 36-point square around it is the size of the stack's back button,
so the page's button sits and takes taps where the stack's would.

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
