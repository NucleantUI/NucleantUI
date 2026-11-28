//
//  Design.swift
//  Rosettes
//
//  A rosette is layers of engraved lines. Every line of a layer is the same
//  closed curve — a circle whose radius swings in and out `petals` times on
//  the way round — turned a little further than the one before, so the
//  lines cross and weave. The design is an `@Observable` class changed
//  through its own methods; the layers are values inside it.
//

import NucleantUI
import Observation

/// One layer of lines.
struct Layer: Identifiable, Equatable {
    let id: Int
    var name: String
    /// How many lines the layer engraves.
    var lines: Int
    /// How many times a line swings out and in on the way round.
    var petals: Int
    /// The line's middle radius, as a share of the rosette's.
    var radius: Double
    /// How far a line swings either side of its middle, as a share of the
    /// rosette's radius.
    var depth: Double
    /// How far the lines are spread round: 1 turns the last line a whole
    /// petal from the first, so the layer weaves evenly.
    var spread: Double
    /// Stroke width, in points.
    var width: Double
    /// The ink's hue, 0…1 round the color wheel.
    var hue: Double
    var isVisible = true

    static let lineRange = 1...96
    static let petalRange = 1...36

    /// The same layer under another id.
    func withID(_ id: Int) -> Layer {
        Layer(
            id: id, name: name, lines: lines, petals: petals, radius: radius, depth: depth,
            spread: spread, width: width, hue: hue, isVisible: isVisible
        )
    }
}

/// How overlapping lines mix.
enum Ink: CaseIterable, Identifiable, Hashable {
    /// Each line over the last.
    case ink
    /// Lines add up where they cross, and glow.
    case glow

    var id: Self { self }

    var name: String {
        switch self {
        case .ink: return "Ink"
        case .glow: return "Glow"
        }
    }
}

/// What the rosette is engraved on.
enum Paper: CaseIterable, Identifiable, Hashable {
    case night, cream, slate

    var id: Self { self }

    var name: String {
        switch self {
        case .night: return "Night"
        case .cream: return "Cream"
        case .slate: return "Slate"
        }
    }

    /// The middle of the sheet and its edge, (r, g, b) 0…1.
    var colors: (center: SIMD3<Double>, edge: SIMD3<Double>) {
        switch self {
        case .night: return (SIMD3(0.09, 0.10, 0.16), SIMD3(0.01, 0.01, 0.03))
        case .cream: return (SIMD3(0.99, 0.96, 0.89), SIMD3(0.88, 0.83, 0.72))
        case .slate: return (SIMD3(0.30, 0.33, 0.37), SIMD3(0.14, 0.15, 0.18))
        }
    }
}

/// A starting point: a name and its layers.
struct Preset: Identifiable {
    let name: String
    let layers: [Layer]

    var id: String { name }

    static let all: [Preset] = [
        Preset(name: "Banknote", layers: [
            Layer(id: 0, name: "Outer band", lines: 48, petals: 18, radius: 0.86, depth: 0.08, spread: 1, width: 0.6, hue: 0.42),
            Layer(id: 1, name: "Weave", lines: 36, petals: 9, radius: 0.58, depth: 0.16, spread: 1, width: 0.7, hue: 0.55),
            Layer(id: 2, name: "Heart", lines: 24, petals: 6, radius: 0.24, depth: 0.12, spread: 0.5, width: 0.8, hue: 0.12),
        ]),
        Preset(name: "Medallion", layers: [
            Layer(id: 0, name: "Rim", lines: 64, petals: 32, radius: 0.9, depth: 0.04, spread: 1, width: 0.5, hue: 0.10),
            Layer(id: 1, name: "Crown", lines: 40, petals: 12, radius: 0.62, depth: 0.2, spread: 0.75, width: 0.7, hue: 0.08),
            Layer(id: 2, name: "Seal", lines: 30, petals: 5, radius: 0.3, depth: 0.18, spread: 1, width: 0.9, hue: 0.02),
        ]),
        Preset(name: "Lace", layers: [
            Layer(id: 0, name: "Edge", lines: 20, petals: 24, radius: 0.82, depth: 0.12, spread: 1, width: 0.8, hue: 0.62),
            Layer(id: 1, name: "Net", lines: 72, petals: 7, radius: 0.5, depth: 0.35, spread: 1, width: 0.4, hue: 0.75),
        ]),
        Preset(name: "Sunburst", layers: [
            Layer(id: 0, name: "Rays", lines: 90, petals: 3, radius: 0.55, depth: 0.4, spread: 1, width: 0.5, hue: 0.13),
            Layer(id: 1, name: "Core", lines: 16, petals: 8, radius: 0.18, depth: 0.08, spread: 1, width: 1.2, hue: 0.03),
        ]),
    ]
}

