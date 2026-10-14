# Issues

An issue tracker: a sidebar, a sortable table and an inspector form.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Issues/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-issues", alt: "A sidebar of issue views and projects beside a table of seventeen issues sorted by last update, and an empty inspector.")
}

## Overview

@Image(source: "example-issues", alt: "A sidebar of issue views and projects beside a table of seventeen issues sorted by last update, and an empty inspector.")

What it shows:

- A `.sidebar` `List` whose `Section`s hold tagged rows with `.badge` counts, and the projects as an `OutlineGroup`.
- The issues in a `Table` sorted by a `KeyPathComparator` that a header click changes, with columns resized from their header edges.
- A set for the selection (⌘- and ⇧-click, ⇧-arrows, ⌘A), and `.contextMenu(forSelectionType:)` with Status, Priority and Assignee submenus for it.
- Delete through `.onDeleteCommand`, and a double click that opens an issue full-window.
- An inspector `Form` in `.grouped` style over the selection, showing “Mixed” when several differ, and Settings as a `.columns` `Form`.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Issues` folder:

```sh
cd Examples/Issues
swift build && .build/debug/Issues
```

To build it step by step, follow <doc:Issues>.

## See Also

- <doc:ExampleApps>
