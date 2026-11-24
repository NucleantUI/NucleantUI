# Metronome

A metronome that clicks, every setting one of the framework's controls.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/Metronome/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "tutorial-metronome", alt: "120 BPM, Allegro, with Start and Tap, beside tempo, time, sound, subdivision, volume and preset settings.")
}

## Overview

@Image(source: "tutorial-metronome", alt: "120 BPM, Allegro, with Start and Tap, beside tempo, time, sound, subdivision, volume and preset settings.")

What it shows:

- An `@Observable` metronome whose settings are bound into it through `@Bindable`.
- A `Stepper` for the tempo that keeps stepping while a button is held, and `Slider`s for the tempo and the volume, with and without value labels.
- `Picker` in four styles: the meter as segments (a `ForEach` tagging each segment with its id), the subdivision as radio buttons, the sound as a pop-up menu (explicit `.tag`s and a `Divider`), and presets as an inline list over an optional selection.
- `Toggle` as a switch, a checkbox, and a button for Start and Stop.
- Clicks synthesised sample by sample by an `AudioProcessor` that NucleantAudio's `AudioPlayer` runs on the audio thread, which counts samples to the next tick, so the beat keeps the output's clock. The beat lights are read back at 60 Hz.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU, its sound played through Web Audio. Browsers keep a
page silent until it is used, so the clicks start with your first click or key press.
To build and run it yourself, it is a package of its own in the repository's
`Examples/Metronome` folder:

```sh
cd Examples/Metronome
swift build && .build/debug/Metronome
```

## See Also

- <doc:ExampleApps>
