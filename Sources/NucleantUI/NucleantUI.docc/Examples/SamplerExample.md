# Sampler

A drum-pad sampler: eight synthesised sounds, a waveform drawn by a shader, trim and gain, and real playback.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Sampler/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-sampler", alt: "Eight drum pads over the selected kick's waveform, with gain, start and end faders.")
}

## Overview

@Image(source: "example-sampler", alt: "Eight drum pads over the selected kick's waveform, with gain, start and end faders.")

What it shows:

- `@Observable` models as the source of truth (`Sample`, `SampleBank`). Views hold plain references and read properties in `body`, so a write anywhere (a drag, a button, a background analysis finishing, the playhead) rebuilds exactly the views that read it.
- `@Bindable` faders: the gain fader takes `$sample.gain`.
- A waveform drawn by a `Shader`: the envelope's two float arrays, the gain, the trim and the playhead go to the GPU as `ShaderArgument`s, and the shader runs again whenever one of them changes.
- The CPU side in plain Swift: synthesis, and a min/max reduction run in parallel with `concurrentPerform`.
- Real playback through NucleantAudio's `AudioPlayer`, with a 60 Hz playhead written to the model from a task.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU, its sound played through Web Audio. Browsers keep a
page silent until it is used, so the sound starts with your first click or key press.
To build and run it yourself, it is a package of its own in the repository's
`Examples/Sampler` folder:

```sh
cd Examples/Sampler
swift build && .build/debug/Sampler
```

## See Also

- <doc:ExampleApps>
