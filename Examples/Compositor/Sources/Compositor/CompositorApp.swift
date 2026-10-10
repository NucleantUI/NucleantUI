//
//  CompositorApp.swift
//  Compositor
//
//  A layer compositor: every layer is a view tree rendered into a
//  `RenderTexture`, and the stack is composited by one generated shader that
//  takes those textures as its named inputs.
//
//  The three lifetimes this app is built around, and where each shows:
//
//  * A **texture** is an object the document holds. It is drawn when it is
//    asked to — `Redraw`, or any edit to what the layer looks like — and
//    never by itself. Nothing in the view tree owns it, so showing a layer
//    (`tex.view()` in the strip) and sampling it (the composite) are both
//    borrowing the one image.
//  * The **shader** is written out from the stack (`CompositeShader`), so
//    adding, hiding, reordering a layer or changing a blend mode is a new
//    shader and a recompile. The mix sliders are `ShaderArgument`s and are
//    not.
//  * The **export** goes the other way entirely: `renderImage` draws the
//    same trees on the CPU with no window and no GPU, which is how a
//    document is written out at a size the window never had.
//

import Foundation
import NucleantUI

/// The one colour the app picks out a selection with.
let accent = Color.dynamic(light: Color(hex: 0x2A6DF0), dark: Color(hex: 0x6D9BFF))

// MARK: - Root

@View
struct CompositorView {
    @Environment(\.colorScheme) private var system

    @State private var document = CompositorDocument()
    @State private var showsExport = false
    @State private var showsSource = false

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(
                document: document,
                showsExport: $showsExport,
                showsSource: $showsSource
            )
            HStack(spacing: 0) {
                LayerSidebar(document: document)
                    .frame(width: 312)
                Divider()
                if showsExport {
                    ExportPane(document: document)
                } else {
                    StagePane(document: document, showsSource: showsSource)
                }
            }
        }
        .background(Color.dynamic(light: Color(hex: 0xF2F3F5), dark: Color(hex: 0x16181C)))
        .colorScheme(AppearanceModel.shared.appearance.scheme ?? system)
    }
}

@View
private struct Toolbar {
    let document: CompositorDocument
    @Binding var showsExport: Bool
    @Binding var showsSource: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("Compositor")
                .font(.system(size: 14, weight: .semibold))
            Text("\(document.stack.count) of \(document.layers.count) layers in the shader")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
            Spacer(minLength: 12)
            Button("Add layer") { document.add() }
            Toggle("Source", isOn: $showsSource)
                .toggleStyle(.button)
            Toggle("Export", isOn: $showsExport)
                .toggleStyle(.button)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.dynamic(light: .white, dark: Color(hex: 0x1F2228)))
    }
}

// MARK: - The stage

/// The composite: one `Shader` view, fed the generated source, the mix
/// values and the layer textures.
///
/// It is a generative `Shader` rather than `.shader(_:)` on something —
/// there is no view underneath to read as `layer(uv)`, only the textures. So
/// binding 2 is unused here and the layers sit at 4, 5, 6…
@View
private struct StagePane {
    let document: CompositorDocument
    let showsSource: Bool

