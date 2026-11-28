//
//  RosettesApp.swift
//  Rosettes
//
//  A designer for guilloché rosettes — the woven line patterns engraved on
//  banknotes and watch dials — drawn with the Skia API itself through
//  `SkiaCanvasView`:
//
//  * the drawing is a `SkiaRenderContext` (`RosettePainter`) that the
//    `@Observable` design owns, so the view takes it by identity and the
//    parent rebuilding with it changes nothing;
//  * `onAppear` sets up its paints once, and `update` draws on the canvas
//    the views around it are drawn on, in paint order — the rounded corner
//    and the controls beside it are the same canvas;
//  * `update` reads the design, so a slider, a picker, a preset or the
//    engraving ticking on at 60 Hz draws it again, and nothing else does.
//
//  The layers are listed on the left, picked from presets or added; the
//  selected one is shaped on the right with `Stepper`s and `Slider`s.
//

import NucleantUI

struct Theme {
    static let background = BackgroundStyle.background
    static let panel = BackgroundStyle.secondaryBackground
    static let accent = Color(hex: 0xC9A227)
}

/// A layer's ink, as a color for the controls.
func swatch(_ layer: Layer) -> Color {
    let rgb = inkColor(hue: layer.hue)
    return Color(red: Float(rgb.x), green: Float(rgb.y), blue: Float(rgb.z))
}

// MARK: - Layers

/// One layer in the list: its ink, what it is, and whether it shows.
@View
struct LayerRow {
    let design: Design
    let layer: Layer

    var body: some View {
        let selected = design.selection == layer.id
        HStack(spacing: 10) {
            Circle()
                .fill(swatch(layer))
                .frame(width: 14, height: 14)
                .opacity(layer.isVisible ? 1 : 0.25)
            VStack(alignment: .leading, spacing: 2) {
                Text(layer.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(layer.lines) lines · \(layer.petals) petals")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(layer.isVisible ? "Hide" : "Show") {
                design.toggleVisibility(of: layer.id)
            }
            .font(.system(size: 11))
            .frame(width: 52)
        }
        .padding(8)
        .background(selected ? Theme.accent.opacity(0.22) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { design.selection = layer.id }
    }
}

/// The layers, adding and removing them, and the presets.
@View
struct LayerList {
    let design: Design

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Layers")
                    .font(.headline)
                    .fixedSize()
                Spacer(minLength: 0)
                Text(design.presetName ?? "Custom")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 90, alignment: .trailing)
            }
            ScrollView(.vertical) {
                VStack(spacing: 4) {
                    ForEach(design.layers) { layer in
                        LayerRow(design: design, layer: layer)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 8) {
                Button("Add Layer") { design.addLayer() }
                Button("Remove") { design.removeSelected() }
                    .disabled(design.selectedIndex == nil)
            }
            .font(.system(size: 12))
            Divider()
            Text("Presets")
                .font(.headline)
            ForEach(Preset.all) { preset in
                Button(preset.name) { design.load(preset) }
                    .font(.system(size: 12))
            }
        }
        .padding(14)
        .frame(width: 270)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }
}

// MARK: - The rosette

/// The rosette, and how it is engraved and shown.
@View
struct Workbench {
    @Bindable var design: Design

    var body: some View {
        VStack(spacing: 12) {
            SkiaCanvasView(context: design.painter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(14)
            HStack(spacing: 14) {
                Button(design.isEngraving ? "Show All" : "Engrave") {
                    if design.isEngraving {
                        design.stopEngraving()
                    } else {
                        design.engrave()
                    }
                }
                .frame(width: 92)
                // No labels: the segments say what they are.
                Picker(selection: $design.ink) {
                    ForEach(Ink.allCases) { ink in
                        Text(ink.name)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                Picker(selection: $design.paper) {
                    ForEach(Paper.allCases) { paper in
                        Text(paper.name)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Toggle("Guides", isOn: $design.showsGuides)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
        }
        .padding(14)
    }
}

// MARK: - Inspector

/// A slider with its title and its value, the value in a fixed width so
/// nothing moves as it changes.
@View
struct ValueSlider {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 0)
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .trailing)
            }
            Slider(value: $value, in: range)
        }
    }
}

/// A stepper with its title and its count, the count in a fixed width.
@View
struct CountStepper {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            Text(title)
            Text("\(value)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

/// The selected layer, shaped.
@View
struct Inspector {
    let design: Design

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Layer")
                .font(.headline)
            if let index = design.selectedIndex {
                let layer = design.layers[index]
                HStack(spacing: 8) {
                    Circle()
                        .fill(swatch(layer))
                        .frame(width: 12, height: 12)
                    Text(layer.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                CountStepper(title: "Lines", value: design.selected(\.lines, default: 1), range: Layer.lineRange)
                CountStepper(title: "Petals", value: design.selected(\.petals, default: 1), range: Layer.petalRange)
                ValueSlider(
                    title: "Radius", value: design.selected(\.radius, default: 0.5),
                    range: 0.08...0.95, text: "\(Int((layer.radius * 100).rounded()))%"
                )
                ValueSlider(
                    title: "Swing", value: design.selected(\.depth, default: 0),
                    range: 0...0.45, text: "\(Int((layer.depth * 100).rounded()))%"
                )
                ValueSlider(
                    title: "Spread", value: design.selected(\.spread, default: 1),
                    range: 0...1, text: "\(Int((layer.spread * 100).rounded()))%"
                )
                ValueSlider(
                    title: "Width", value: design.selected(\.width, default: 1),
                    range: 0.2...3, text: "\((layer.width * 10).rounded() / 10)pt"
                )
                ValueSlider(
                    title: "Hue", value: design.selected(\.hue, default: 0),
                    range: 0...1, text: "\(Int((layer.hue * 360).rounded()))°"
                )
            } else {
                Text("Select a layer to shape it.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(width: 270)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }
}

// MARK: - App

@View
struct RosettesView {
    @State private var design = Design()
    @Environment(\.colorScheme) private var system

    var body: some View {
        HStack(spacing: 0) {
            LayerList(design: design)
            Workbench(design: design)
            Inspector(design: design)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .tint(Theme.accent)
        .colorScheme(AppearanceModel.shared.appearance.scheme ?? system)
    }
}

@main
struct RosettesApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Rosettes") {
            RosettesView()
        }
        .defaultSize(width: 1200, height: 780)
        .commands { AppearanceCommands() }
    }
}
