//
//  Studio.swift
//  Backdrops
//
//  The look being designed, and the stills made from the same shader: one
//  per preset, rendered once into a texture each, and one of the current
//  look kept up to date by watching the shader's input — no view renders
//  either of them.
//

import NucleantUI
import Observation

@MainActor @Observable
final class Studio {
    let look: Look
    /// Each preset as a still, by name.
    let thumbnails: [String: RenderTexture]
    /// The current look as a still — what a still wallpaper of it shows.
    let still: RenderTexture
    @ObservationIgnored private var watching: ShaderObservation?

    init() {
        let look = Look(Preset.all[0])
        self.look = look
        var thumbnails: [String: RenderTexture] = [:]
        for preset in Preset.all {
            thumbnails[preset.name] = SpirvFunction(spirv: auroraModule, input: Look(preset))
                .renderTexture(size: Size(width: 56, height: 32), scale: 2)
        }
        self.thumbnails = thumbnails

        let shader = SpirvFunction(spirv: auroraModule, input: look)
        let still = shader.renderTexture(size: Size(width: 240, height: 135), scale: 2)
        self.still = still
        watching = shader.observe { shader in
            shader.render(into: still)
        }
    }
}
