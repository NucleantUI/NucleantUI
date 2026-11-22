//
//  MetronomeApp.swift
//  Metronome
//
//  A metronome that clicks. Every setting is one of the framework's
//  controls bound into the `@Observable` model through `@Bindable`:
//
//  * `Stepper` for the tempo — hold a button and it keeps stepping. One
//    more, with no label, sits beside Start / Tap: just the − / + buttons;
//  * `Slider` for the tempo too, with no label — only the range at either
//    end — and for the volume, with value labels;
//  * `Picker` in four styles: the meter as segments (`ForEach` tagging
//    each segment with its id), the subdivision as radio buttons, the sound
//    as a pop-up menu (explicit `.tag`s and a `Divider`), and the presets as
//    an inline list over an optional selection — a manual tempo change
//    clears it. The meter is also a pop-up with no label beside Start /
//    Tap: a picker made without a label is the control alone;
//  * `Toggle` as a switch, a checkbox and a button — the button is Start /
//    Stop. The switch has no label: it ends a row of its own, the switch
//    alone on the trailing edge.
//

import NucleantUI

struct Theme {
    static let background = BackgroundStyle.background
    static let panel = BackgroundStyle.secondaryBackground
    static let accent = Color(hex: 0x4C8DFF)
    static let downbeat = Color(hex: 0xFF9F43)
    static let flash = DynamicShapeStyle(light: Color(hex: 0xDCE8FF), dark: Color(hex: 0x1F2B45))
}

// MARK: - Tempo

/// The tempo, big, with its marking, the beat lights and the tempo slider.
/// The panel flashes on every beat when that is turned on.
@View
struct TempoPanel {
    @Bindable var metronome: Metronome

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 2) {
                Text("\(metronome.tempo)")
                    .font(.system(size: 84, weight: .light, design: .monospaced))
                Text("BPM · \(tempoMarking(metronome.tempo))")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            BeatLights(
                beats: metronome.meter.beats,
                current: metronome.beat,
                accentsFirstBeat: metronome.accentsFirstBeat
            )

            // No label before the track — the tempo above says what it is —
            // only the range at either end.
            Slider(value: $metronome.tempoValue, in: 30...300, step: 1) {
                Text("30").font(.footnote).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("300").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            HStack(spacing: 10) {
                Toggle(isOn: $metronome.isPlaying) {
                    Text(metronome.isPlaying ? "Stop" : "Start")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 70)
                }
                .toggleStyle(.button)

                Button("Tap") { metronome.tap() }
                    .tint(DynamicShapeStyle(light: Color(white: 0.55), dark: Color(white: 0.3)))

                // The meter again, with no label: just the pop-up, beside
                // the buttons.
                Picker(selection: $metronome.meter) {
                    ForEach(Meter.allCases) { meter in
                        Text(meter.name)
                    }
                }

                // The tempo a beat per minute at a time, with no label:
                // just the − / + buttons.
                Stepper(value: $metronome.tempo, in: Metronome.tempoRange)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(metronome.flashesOnBeat && metronome.isFlashing ? AnyShapeStyle(Theme.flash) : AnyShapeStyle(Theme.panel))
        .cornerRadius(16)
    }
}

/// One light per beat of the bar; the one sounding is lit, the downbeat in
/// its own colour while it is accented.
@View
struct BeatLights {
    let beats: Int
    let current: Int?
    let accentsFirstBeat: Bool

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<beats) { index in
                let isDownbeat = index == 0 && accentsFirstBeat
                let color = isDownbeat ? Theme.downbeat : Theme.accent
                Circle()
                    .fill(current == index ? AnyShapeStyle(color) : AnyShapeStyle(.fill))
                    .frame(width: isDownbeat ? 22 : 18, height: isDownbeat ? 22 : 18)
                    .frame(width: 22, height: 22)
            }
        }
    }
}

// MARK: - Settings

/// Every setting, one per row.
@View
struct SettingsPanel {
    @Bindable var metronome: Metronome

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                Stepper(value: $metronome.tempo, in: Metronome.tempoRange) {
                    Text("Tempo")
                        .font(.system(size: 12))
                    Text("\(metronome.tempo)")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Picker("Time", selection: $metronome.meter) {
                    ForEach(Meter.allCases) { meter in
                        Text(meter.name)
                            .fixedSize()
                    }
                }
                .pickerStyle(.segmented)
                .font(.system(size: 12))

                Picker("Sound", selection: $metronome.sound) {
                    Text("Click").tag(ClickSound.click)
                    Text("Woodblock").tag(ClickSound.woodblock)
                    Divider()
                    Text("Beep").tag(ClickSound.beep)
                }
                    .font(.system(size: 12))

                Picker("Subdivide", selection: $metronome.subdivision) {
                    ForEach(Subdivision.allCases) { subdivision in
                        Text(subdivision.name)
                    }
                }
                .pickerStyle(.radioGroup)
                .font(.system(size: 12))

                Slider(value: $metronome.volume) {
                    Text("Volume")
                } minimumValueLabel: {
                    Text("0%").font(.footnote).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("100%").font(.footnote).foregroundStyle(.secondary)
                }
                    .font(.system(size: 12))

                Divider()

                // A row of its own around a switch with no label: the
                // downbeat's colour and the text on the leading edge, the
                // switch alone on the trailing one.
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.downbeat)
                        .frame(width: 10, height: 10)
                    Text("Accent first beat")
                    Spacer(minLength: 8)
                    Toggle(isOn: $metronome.accentsFirstBeat)
                        .toggleStyle(.switch)
                }

                Toggle("Flash on beat", isOn: $metronome.flashesOnBeat)

                Divider()

                Picker("Presets", selection: $metronome.preset) {
                    ForEach(TempoPreset.allCases) { preset in
                        HStack(spacing: 8) {
                            Text(preset.name)
                                .frame(width: 104, alignment: .leading)
                            Text("\(preset.bpm) BPM")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .pickerStyle(.inline)
                .font(.system(size: 12))
            }
            .padding(18)
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
        .cornerRadius(16)
    }
}

// MARK: - App

@View
struct MetronomeView {
    @State private var metronome = Metronome()
    @Environment(\.colorScheme) private var system

    var body: some View {
        HStack(spacing: 16) {
            TempoPanel(metronome: metronome)
            SettingsPanel(metronome: metronome)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .tint(Theme.accent)
        .colorScheme(AppearanceModel.shared.appearance.scheme ?? system)
    }
}

@main
struct MetronomeApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Metronome") {
            MetronomeView()
        }
        .defaultSize(width: 900, height: 760)
        .commands { AppearanceCommands() }
    }
}