/// (r, g, b), 0…1, for a hue round the color wheel.
func inkColor(hue: Double, saturation: Double = 0.7, brightness: Double = 1) -> SIMD3<Double> {
    let h = (hue - hue.rounded(.down)) * 6
    let sector = Int(h) % 6
    let f = h - h.rounded(.down)
    let p = brightness * (1 - saturation)
    let q = brightness * (1 - saturation * f)
    let t = brightness * (1 - saturation * (1 - f))
    switch sector {
    case 0: return SIMD3(brightness, t, p)
    case 1: return SIMD3(q, brightness, p)
    case 2: return SIMD3(p, brightness, t)
    case 3: return SIMD3(p, q, brightness)
    case 4: return SIMD3(t, p, brightness)
    default: return SIMD3(brightness, p, q)
    }
}

/// The rosette being designed.
@MainActor
@Observable
final class Design {
    private(set) var layers: [Layer]
    var selection: Layer.ID?
    var ink: Ink = .glow
    var paper: Paper = .night
    var showsGuides = true
    /// The preset the layers came from, until one of them is changed.
    private(set) var presetName: String?

    /// How much of the rosette is engraved, 0…1 — every layer's lines, one
    /// after another, the last one partly. 1 when it is not being engraved.
    private(set) var engraved: Double = 1
    private(set) var isEngraving = false

    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var engravingTask: Task<Void, Never>?

    /// What draws it.
    @ObservationIgnored private(set) lazy var painter = RosettePainter(design: self)

    init() {
        layers = []
        load(Preset.all[0])
    }

    var selectedIndex: Int? {
        selection.flatMap { id in layers.firstIndex { $0.id == id } }
    }

    // MARK: Layers

    func load(_ preset: Preset) {
        stopEngraving()
        layers = preset.layers.map { layer in
            defer { nextID += 1 }
            return layer.withID(nextID)
        }
        selection = layers.first?.id
        presetName = preset.name
    }

    /// A new layer inside the others, in the next hue, selected.
    func addLayer() {
        let inner = layers.map(\.radius).min() ?? 0.9
        let hue = ((layers.last?.hue ?? 0) + 0.17).truncatingRemainder(dividingBy: 1)
        let layer = Layer(
            id: nextID, name: "Layer \(nextID + 1)", lines: 24, petals: 8,
            radius: max(0.12, inner * 0.6), depth: 0.12, spread: 1, width: 0.8, hue: hue
        )
        nextID += 1
        layers.append(layer)
        selection = layer.id
        presetName = nil
    }

    func removeSelected() {
        guard let index = selectedIndex else { return }
        layers.remove(at: index)
        selection = layers.indices.contains(index) ? layers[index].id : layers.last?.id
        presetName = nil
    }

    func toggleVisibility(of id: Layer.ID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].isVisible.toggle()
    }

    /// Change the selected layer.
    func editSelected(_ change: (inout Layer) -> Void) {
        guard let index = selectedIndex else { return }
        var layer = layers[index]
        change(&layer)
        guard layer != layers[index] else { return }
        layers[index] = layer
        presetName = nil
    }

    /// A binding into one field of the selected layer, for a control.
    func selected<Value>(_ field: WritableKeyPath<Layer, Value>, default value: Value) -> Binding<Value> {
        Binding(
            get: { [self] in selectedIndex.map { layers[$0][keyPath: field] } ?? value },
            set: { [self] newValue in editSelected { $0[keyPath: field] = newValue } }
        )
    }

    // MARK: Engraving

    /// Engrave the rosette from nothing, line by line, over `seconds`.
    func engrave(seconds: Double = 4) {
        engravingTask?.cancel()
        engraved = 0
        isEngraving = true
        engravingTask = Task { [weak self] in
            let start = ContinuousClock.now
            while true {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled else { return }
                let done = min(1, (ContinuousClock.now - start) / .seconds(seconds))
                self.engraved = done
                if done >= 1 {
                    self.isEngraving = false
                    self.engravingTask = nil
                    return
                }
            }
        }
    }

    /// Show the whole rosette now.
    func stopEngraving() {
        engravingTask?.cancel()
        engravingTask = nil
        isEngraving = false
        engraved = 1
    }
}
