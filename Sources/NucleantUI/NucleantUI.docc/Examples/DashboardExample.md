# Dashboard

Charts, stat tiles and a feed, drawn with shapes and gradients.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Dashboard/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-dashboard", alt: "An overview of four stat tiles over a traffic line chart, a sources ring chart, a sessions bar chart and an activity feed.")
}

## Overview

@Image(source: "example-dashboard", alt: "An overview of four stat tiles over a traffic line chart, a sources ring chart, a sessions bar chart and an activity feed.")

What it shows:

- Line, bar and ring charts drawn with `PathShape`, gradients and `.relativeSize`.
- Stat tiles and a segmented period switch that redraws every chart.
- A scrolling feed beside the charts.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/Dashboard` folder:

```sh
cd Examples/Dashboard
swift build && .build/debug/Dashboard
```

## See Also

- <doc:ExampleApps>
