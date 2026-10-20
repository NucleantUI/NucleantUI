//
//  BackdropsApp.swift
//  Backdrops
//
//  Design an animated backdrop: pick a preset, then tune its colours,
//  brightness, speed and scale.
//
//  The backdrop is a PyShader compute shader compiled to SPIR-V by the build
//  (`Shaders/aurora.py`, listed in `pyshader.toml`) and run through
//  `SpirvFunction`. Its input is the `Look` model itself. Moving a slider
//  changes the model, and the shader reads the change through observation:
//  the screen holding the backdrop never reads the model, so it is never
//  rebuilt for it.
//

import NucleantUI

enum Theme {
    static let panel = Color.dynamic(light: Color(hex: 0xF4F4F6), dark: Color(hex: 0x1A1B1F))
    static let card = Color.dynamic(light: Color.white, dark: Color(hex: 0x24252B))
    static let faint = Color.dynamic(light: Color(white: 0, opacity: 0.45), dark: Color(white: 1, opacity: 0.45))
    static let accent = Color(hex: 0x4C8DFF)
}

@View
struct RootView {
    @State private var look = Look(Preset.all[0])

    var body: some View {
        HStack(spacing: 0) {
            Shader(SpirvFunction(spirv: auroraModule, input: look))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ControlsPanel(look: look)
                .frame(width: 280)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.panel)
        }
    }
}

@main
struct BackdropsApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Backdrops") {
            RootView()
        }
        .defaultSize(width: 960, height: 600)
    }
}
