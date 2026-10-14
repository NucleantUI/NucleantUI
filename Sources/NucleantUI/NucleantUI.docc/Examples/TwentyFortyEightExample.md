# TwentyFortyEight

The 2048 game: swipes drive a value-type board.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/TwentyFortyEight/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-twentyfortyeight", alt: "A 4 by 4 board with a 2 and a 4 tile, a score and best counter, a New game button and arrow buttons.")
}

## Overview

@Image(source: "example-twentyfortyeight", alt: "A 4 by 4 board with a 2 and a 4 tile, a score and best counter, a New game button and arrow buttons.")

What it shows:

- A swipe read from `DragGesture.onEnded` and its `translation`.
- The whole game in one `@State` holding a value-type board.
- Arrow buttons for playing with a mouse.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/TwentyFortyEight` folder:

```sh
cd Examples/TwentyFortyEight
swift build && .build/debug/TwentyFortyEight
```

## See Also

- <doc:ExampleApps>
