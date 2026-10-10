//
//  Document.swift
//  Compositor
//
//  The stack being composited: a document of layers, each a view tree
//  rendered into a `RenderTexture` of its own.
//
//  A layer is a class, not a struct in an array: its texture is an object
//  with GPU memory behind it, and the whole point of holding one is that it
//  outlives the views that made it. Replacing a layer value would throw its
//  image away and draw it again — so a layer is changed through its own
//  methods, and only `redraw()` touches the texture.
//

import Foundation
import NucleantUI

/// Every layer is this size, in points, at one pixel per point. A texture is
/// the size it was made at and is never resized, which is why this is one
/// constant rather than the stage's current frame.
let canvasSize = Size(width: 420, height: 300)

/// Width ÷ height. The textures are fixed at `canvasSize`, but every view
/// showing one is fitted to the room it has at these proportions, so the
/// window can be any shape without the composite being stretched.
let canvasAspect = canvasSize.width / canvasSize.height

/// What a layer draws. Each is a real view tree — shapes, gradients, a
/// `ForEach` — not an image file: the texture is how a tree becomes pixels.
enum LayerArtwork: String, CaseIterable, Hashable {
    case wash, rings, bars, grid, label, stripes, dots, burst, waves

    var name: String {
        switch self {
        case .wash:    return "Wash"
        case .rings:   return "Rings"
        case .bars:    return "Bars"
        case .grid:    return "Grid"
        case .label:   return "Label"
        case .stripes: return "Stripes"
        case .dots:    return "Dots"
        case .burst:   return "Burst"
        case .waves:   return "Waves"
        }
    }
}

/// How a layer picks its colours.
///
/// The same artwork, the same slider, two readings of it: a hue around the
/// wheel, or a level from black to white. Grey layers are what make the blend
/// modes legible — a screen or a difference between two coloured layers is
/// hard to read, and between two grey ones it is obvious.
enum LayerTone: String, CaseIterable, Hashable {
    case colour, grey

    var name: String {
        switch self {
        case .colour: return "Colour"
        case .grey:   return "Grey"
        }
    }

    /// What the one slider means under this tone, for the inspector's label.
    var valueName: String {
        switch self {
        case .colour: return "Hue"
        case .grey:   return "Level"
        }
    }
}

/// How a layer is mixed into the stack below it. The names are the usual
/// ones; what each becomes is one line of generated PyShader
/// (`CompositeShader`).
enum LayerBlend: String, CaseIterable, Hashable {
    case normal, add, screen, multiply, difference

    var name: String {
        switch self {
        case .normal:     return "Normal"
        case .add:        return "Add"
        case .screen:     return "Screen"
        case .multiply:   return "Multiply"
        case .difference: return "Difference"
        }
    }
}

/// One layer: what it draws, how it is mixed, and the texture it drew into.
///
/// `artwork`, `hue` and `detail` change what the tree looks like, so they
/// need a `redraw()` — the texture is a snapshot and nothing re-renders it by
/// itself. `blend` changes the generated shader, and `mix` is a
/// `ShaderArgument`, so neither touches the texture at all.
@MainActor
@Observable
final class CompositorLayer: Identifiable {
    let id = UUID()
    var name: String

    private(set) var artwork: LayerArtwork
    private(set) var tone: LayerTone
    /// The one colour slider: a hue under `.colour`, a level under `.grey`.
    private(set) var hue: Double
    private(set) var detail: Double

    var blend: LayerBlend
    var mix: Double
    var isVisible = true

    /// The layer's pixels. Made once and kept: the shader samples this image
    /// every frame, and a redraw writes into the same one.
    let texture: RenderTexture

    init(
        name: String,
        artwork: LayerArtwork,
        tone: LayerTone = .colour,
        hue: Double,
        detail: Double = 0.5,
        blend: LayerBlend = .normal,
        mix: Double = 1
    ) {
        self.name = name
        self.artwork = artwork
        self.tone = tone
        self.hue = hue
        self.detail = detail
        self.blend = blend
        self.mix = mix
        self.texture = renderTexture(size: canvasSize) {
            LayerArt(artwork: artwork, palette: LayerPalette(tone: tone, value: hue), detail: detail)
        }
    }

