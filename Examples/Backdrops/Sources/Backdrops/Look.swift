//
//  Look.swift
//  Backdrops
//
//  The backdrop being designed, and the shader's input: `pack` writes the
//  same fields in the same order as `class Look` in `Shaders/aurora.py`.
//  Each value aligns itself as the GPU reads it — the colours on 16 bytes,
//  the numbers on 4 — so the two sides agree without padding by hand.
//

import NucleantUI
import Observation

/// A starting point: two colours and how the bands move.
struct Preset: Identifiable, Hashable {
    let name: String
    let colorA: Color
    let colorB: Color
    let intensity: Double
    let speed: Double
    let scale: Double

    var id: String { name }

    static let all: [Preset] = [
        Preset(name: "Aurora", colorA: Color(hex: 0x0B3D2E), colorB: Color(hex: 0x3DF5A0), intensity: 1.1, speed: 0.6, scale: 1.6),
        Preset(name: "Ember", colorA: Color(hex: 0x2A0A05), colorB: Color(hex: 0xFF7A1A), intensity: 1.2, speed: 0.9, scale: 2.2),
        Preset(name: "Lagoon", colorA: Color(hex: 0x032B4A), colorB: Color(hex: 0x4CD3FF), intensity: 1.0, speed: 0.4, scale: 1.2),
        Preset(name: "Orchid", colorA: Color(hex: 0x1E0630), colorB: Color(hex: 0xE05CFF), intensity: 1.0, speed: 0.7, scale: 2.8),
        Preset(name: "Dusk", colorA: Color(hex: 0x14122B), colorB: Color(hex: 0xFFB36B), intensity: 0.9, speed: 0.3, scale: 1.4),
    ]
}

@MainActor @Observable
final class Look: ShaderInput {
    private(set) var colorA: Color
    private(set) var colorB: Color
    private(set) var intensity: Double
    private(set) var speed: Double
    private(set) var scale: Double
    /// The preset last applied, while nothing has been changed since.
    private(set) var preset: Preset?

    init(_ preset: Preset) {
        colorA = preset.colorA
        colorB = preset.colorB
        intensity = preset.intensity
        speed = preset.speed
        scale = preset.scale
        self.preset = preset
    }

    func apply(_ preset: Preset) {
        colorA = preset.colorA
        colorB = preset.colorB
        intensity = preset.intensity
        speed = preset.speed
        scale = preset.scale
        self.preset = preset
    }

    func set(intensity: Double) {
        self.intensity = intensity
        preset = nil
    }

    func set(speed: Double) {
        self.speed = speed
        preset = nil
    }

    func set(scale: Double) {
        self.scale = scale
        preset = nil
    }

    /// Swap the two colours.
    func swapColors() {
        (colorA, colorB) = (colorB, colorA)
        preset = nil
    }

    func pack(into bytes: inout [UInt8]) {
        colorA.pack(into: &bytes)
        colorB.pack(into: &bytes)
        Float(intensity).pack(into: &bytes)
        Float(speed).pack(into: &bytes)
        Float(scale).pack(into: &bytes)
    }
}
