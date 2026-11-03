# Examples in Xcode

One Xcode project with every example as an app target, for the platforms
`swift run` cannot reach: iOS on a device or the simulator, and macOS as a
proper `.app`. Pick the example by its scheme and the platform by the
destination.

Each target compiles its example's sources where they are,
`../<Name>/Sources/<Name>`, unchanged, and depends on the enclosing
checkout as a local package (`path: ../..`), as the example's own
`Package.swift` does. The Nucleant packages under it resolve the way
`swift build` resolves them: GitHub, or the sibling checkouts with
`NUCLEANT_LOCAL_DEV=1` (see `localDev` in [Package.swift](../../Package.swift)).

## Building

Open `Examples.xcodeproj`, pick an example's scheme and a destination, and
run. The first build stops on the `NucleantUIMacros` compiler plugin
(`@View`, `#viewID`) until you choose *Trust & Enable*. You answer that once
per machine.

From the command line, where `-skipMacroValidation` stands in for the trust
prompt:

```sh
cd Examples/xcode
xcodebuild -scheme Calculator -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation build
xcodebuild -scheme Calculator -destination 'platform=macOS' -skipMacroValidation build
```

### Signing

The simulator and macOS need nothing: the targets sign to run locally. A
real iOS device needs a team. Set it under *Signing & Capabilities*, or as
`DEVELOPMENT_TEAM` in the `Example` template in `project.yml` so it
survives regeneration.

## What is in it

Every example except two:

- **AnimatableShader** and **Backdrops** are left out. Their shaders are
  compiled to SPIR-V by PyShader's build plugin, which implements only
  SwiftPM's `BuildToolPlugin`. Xcode needs `XcodeBuildToolPlugin` to run a
  plugin for an app target.

Two targets need more than their sources:

- **Compositor** also depends on `NucleantUI_PyShader`, from GitHub as in
  its package.
- **Icons** carries its `Material` folder as a folder resource, as the
  package's `.copy("Material")` does. It also gets
  [Support/BundleModule.swift](Support/BundleModule.swift), the
  `Bundle.module` that SwiftPM generates for a package target and Xcode
  does not generate for an app target.

**Metronome** and **Sampler** also link the `NucleantAudio` product.

## Known problems (2026-11-03)

All 19 targets build for macOS, and 17 build for the iOS Simulator too.

- **Metronome and Sampler do not build for iOS.** NucleantAudio has macOS
  and Windows backends only (`AudioPlayer+MacOS.swift`,
  `AudioFileLoader+MacOS.swift`, …), so `AudioBackend` and `decode` are
  missing on iOS.
- **Nothing runs in the iOS 26 Simulator yet.** MoltenVK 1.2.11 aborts in
  `vkCreateInstance`, called from NucleantVulkan's `makeMetalInstance`: the
  simulator's Metal driver asserts `MTLPixelFormatInvalid is not supported
  on this device` while MoltenVK lists its formats. This is the engine
  starting up, before any example code runs, so it is the same for every
  example. A real device is untested.

## Changing the project

`project.yml` is the source. The `.xcodeproj` is generated from it with
[xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
and checked in, so you can open it without installing anything:

```sh
cd Examples/xcode && xcodegen
```

Edit the YAML, not the project: the next `xcodegen` run overwrites the
project. A new example that needs only NucleantUI is one entry under
`targets:`:

```yaml
  MyExample:
    templates: [Example, ExampleSources]
```
