# Tasks

A list with a detail screen, both editing the same tasks through bindings.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Tasks/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-tasks", alt: "A Today list of six tasks, two of them done, under All, Active and Done filters and Add and Clear done buttons.")
}

## Overview

@Image(source: "example-tasks", alt: "A Today list of six tasks, two of them done, under All, Active and Done filters and Add and Clear done buttons.")

What it shows:

- `ForEach` over indices, each row bound into the array with `$tasks[index]`.
- A detail screen pushed by `NavigationLink` that edits through the same `Binding`.
- Deleting from the detail screen with a flag and `navigationRouter.pop()`.
- Filters as tap targets above the list.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Tasks` folder:

```sh
cd Examples/Tasks
swift build && .build/debug/Tasks
```

To build it step by step, follow <doc:Tasks>.

## See Also

- <doc:ExampleApps>
