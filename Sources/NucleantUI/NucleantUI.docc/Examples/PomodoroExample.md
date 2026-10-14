# Pomodoro

A focus timer with an analog clock, progress rings and a saved plan.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Pomodoro/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-pomodoro", alt: "A 25:00 focus timer in a ring, an analog clock, and an empty plan panel with a field to add a task.")
}

## Overview

@Image(source: "example-pomodoro", alt: "A 25:00 focus timer in a ring, an analog clock, and an empty plan panel with a field to add a task.")

What it shows:

- A Foundation `Timer` on the main run loop writing `@State` once a second.
- An analog clock and progress rings drawn as `PathShape`s.
- A plan of tasks saved between launches: an `@Observable` model owned through `@State` by a panel the ticker rebuilds every second, so the model is made once, not once a second.
- `@Preview` functions for the clock face, the rings, the plan panel and the whole screen.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Pomodoro` folder:

```sh
cd Examples/Pomodoro
swift build && .build/debug/Pomodoro
```

## See Also

- <doc:ExampleApps>
