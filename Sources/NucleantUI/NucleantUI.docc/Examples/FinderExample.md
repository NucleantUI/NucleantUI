# Finder

A file browser: nested disclosure groups over an observable file tree.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Finder/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-finder", alt: "A sidebar of places and tags beside a list of four folders with disclosure chevrons, dates, sizes and kinds.")
}

## Overview

@Image(source: "example-finder", alt: "A sidebar of places and tags beside a list of four folders with disclosure chevrons, dates, sizes and kinds.")

What it shows:

- Nested `DisclosureGroup`s built recursively, each bound to `$node.isExpanded` through `@Bindable`.
- A custom `DisclosureGroupStyle` that keeps the columns aligned while only the name indents.
- New Folder and Move to Trash editing the tree, and a download growing from a timer.
- A `.contextMenu` per row, ending in tag colours that close the menu through `@Environment(\.contextMenu)`.
- A sidebar of places with back and forward history.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Finder` folder:

```sh
cd Examples/Finder
swift build && .build/debug/Finder
```

## See Also

- <doc:ExampleApps>
