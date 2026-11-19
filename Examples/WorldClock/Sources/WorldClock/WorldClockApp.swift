//
//  WorldClockApp.swift
//  WorldClock
//
//  The time where your people are: a window of analog clocks, one per city,
//  and the same clocks in the menu bar. The menu bar item is a `SystemTray`
//  in the `.window` style. Its title is the time here, and the window that
//  drops down from it is drawn like any other window, by Skia on Vulkan. It
//  stays when the window is closed, so the app goes on in the menu bar and
//  opens the window again from there (`openWindow(id:)`).
//
//  "Show in menu bar" in the window is the item's `isInserted`; taking the
//  item out of the menu bar (⌘-drag) turns it off. With the window closed
//  the app is in the menu bar alone, with no Dock icon, and back in the Dock
//  when the window opens again. Where there is no menu bar, the app is its
//  window.
//

import Foundation
import NucleantUI
import Observation

// MARK: - Model

/// A place, by its time zone.
struct City: Hashable, Identifiable {
    let name: String
    let zone: String

    var id: String { name }

    var timeZone: TimeZone { TimeZone(identifier: zone) ?? .current }

    static let all: [City] = [
        City(name: "Honolulu", zone: "Pacific/Honolulu"),
        City(name: "San Francisco", zone: "America/Los_Angeles"),
        City(name: "Denver", zone: "America/Denver"),
        City(name: "Chicago", zone: "America/Chicago"),
        City(name: "New York", zone: "America/New_York"),
        City(name: "São Paulo", zone: "America/Sao_Paulo"),
        City(name: "London", zone: "Europe/London"),
        City(name: "Paris", zone: "Europe/Paris"),
        City(name: "Cairo", zone: "Africa/Cairo"),
        City(name: "Moscow", zone: "Europe/Moscow"),
        City(name: "Dubai", zone: "Asia/Dubai"),
        City(name: "Mumbai", zone: "Asia/Kolkata"),
        City(name: "Bangkok", zone: "Asia/Bangkok"),
        City(name: "Singapore", zone: "Asia/Singapore"),
        City(name: "Tokyo", zone: "Asia/Tokyo"),
        City(name: "Sydney", zone: "Australia/Sydney"),
        City(name: "Auckland", zone: "Pacific/Auckland"),
    ]
}

/// The cities on show and the time now. One per app: the window and the
/// menu bar item show the same clocks.
@MainActor
@Observable
final class WorldClock {
    static let shared = WorldClock()

    private(set) var cities: [City] = City.all.filter { ["London", "New York", "Tokyo"].contains($0.name) }

    /// Now, to the second, for the clocks' hands.
    private(set) var now = Date()

    /// Now, to the minute: the menu bar item's title changes once a minute,
    /// not every second.
    private(set) var minute = WorldClock.startOfMinute(Date())

    /// Whether the menu bar item is there.
    var showsInMenuBar = true

    @ObservationIgnored private var ticker: Task<Void, Never>?

    private init() {
        // A task rather than a Foundation `Timer`: a timer needs a run loop
        // to fire it, and in the browser the page owns the event loop.
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    var citiesToAdd: [City] {
        City.all.filter { !cities.contains($0) }
    }

    func add(_ city: City) {
        guard !cities.contains(city) else { return }
        cities.append(city)
    }

    func remove(_ city: City) {
        cities.removeAll { $0 == city }
    }

    /// The menu bar item's title: the time here.
    var menuBarTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: minute)
    }

    private func tick() {
        let date = Date()
        now = date
        let minute = Self.startOfMinute(date)
        if minute != self.minute {
            self.minute = minute
        }
    }

    private static func startOfMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }
}

/// What a city's clock shows at a moment: the hands, the digits, and how
/// the day and the hour differ from here.
struct CityTime {
    /// Hours since midnight there, with the minutes in them; likewise the
    /// minutes and seconds.
    let hours: Double
    let minutes: Double
    let seconds: Double
    let digits: String
    let day: String
    let offset: String

    /// Dark from six in the evening to six in the morning.
    var isNight: Bool { hours < 6 || hours >= 18 }

    init(city: City, at now: Date) {
        var there = Calendar(identifier: .gregorian)
        there.timeZone = city.timeZone
        let parts = there.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        seconds = Double(parts.second ?? 0)
        minutes = Double(parts.minute ?? 0) + seconds / 60
        hours = Double(parts.hour ?? 0) + minutes / 60
        digits = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)