    /// The shader's name for this layer. Positional — `l0` is the bottom —
    /// because the stack's order is what the generated source is built from.
    func samplerName(at index: Int) -> String { "l\(index)" }

    // MARK: - Editing

    /// Change the tree and draw it again. One call, because the two always go
    /// together: a texture nobody re-renders still holds the old pixels, and
    /// an app that forgets this looks broken in a way nothing reports.
    func set(
        artwork: LayerArtwork? = nil,
        tone: LayerTone? = nil,
        hue: Double? = nil,
        detail: Double? = nil
    ) {
        self.artwork = artwork ?? self.artwork
        self.tone = tone ?? self.tone
        self.hue = hue ?? self.hue
        self.detail = detail ?? self.detail
        redraw()
    }

    /// Re-evaluate the tree into the same image. `update { }` replaces the
    /// view the texture renders, which is what makes the new values show.
    func redraw() {
        let art = self.art
        texture.update { art }
    }

    /// This layer alone, as a tree — what the texture holds, and what the
    /// CPU export draws instead of reading the image back.
    var art: LayerArt {
        LayerArt(
            artwork: artwork,
            palette: LayerPalette(tone: tone, value: hue),
            detail: detail
        )
    }
}

/// The stack, bottom layer first.
@MainActor
@Observable
final class CompositorDocument {

    private(set) var layers: [CompositorLayer]
    /// The layer the inspector edits. An id, not the object: the layer it
    /// names may be removed.
    var selection: UUID?

    /// Pixels per point for the export. The stage is one point per pixel;
    /// an export at 2 is the same trees drawn twice as large, not the
    /// textures scaled up.
    var exportScale: Double = 2

    init() {
        let layers = [
            CompositorLayer(name: "Backdrop", artwork: .wash, hue: 0.58, detail: 0.5),
            CompositorLayer(name: "Rings", artwork: .rings, hue: 0.92, detail: 0.45, blend: .screen, mix: 0.85),
            CompositorLayer(name: "Readout", artwork: .bars, hue: 0.13, detail: 0.6, blend: .add, mix: 0.6),
            // One grey layer from the start, so the two tones are side by
            // side rather than something to go looking for.
            CompositorLayer(name: "Grain", artwork: .dots, tone: .grey, hue: 0.4,
                            detail: 0.7, blend: .multiply, mix: 0.45),
        ]
        self.layers = layers
        self.selection = layers.last?.id
    }

    var selected: CompositorLayer? {
        layers.first { $0.id == selection }
    }

    /// The visible layers, bottom first — the stack the shader is generated
    /// for. Hiding a layer takes it out of the shader entirely, which is a
    /// recompile; the mix sliders are arguments and are not.
    var stack: [CompositorLayer] {
        layers.filter(\.isVisible)
    }

    func add() {
        let artwork = LayerArtwork.allCases[layers.count % LayerArtwork.allCases.count]
        let layer = CompositorLayer(
            name: "\(artwork.name) \(layers.count + 1)",
            artwork: artwork,
            tone: layers.count.isMultiple(of: 3) ? .grey : .colour,
            hue: Double(layers.count) * 0.17,
            blend: .screen,
            mix: 0.7
        )
        layers.append(layer)
        selection = layer.id
    }

    func remove(_ layer: CompositorLayer) {
        layers.removeAll { $0 === layer }
        if selection == layer.id { selection = layers.last?.id }
    }

    /// Move a layer up or down the stack. The order is the shader's order, so
    /// this regenerates it.
    func move(_ layer: CompositorLayer, by offset: Int) {
        guard let from = layers.firstIndex(where: { $0 === layer }) else { return }
        let to = from + offset
        guard layers.indices.contains(to) else { return }
        layers.swapAt(from, to)
    }
}
