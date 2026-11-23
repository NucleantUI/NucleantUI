//
//  EggTimerApp.swift
//  EggTimer
//
//  A kitchen timer that lives in the system tray and nowhere else — the
//  menu bar on macOS, the notification area on Windows, the panel's tray
//  on Linux. A `SystemTray` in its default style, a menu, declared as the
//  app's only scene: the app opens no window at launch, keeps running with
//  none, and Quit in the menu is the way out.
//
//  The menu's rows follow the timer. Idle, it offers things to time; going,
//  Pause or Resume, and Reset; at the top, a disabled row saying what it is
//  doing. The item's label is the time left twice over: drawn into a bitmap
//  as a dial that empties, and as text — both in macOS's menu bar; on
//  Windows, and in most Linux trays, which show icons only, the dial, with
//  the text as its tooltip.
//

import Foundation
import NucleantUI
import Observation

// MARK: - Model

/// Something to time.
struct Preset: Identifiable {
    let name: String
    let minutes: Int

    var id: String { name }

    static let all: [Preset] = [
        Preset(name: "Soft-boiled egg", minutes: 6),
        Preset(name: "Medium egg", minutes: 8),
        Preset(name: "Hard-boiled egg", minutes: 10),
        Preset(name: "Green tea", minutes: 3),
        Preset(name: "Black tea", minutes: 5),
    ]
}

/// The timer: what it times, how long is left, and whether it is going.
/// One per app, as there is one item in the tray.
@MainActor
@Observable
final class EggTimer {
    static let shared = EggTimer()

    enum Phase {
        case idle, running, paused, done
    }

    private(set) var phase = Phase.idle
    private(set) var preset: Preset?

    /// Whole seconds left — what the label and the dial show.
    private(set) var remaining = 0

    /// When it runs out, while it is going. Time is read off the clock
    /// rather than counted in ticks, so a late tick loses nothing.
    @ObservationIgnored private var endsAt: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    func start(_ preset: Preset) {
        self.preset = preset
        remaining = preset.minutes * 60
        run()
    }

    func pause() {
        guard phase == .running else { return }
        ticker?.cancel()
        update()
        endsAt = nil
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        run()
    }

    func reset() {
        ticker?.cancel()
        endsAt = nil
        preset = nil
        remaining = 0
        phase = .idle
    }

    private func run() {
        endsAt = Date().addingTimeInterval(Double(remaining))
        phase = .running
        ticker?.cancel()
        // A task rather than a Foundation `Timer`, which needs a run loop
        // to fire it: woken just after each whole second left goes by.
        ticker = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.phase == .running {
                let untilNext = (self.endsAt?.timeIntervalSinceNow ?? 0)
                    .truncatingRemainder(dividingBy: 1)
                try? await Task.sleep(for: .seconds(untilNext > 0.01 ? untilNext + 0.01 : 1))
                guard !Task.isCancelled else { return }
                self.update()
            }
        }
    }

    /// `remaining` from the clock; done once it reaches zero.
    private func update() {
        guard let endsAt else { return }
        remaining = max(0, Int(endsAt.timeIntervalSinceNow.rounded(.up)))
        if remaining == 0 {
            ticker?.cancel()
            self.endsAt = nil
            phase = .done
        }
    }

    /// How much of the time is left, from 1 at the start to 0.
    var fractionLeft: Double {
        guard let preset, phase != .idle else { return 0 }
        return Double(remaining) / Double(preset.minutes * 60)
    }

    /// "5:42".
    var clock: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    /// The item's title: the time left, and the name of the app when there
    /// is nothing to time.
    var label: String {
        switch phase {
        case .idle: "Egg Timer"
        case .running, .paused: clock
        case .done: "Done"
        }
    }

    /// The menu's first row.
    var status: String {
        let name = preset?.name ?? ""
        switch phase {
        case .idle: return "Nothing on the stove"
        case .running: return "\(name): \(clock) left"
        case .paused: return "\(name): paused at \(clock)"
        case .done: return "\(name) is done"
        }
    }
}

// MARK: - The dial

/// The item's picture: a dial whose orange wedge is the time left, emptying
/// clockwise from twelve. Drawn pixel by pixel into a `RasterImage` — a
/// tray item takes a bitmap on every platform — and made once for each of
/// its sixty steps, so a tick that doesn't move the wedge reuses the last.
@MainActor
enum Dial {
    static let size = 32

    private static var made: [Int: RasterImage] = [:]

    static func image(fractionLeft: Double) -> RasterImage {
        let step = Int((max(0, min(1, fractionLeft)) * 60).rounded(.up))
        if let image = made[step] { return image }
        let image = draw(sweep: Double(step) / 60)
        made[step] = image
        return image
    }

    /// Orange: on a dark panel and on a light one.
    private static let ink = (red: 255.0, green: 159.0, blue: 10.0)

    private static func draw(sweep: Double) -> RasterImage {
        let center = Double(size) / 2
        let outer = center - 1
        let rim = 2.2
        let gap = 1.6
        var pixels = [UInt32](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                // Four by four samples a pixel, for smooth edges.
                var covered = 0
                for sy in 0..<4 {
                    for sx in 0..<4 {
                        let dx = Double(x) + (Double(sx) + 0.5) / 4 - center
                        let dy = Double(y) + (Double(sy) + 0.5) / 4 - center
                        let distance = (dx * dx + dy * dy).squareRoot()
                        var angle = atan2(dx, -dy)
                        if angle < 0 { angle += 2 * .pi }
                        let onRim = distance <= outer && distance >= outer - rim
                        let inWedge = distance <= outer - rim - gap && angle <= sweep * 2 * .pi && sweep > 0
                        if onRim || inWedge { covered += 1 }
                    }
                }
                guard covered > 0 else { continue }
                // Alpha-premultiplied ARGB, as `RasterImage` holds it.
                let coverage = Double(covered) / 16
                let alpha = UInt32((coverage * 255).rounded())
                let red = UInt32((ink.red * coverage).rounded())
                let green = UInt32((ink.green * coverage).rounded())
                let blue = UInt32((ink.blue * coverage).rounded())
                pixels[y * size + x] = alpha << 24 | red << 16 | green << 8 | blue
            }
        }
        return RasterImage(width: size, height: size, pixels: pixels)
    }
}

// MARK: - App

@main
struct EggTimerApp: NucleantApp {
    var body: some Scene {
        let timer = EggTimer.shared

        // The menu, row by row: rows are `Button`s and `Divider`s, with `if`
        // and `ForEach` deciding which there are — read again, and the menu
        // remade, whenever what they read of the timer changes.
        SystemTray {
            // Says, and does nothing.
            Button(timer.status) {}
                .disabled(true)
            Divider()
            if timer.phase == .running {
                Button("Pause") { timer.pause() }
            } else if timer.phase == .paused {
                Button("Resume") { timer.resume() }
            }
            if timer.phase != .idle {
                Button("Reset") { timer.reset() }
                Divider()
            }
            ForEach(Preset.all) { preset in
                Button("\(preset.name) (\(preset.minutes) min)") { timer.start(preset) }
            }
            Divider()
            Button("Quit Egg Timer") { Self.quit() }
                .keyboardShortcut("q")
        } label: {
            // An image and a text: both where the tray shows text, the
            // image where it shows only icons, with the text as its tooltip.
            HStack {
                Image(Dial.image(fractionLeft: timer.fractionLeft))
                Text(timer.label)
            }
        }
    }
}
