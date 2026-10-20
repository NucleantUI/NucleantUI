# AnimatableShader

PyShader scenes driven by `withAnimation`.

@Metadata {
    @CallToAction(url: "/NucleantUI/examples/AnimatableShader/", purpose: link, label: "Run in your browser")
    @PageImage(purpose: card, source: "example-animatableshader", alt: "A tilted blue box with orange rings radiating from it, under a playhead readout, with four scene tabs along the bottom.")
}

## Overview

@Image(source: "example-animatableshader", alt: "A tilted blue box with orange rings radiating from it, under a playhead readout, with four scene tabs along the bottom.")

What it shows:

- Four PyShader `.py` shaders compiled to SPIR-V by PyShader's build plugin and run through ``SpirvFunction``, with their clock replaced by a `Clock` class input holding the playhead.
- An `Animatable` view with the playhead as its `animatableData`, so `withAnimation` drives the shader: a tap plays it forward and the completion rewinds it.
- A glow that follows each tap as an `Animatable` point under a custom wiggle animation.
- A tab bar whose highlight slides over first, the scene following with a `.push(from:)` transition.

## Run it

The app runs in your browser from the button above: it is the same Swift code, built for
WebAssembly and drawn with WebGPU. To build and run it yourself, it is a package of its
own in the repository's `Examples/AnimatableShader` folder:

```sh
cd Examples/AnimatableShader
swift build && .build/debug/AnimatableShader
```

To build it step by step, follow <doc:AnimatableShader>.

## See Also

- <doc:ExampleApps>