    var body: some View {
        let stack = document.stack
        let composite = CompositeShader(stack: stack)
        VStack(spacing: 14) {
            ZStack {
                Checkerboard()
                if stack.isEmpty {
                    Text("Every layer is hidden")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                } else {
                    Shader(
                        composite.function,
                        arguments: composite.arguments,
                        textures: composite.textures
                    )
                }
            }
            // Fitted rather than fixed: the composite takes whatever height
            // is left under the strip and keeps the texture's proportions, so
            // a taller window gets a bigger preview and never a stretched one.
            .aspectRatio(canvasAspect, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cornerRadius(8)

            if showsSource {
                SourcePane(source: composite.source)
            } else {
                LayerStrip(document: document)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
    }
}

/// The generated PyShader module, as it was handed to the compiler.
@View
private struct SourcePane {
    let source: String

    var body: some View {
        ScrollView {
            Text(source)
                .font(.system(size: 10.5, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(Color.dynamic(light: .white, dark: Color(hex: 0x12141A)))
        .cornerRadius(8)
    }
}

/// Each layer's own texture, shown through `tex.view()`.
///
/// The same images the shader is sampling, in the same frame — a texture is
/// one image however many places borrow it, so this strip costs a composite
/// each and no extra drawing.
@View
private struct LayerStrip {
    let document: CompositorDocument

    var body: some View {
        HStack(spacing: 10) {
            ForEach(document.layers) { layer in
                LayerThumbnail(
                    layer: layer,
                    isSelected: layer.id == document.selection
                ) {
                    document.selection = layer.id
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// One texture in the strip, and one of the two places a layer is selected.
///
/// Both of them say the same three things: a ring around what is selected, a
/// lighter one under the pointer so the thing reads as pressable before it is
/// pressed, and the name in the accent when it is the one being edited.
@View
private struct LayerThumbnail {
    let layer: CompositorLayer
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Checkerboard()
                layer.texture.view().resizable()
                    .opacity(layer.isVisible ? 1 : 0.25)
            }
            .frame(width: 112, height: 80)
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(ringColor, lineWidth: isSelected ? 2 : 1)
            )
            Text(layer.name)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? accent : Color.secondary)
        }
        .onHover { isHovered = $0 }
        .onTapGesture { select() }
    }

    private var ringColor: Color {
        if isSelected { return accent }
        return isHovered ? accent.opacity(0.45) : Color.dynamic(
            light: Color(hex: 0xC9CDD4),
            dark: Color(hex: 0x33373F)
        )
    }
}

/// Behind a texture with transparency, so what is image and what is gap is
/// visible.
@View
private struct Checkerboard {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { column in
                        Rectangle()
                            .fill((row + column).isMultiple(of: 2)
                                  ? Color.dynamic(light: Color(hex: 0xE4E6EA), dark: Color(hex: 0x23262D))
                                  : Color.dynamic(light: Color(hex: 0xD6D9DF), dark: Color(hex: 0x1B1E24)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Sidebar

@View
private struct LayerSidebar {
    let document: CompositorDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Top of the list is the top of the stack, as a layers panel
                // reads; the document keeps them bottom-first because that is
                // the order the shader folds them in.
                ForEach(document.layers.reversed()) { layer in
                    LayerRow(document: document, layer: layer)
                }
                if let selected = document.selected {
                    Divider()
                    LayerInspector(document: document, layer: selected)
                }
            }
            .padding(12)
        }
        .background(Color.dynamic(light: .white, dark: Color(hex: 0x1A1D23)))
    }
}

@View
private struct LayerRow {
    let document: CompositorDocument
    @Bindable var layer: CompositorLayer

    @State private var isHovered = false

    private var isSelected: Bool { layer.id == document.selection }

    var body: some View {
        HStack(spacing: 8) {
            // The bar down the leading edge is the row's "this one": it is
            // the only mark that survives both appearances and a row whose
            // layer is hidden and so drawn faint.
            Capsule()
                .fill(isSelected ? accent : Color.clear)
                .frame(width: 3, height: 24)
            Toggle("", isOn: $layer.isVisible)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Text("\(layer.tone.name) · \(layer.blend.name) · \(Int(layer.mix * 100))%")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(layer.isVisible ? 1 : 0.5)
            Button("↑") { document.move(layer, by: 1) }
            Button("↓") { document.move(layer, by: -1) }
        }
        .padding(horizontal: 8, vertical: 6)
        .frame(minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? accent.opacity(0.65) : Color.clear, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .onTapGesture { document.selection = layer.id }
    }

    /// Selected, hovered, neither — three steps, so the row says it can be
    /// pressed before it is pressed.
    private var fill: Color {
        if isSelected { return accent.opacity(0.18) }
        return isHovered
            ? Color.dynamic(light: Color(hex: 0xEDEFF3), dark: Color(hex: 0x23262D))
            : Color.clear
    }
}

/// The selected layer's controls, split by what each one costs.
@View
private struct LayerInspector {
    let document: CompositorDocument
    @Bindable var layer: CompositorLayer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(layer.name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary)

            // Arguments: a slider drag uploads the mix array and
            // re-dispatches. No recompile, no redraw.
            Row("Mix") {
                Slider(value: $layer.mix, in: 0...1) {
                    Text("Mix")
                } minimumValueLabel: {
                    EmptyView()
                } maximumValueLabel: {
                    EmptyView()
                }
                .labelsHidden()
            }

            // Source: the blend mode is one line of the generated shader, so
            // changing it writes a new one and the slot recompiles.
            Row("Blend") {
                Picker("Blend", selection: $layer.blend) {
                    ForEach(LayerBlend.allCases, id: \.self) { blend in
                        Text(blend.name).tag(blend)
                    }
                }
                .labelsHidden()
            }

            Divider()
            Text("TEXTURE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary)

            // Pixels: each of these re-renders the layer's tree into the same
            // image. The shader is untouched — it samples whatever is there.
            Row("Art") {
                Picker("Art", selection: Binding(
                    get: { layer.artwork },
                    set: { layer.set(artwork: $0) }
                )) {
                    ForEach(LayerArtwork.allCases, id: \.self) { artwork in
                        Text(artwork.name).tag(artwork)
                    }
                }
                .labelsHidden()
            }
            // Which way the one colour slider is read. A grey layer is what
            // makes a screen or a difference legible, so this sits right
            // above the slider it changes the meaning of.
            Row("Tone") {
                Picker("Tone", selection: Binding(
                    get: { layer.tone },
                    set: { layer.set(tone: $0) }
                )) {
                    ForEach(LayerTone.allCases, id: \.self) { tone in
                        Text(tone.name).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Row(layer.tone.valueName) {
                Slider(value: Binding(get: { layer.hue }, set: { layer.set(hue: $0) }), in: 0...1) {
                    Text(layer.tone.valueName)
                } minimumValueLabel: {
                    EmptyView()
                } maximumValueLabel: {
                    EmptyView()
                }
                .labelsHidden()
            }
            Row("Detail") {
                Slider(value: Binding(get: { layer.detail }, set: { layer.set(detail: $0) }), in: 0...1) {
                    Text("Detail")
                } minimumValueLabel: {
                    EmptyView()
                } maximumValueLabel: {
                    EmptyView()
                }
                .labelsHidden()
            }

            HStack(spacing: 8) {
                Button("Redraw") { layer.redraw() }
                Button("Delete") { document.remove(layer) }
                Spacer(minLength: 0)
            }
            Text("\(layer.texture.pixelWidth)×\(layer.texture.pixelHeight) px, held by the document")
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
        }
    }
}

@View
private struct Row<Content: View> {
    let title: String
    let content: Content

    init(_ title: String, _viewID: ViewID = #viewID, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self._viewID = _viewID
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
                .frame(width: 44, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Export

/// The document flattened on the CPU.
///
/// `renderImage` lays the same trees out at any size with no window and no
/// GPU — which is what an export is. It draws them stacked with their mix as
/// opacity: the blend modes belong to the GPU composite, and a vector canvas
/// has no screen or difference blend to offer, so this is deliberately the
/// normal-blended flatten rather than a second implementation of the shader
/// that would drift from it.
@View
private struct ExportPane {
    let document: CompositorDocument

    var body: some View {
        let scale = document.exportScale
        // Drawn once, here: `renderImage` lays the trees out and rasterizes
        // them, and the body reads its size as well as drawing it.
        let flattened = renderImage(size: canvasSize, scale: scale) {
            FlattenedStack(layers: document.stack)
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Export")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(flattened.width)×\(flattened.height) px at \(Int(scale))×")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                Spacer(minLength: 12)
                ForEach([1.0, 2.0, 3.0], id: \.self) { choice in
                    Button("\(Int(choice))×") { document.exportScale = choice }
                }
            }
            ZStack {
                Checkerboard()
                Image(flattened).resizable()
            }
            .aspectRatio(canvasAspect, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cornerRadius(8)
            Text("""
            Drawn by renderImage: the same trees the textures hold, laid out \
            again on the CPU at \(Int(scale)) pixels per point. Mix is applied \
            as opacity — the blend modes are the GPU composite's.
            """)
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
    }
}

@View
private struct FlattenedStack {
    let layers: [CompositorLayer]

    var body: some View {
        ZStack {
            ForEach(layers) { layer in
                layer.art.opacity(layer.mix)
            }
        }
    }
}

// MARK: - App

@main
struct CompositorApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Compositor", width: 1000, height: 700) {
            CompositorView()
        }
        .commands { AppearanceCommands() }
    }
}
