# Bookmarks

A reading list laid out by custom layouts.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Bookmarks/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-bookmarks", alt: "A sidebar with a cloud of tags beside a shelf of bookmark cards and an empty inspector.")
}

## Overview

@Image(source: "example-bookmarks", alt: "A sidebar with a cloud of tags beside a shelf of bookmark cards and an empty inspector.")

What it shows:

- The shelf as a custom `Layout` — a masonry and a list — with its column width as `animatableData`, so switching morphs every card into its row.
- Tags as a `FlowLayout` cloud or a `VStackLayout` list through one `AnyLayout`.
- Removable tag chips in the inspector, and actions in an equal-width stack.
- Preferences going up: the shelf naming itself to the window bar, and every card adding to the totals in the status bar.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Bookmarks` folder:

```sh
cd Examples/Bookmarks
swift build && .build/debug/Bookmarks
```

To build it step by step, follow <doc:Bookmarks>.

## See Also

- <doc:ExampleApps>