        var here = Calendar(identifier: .gregorian)
        here.timeZone = .current
        let today = here.dateComponents([.year, .month, .day], from: now)
        let thereDay = (parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let hereDay = (today.year ?? 0, today.month ?? 0, today.day ?? 0)
        day = thereDay == hereDay ? "Today" : (thereDay > hereDay ? "Tomorrow" : "Yesterday")

        let ahead = city.timeZone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)
        offset = Self.offset(ahead)
    }

    /// "+9 h", "−4:30 h", or "same time".
    static func offset(_ seconds: Int) -> String {
        guard seconds != 0 else { return "same time" }
        let sign = seconds > 0 ? "+" : "−"
        let minutes = abs(seconds) / 60
        if minutes % 60 == 0 {
            return "\(sign)\(minutes / 60) h"
        }
        return "\(sign)\(minutes / 60):\(String(format: "%02d", minutes % 60)) h"
    }
}

struct Theme {
    static let background = BackgroundStyle.background
    static let panel = BackgroundStyle.secondaryBackground
    static let dayFace = DynamicShapeStyle(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x3A3F4B))
    /// The edge of a face, so a day face on a light window still shows.
    static let rim = DynamicShapeStyle(light: Color(white: 0, opacity: 0.18), dark: Color(white: 1, opacity: 0.14))
    static let nightFace = DynamicShapeStyle(light: Color(hex: 0x2B2F38), dark: Color(hex: 0x15171C))
    static let dayInk = DynamicShapeStyle(light: Color(hex: 0x1C1E24), dark: Color(hex: 0xE9EAEE))
    static let nightInk = Color(hex: 0xE9EAEE)
    static let second = Color(hex: 0xFF9F0A)
    static let muted = DynamicShapeStyle(light: Color(white: 0.55), dark: Color(white: 0.3))
}

// MARK: - Clock

/// A line from the centre of the view, `length` as a fraction of the
/// radius, at `turns` round from twelve o'clock.
@View
struct Hand {
    let turns: Double
    let length: Double
    let width: Double
    let color: AnyShapeStyle

