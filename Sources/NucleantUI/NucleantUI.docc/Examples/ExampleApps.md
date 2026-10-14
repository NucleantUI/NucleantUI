# Examples

Complete apps built with NucleantUI, each running live in your browser.

@Metadata {
    @PageImage(purpose: card, source: "example-photos", alt: "A sidebar of albums beside a grid of landscape thumbnails under a September 2026 header and a zoom slider.")
}

## Overview

Each of these is a small but complete app from the repository's `Examples`
folder: a calculator, a task list, a file browser, a photo library, games
and editors. Every page below shows what the app is there to demonstrate,
and opens it in your browser: the same Swift that runs as a window on macOS,
built for WebAssembly and drawn with WebGPU. You need a browser with WebGPU
— Chrome or Edge 113 or later, Safari 26, or Firefox 141 on Windows.

@Links(visualStyle: detailedGrid) {
    - <doc:CalculatorExample>
    - <doc:TasksExample>
    - <doc:SketchExample>
    - <doc:DashboardExample>
    - <doc:TwentyFortyEightExample>
    - <doc:PomodoroExample>
    - <doc:FlashcardsExample>
    - <doc:AnimatableShaderExample>
    - <doc:FinderExample>
    - <doc:PhotosExample>
    - <doc:BookmarksExample>
    - <doc:MoodboardExample>
    - <doc:MindMapExample>
    - <doc:ReaderExample>
    - <doc:CompositorExample>
}

### One download for every example

Built on its own, each example would be a WebAssembly module of about 70 MB,
of which its own code is a few hundred kilobytes: the rest is the Swift
runtime, Foundation, NucleantUI and the renderer under it, the same in every
app. So the examples are linked the way native apps link a shared library.
One shared module holds everything they have in common, and each example is
a small side module linked against it, which the page loads into the shared
one at startup. Your browser downloads the shared module once, with the
first example you open, and every other example after it is only its own
code.

## Topics

### First apps

- <doc:CalculatorExample>
- <doc:TasksExample>
- <doc:SketchExample>
- <doc:DashboardExample>
- <doc:TwentyFortyEightExample>
- <doc:PomodoroExample>

### Motion and shaders

- <doc:FlashcardsExample>
- <doc:AnimatableShaderExample>
- <doc:CompositorExample>

### Collections and layout

- <doc:FinderExample>
- <doc:PhotosExample>
- <doc:BookmarksExample>

### Input, navigation and canvases

- <doc:MoodboardExample>
- <doc:MindMapExample>
- <doc:ReaderExample>
