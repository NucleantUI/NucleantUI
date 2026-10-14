# Moodboard

A collage of photos, notes and stickers arranged by hand.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Moodboard/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-moodboard", alt: "A board of tilted photos, sticky notes and round soft and yes! stickers, beside a list of boards.")
}

## Overview

@Image(source: "example-moodboard", alt: "A board of tilted photos, sticky notes and round soft and yes! stickers, beside a list of boards.")

What it shows:

- Cards dragged, pinched with `MagnifyGesture` and twisted with `RotateGesture` as a `.simultaneousGesture`.
- Double-click to reset, hold to pin with `.onLongPressGesture`.
- Lock Photos turning their input off with `.allowsHitTesting(false)`, and round stickers that take clicks only inside their circles with `.contentShape`.
- A Present mode where a click anywhere is “next”, through `.highPriorityGesture`.
- One `@FocusState` moving the keys between the board, the toolbar and the inspector, and the board handling keys with `.onKeyPress`.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Moodboard` folder:

```sh
cd Examples/Moodboard
swift build && .build/debug/Moodboard
```

## See Also

- <doc:ExampleApps>
