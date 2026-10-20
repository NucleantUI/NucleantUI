//
//  ControlsPanel.swift
//  Backdrops
//

import NucleantUI

/// The presets and the sliders. Everything here reads the model, so it is
/// what rebuilds when the model changes — the backdrop beside it is not.
@View
struct ControlsPanel {
    let studio: Studio

    var body: some View {
        let look = studio.look
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Still")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    studio.still.view()
                        .cornerRadius(8)
                    Text("The look as a still wallpaper shows it, rendered again as you change it.")
                        .font(.footnote)
                        .foregroundColor(Theme.faint)
                }

                Text("Presets")
                    .font(.headline)

                VStack(spacing: 8) {
                    ForEach(Preset.all) { preset in
                        PresetRow(
                            preset: preset,
                            thumbnail: studio.thumbnails[preset.name],
                            isCurrent: look.preset == preset
                        ) {
                            look.apply(preset)
                        }
                    }
                }

                Text("Tune")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Swatch(color: look.colorA)
                        Swatch(color: look.colorB)
                        Spacer()
                        Button("Swap colours") { look.swapColors() }
                            .tint(Theme.accent)
                    }

                    LabeledSlider(
                        title: "Brightness",
                        value: Binding(get: { look.intensity }, set: { look.set(intensity: $0) }),
                        range: 0.2...2
                    )
                    LabeledSlider(
                        title: "Speed",
                        value: Binding(get: { look.speed }, set: { look.set(speed: $0) }),
                        range: 0...2
                    )
                    LabeledSlider(
                        title: "Scale",
                        value: Binding(get: { look.scale }, set: { look.set(scale: $0) }),
                        range: 0.5...4
                    )
                }
            }
            .padding(20)
        }
    }
}

@View
struct PresetRow {
    let preset: Preset
    let thumbnail: RenderTexture?
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let thumbnail {
                thumbnail.view()
                    .cornerRadius(4)
            }
            Text(preset.name)
            Spacer()
        }
        .padding(horizontal: 12, vertical: 8)
        .background(Theme.card)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Theme.accent : Color.clear, lineWidth: 2)
        )
        .onTapGesture { action() }
    }
}

@View
struct Swatch {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
    }
}

@View
struct LabeledSlider {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.footnote)
                    .foregroundColor(Theme.faint)
            }
            Slider(value: value, in: range)
        }
    }
}
