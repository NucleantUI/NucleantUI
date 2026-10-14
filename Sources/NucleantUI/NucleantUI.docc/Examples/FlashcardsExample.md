# Flashcards

A study deck where every part of the animation API does a job.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Flashcards/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-flashcards", alt: "A card asking for the capital of Canada, over Missed it, Reveal and Knew it buttons.")
}

## Overview

@Image(source: "example-flashcards", alt: "A card asking for the capital of Canada, over Missed it, Reveal and Knew it buttons.")

What it shows:

- A card that follows a `DragGesture` and springs back with `withAnimation(.bouncy)`, or is flung off with `withAnimation(_:_:completion:)`, whose completion deals the next card.
- The next card arriving through a one-element `ForEach`, so `.transition` applies.
- A flip as an `Animatable` view that swaps faces halfway, and a head-shake `AnimatableModifier` under `.animation(_:value:)`.
- An animatable `Shape` progress ring, numbers that count through their `animatableData`, and a `TimelineView` clock.
- A results screen whose score rolls up through a `CustomAnimation`, its rows staggered with `.delay`.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Flashcards` folder:

```sh
cd Examples/Flashcards
swift build && .build/debug/Flashcards
```

To build it step by step, follow <doc:Flashcards>.

## See Also

- <doc:ExampleApps>