    var body: some View {
        PathShape { size in
            let c = Point(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 * length
            let a = turns * 2 * .pi - .pi / 2
            var path = Path()
            path.move(to: Point(x: c.x - cos(a) * r * 0.15, y: c.y - sin(a) * r * 0.15))
            path.addLine(to: Point(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            return path
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

/// An analog clock `diameter` points across, light by day and dark by
/// night there.
@View
struct ClockFace {
    let time: CityTime
    let diameter: Double

    var body: some View {
        // Strokes as thick as the face is large.
        let scale = diameter / 120
        let ink = time.isNight ? AnyShapeStyle(Theme.nightInk) : AnyShapeStyle(Theme.dayInk)

        ZStack {
            Circle().fill(time.isNight ? AnyShapeStyle(Theme.nightFace) : AnyShapeStyle(Theme.dayFace))
            Circle().stroke(Theme.rim, lineWidth: max(1, 1.5 * scale))
            // Twelve hour marks.
            PathShape { size in
                let c = Point(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2
                var path = Path()
                for i in 0..<12 {
                    let a = Double(i) / 12 * 2 * .pi
                    path.move(to: Point(x: c.x + cos(a) * r * 0.82, y: c.y + sin(a) * r * 0.82))
                    path.addLine(to: Point(x: c.x + cos(a) * r * 0.92, y: c.y + sin(a) * r * 0.92))
                }
                return path
            }
            .stroke(ink, lineWidth: max(1, 2 * scale))

            Hand(turns: time.hours / 12, length: 0.5, width: max(1.5, 4 * scale), color: ink)
            Hand(turns: time.minutes / 60, length: 0.75, width: max(1, 3 * scale), color: ink)
            Hand(turns: time.seconds / 60, length: 0.82, width: max(0.75, 1.2 * scale), color: AnyShapeStyle(Theme.second))
            Circle().fill(Theme.second).frame(width: max(3, 6 * scale), height: max(3, 6 * scale))
        }
        .frame(width: diameter, height: diameter)
    }
}

@Preview("Clock faces")
@MainActor
func clockFacesPreview() -> some View {
    HStack(spacing: 24) {
        ClockFace(time: CityTime(city: City.all[6], at: Date()), diameter: 120)
        ClockFace(time: CityTime(city: City.all[14], at: Date()), diameter: 120)
        ClockFace(time: CityTime(city: City.all[14], at: Date()), diameter: 36)
    }
    .padding(24)
    .background(Theme.panel)
}

// MARK: - Window

/// One city in the window: its clock, its time, and how it differs.
@View
struct CityCard {
    let clock: WorldClock
    let city: City

    var body: some View {
        let time = CityTime(city: city, at: clock.now)

        VStack(spacing: 8) {
            ClockFace(time: time, diameter: 120)
            Text(city.name)
                .font(.system(size: 16, weight: .semibold))
            Text(time.digits)
                .font(.system(size: 22, weight: .light, design: .monospaced))
            Text("\(time.day), \(time.offset)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Remove") { clock.remove(city) }
                .tint(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.panel)
        .cornerRadius(14)
    }
}

@View
struct WorldClockView {
    @Bindable var clock: WorldClock
    @Environment(\.colorScheme) private var system
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("World Clock")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                // A desktop's — where there is a menu bar to show it in.
                if supportsMultipleWindows {
                    Toggle("Show in menu bar", isOn: $clock.showsInMenuBar)
                }
                Menu("Add City") {
                    ForEach(clock.citiesToAdd) { city in
                        Button(city.name) { clock.add(city) }
                    }
                }
                .disabled(clock.citiesToAdd.isEmpty)
            }
            .padding(horizontal: 20, vertical: 14)

            Divider()

            if clock.cities.isEmpty {
                Text("No cities. Add one with Add City.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 16) {
                        ForEach(clock.cities) { city in
                            CityCard(clock: clock, city: city)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .background(Theme.background)
        .colorScheme(AppearanceModel.shared.appearance.scheme ?? system)
    }
}

@Preview("World Clock")
@MainActor
func worldClockPreview() -> some View {
    WorldClockView(clock: .shared)
        .frame(width: 640, height: 460)
}

// MARK: - Menu bar

/// The window under the menu bar item: each city on a row, the way to the
/// big window, and out of the app.
@View
struct MenuBarPanel {
    let clock: WorldClock
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var system

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if clock.cities.isEmpty {
                Text("No cities yet")
                    .foregroundStyle(.secondary)
                    .padding(18)
            }
            ForEach(clock.cities) { city in
                let time = CityTime(city: city, at: clock.now)
                HStack(spacing: 14) {
                    ClockFace(time: time, diameter: 48)
                    // What is left of the row once the clock and the time
                    // have theirs, so neither of them wraps.
                    VStack(alignment: .leading, spacing: 3) {
                        Text(city.name)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        Text("\(time.day), \(time.offset)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(time.digits)
                        .font(.system(size: 24, weight: .light, design: .monospaced))
                        .lineLimit(1)
                }
                .padding(horizontal: 16, vertical: 10)
            }
            Divider()
            HStack(spacing: 12) {
                // The row but for what Quit takes.
                Button("Open World Clock") { openWindow(id: "main") }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // With the window closed the app has no Dock icon and no
                // menus: this is the way out.
                Button("Quit") { WorldClockApp.quit() }
                    .lineLimit(1)
            }
            .padding(horizontal: 16, vertical: 12)
        }
        .frame(width: 380)
        .background(Theme.background)
        .colorScheme(AppearanceModel.shared.appearance.scheme ?? system)
    }
}

@Preview("Menu bar panel")
@MainActor
func menuBarPanelPreview() -> some View {
    MenuBarPanel(clock: .shared)
}

@main
struct WorldClockApp: NucleantApp {
    var body: some Scene {
        Window("World Clock", id: "main") {
            WorldClockView(clock: .shared)
        }
        .defaultSize(width: 640, height: 460)
        .commands { AppearanceCommands() }

        // The time here as its title, the clocks in a window under it.
        SystemTray(
            WorldClock.shared.menuBarTitle,
            isInserted: Binding(
                get: { WorldClock.shared.showsInMenuBar },
                set: { WorldClock.shared.showsInMenuBar = $0 }
            )
        ) {
            MenuBarPanel(clock: .shared)
        }
        .systemTrayStyle(.window)
    }
}
