//
//  FixedSizeTests.swift
//  NucleantUITests
//
//  `.fixedSize()` and `.fixedSize(horizontal:vertical:)`: a text in a frame
//  too narrow for it keeps its one line, sticks out of the frame centered
//  on it, and on an axis left free still follows what it is offered.
//

import Testing
@testable import NucleantUI

private let line = "A line much wider than sixty points"

/// The window-space frame of a text in a 60-point-wide frame, fixed on the
/// axes given.
@View
struct FixedSizeProbe {
    let log: Log
    let horizontal: Bool?
    let vertical: Bool

    var body: some View {
        content
            .frame(width: 60)
    }

    @ViewBuilder
    private var content: some View {
        if let horizontal {
            reported.fixedSize(horizontal: horizontal, vertical: vertical)
        } else {
            reported
        }
    }

    private var reported: some View {
        Text(line)
            .onGeometryChange(for: Rect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                log("\(Int(frame.minX)) \(Int(frame.width))×\(Int(frame.height))")
            }
    }
}

/// The same text with nothing constraining it — the size `.fixedSize()`
/// should land on.
@View
struct IdealTextProbe {
    let log: Log

    var body: some View {
        // Measured inside: the window gives the root all of itself, and the
        // fixed text is centered in that.
        Text(line)
            .onGeometryChange(for: Size.self) { proxy in
                proxy.size
            } action: { size in
                log("\(Int(size.width))×\(Int(size.height))")
            }
            .fixedSize()
    }
}

/// A fixed text next to a sibling that takes all it is offered.
@View
struct FixedTextBesideGreedy {
    let log: Log

    var body: some View {
        HStack(spacing: 0) {
            Text(line)
                .fixedSize()
                .onGeometryChange(for: Double.self) { proxy in
                    proxy.size.width
                } action: { width in
                    log("text \(Int(width))")
                }
            Color.red
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: Double.self) { proxy in
                    proxy.size.width
                } action: { width in
                    log("fill \(Int(width))")
                }
        }
        .frame(width: 120)
    }
}

/// A short and a long column, each filling all the height it is given, in a
/// row fixed vertically.
@View
struct EqualHeightColumns {
    let log: Log

    var body: some View {
        HStack(spacing: 0) {
            Text("Short")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: Double.self) { proxy in
                    proxy.size.height
                } action: { height in
                    log("short \(Int(height))")
                }
            Text(line)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: Double.self) { proxy in
                    proxy.size.height
                } action: { height in
                    log("long \(Int(height))")
                }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Parses `"x w×h"`.
private func parse(_ entry: String) -> (x: Int, width: Int, height: Int) {
    let parts = entry.split(separator: " ")
    let size = parts[1].split(separator: "×")
    return (Int(parts[0])!, Int(size[0])!, Int(size[1])!)
}

extension HostedViews {
    @MainActor
    @Suite
    struct FixedSizeTests {

        /// The size of `line` on one line, from the probe with no frame.
        private func idealSize() -> (width: Int, height: Int) {
            let log = Log()
            _ = Harness(IdealTextProbe(log: log), size: Size(width: 1000, height: 200))
            let size = log.take().last!.split(separator: "×")
            return (Int(size[0])!, Int(size[1])!)
        }

        @Test func withoutItTheTextWrapsToTheFrame() {
            let log = Log()
            _ = Harness(FixedSizeProbe(log: log, horizontal: nil, vertical: false))
            let frame = parse(log.take().last!)
            #expect(frame.width <= 60)
            #expect(frame.height > idealSize().height)
        }

        @Test func bothAxesKeepTheIdealSize() {
            let ideal = idealSize()
            #expect(ideal.width > 60)
            let log = Log()
            _ = Harness(FixedSizeProbe(log: log, horizontal: true, vertical: true))
            let frame = parse(log.take().last!)
            #expect(frame.width == ideal.width)
            #expect(frame.height == ideal.height)
        }

        @Test func theFixedViewIsCenteredOnTheFrameItSticksOutOf() {
            let log = Log()
            _ = Harness(FixedSizeProbe(log: log, horizontal: true, vertical: true))
            let frame = parse(log.take().last!)
            // The 60-point frame is centered in the 200-point window.
            let center = Double(frame.x) + Double(frame.width) / 2
            #expect(abs(center - 100) <= 1)
            #expect(frame.x < 70)
        }

        @Test func horizontalOnlyKeepsTheOneLine() {
            let ideal = idealSize()
            let log = Log()
            _ = Harness(FixedSizeProbe(log: log, horizontal: true, vertical: false))
            let frame = parse(log.take().last!)
            #expect(frame.width == ideal.width)
            #expect(frame.height == ideal.height)
        }

        @Test func verticalOnlyStillWrapsToTheOfferedWidth() {
            let ideal = idealSize()
            let log = Log()
            _ = Harness(FixedSizeProbe(log: log, horizontal: false, vertical: true))
            let frame = parse(log.take().last!)
            #expect(frame.width <= 60)
            #expect(frame.height > ideal.height)
        }

        @Test func aStackSizesTheFixedTextFirstAndTheSiblingTakesTheRest() {
            let ideal = idealSize()
            let log = Log()
            _ = Harness(FixedTextBesideGreedy(log: log))
            let entries = log.take()
            #expect(ideal.width > 120)
            #expect(entries.contains("text \(ideal.width)"))
            #expect(entries.contains("fill 0"))
        }

        @Test func aRowFixedVerticallyIsAsTallAsItsTallestColumn() {
            let log = Log()
            _ = Harness(EqualHeightColumns(log: log), size: Size(width: 200, height: 400))
            let entries = log.take()
            let short = entries.last { $0.hasPrefix("short") }!.split(separator: " ")[1]
            let long = entries.last { $0.hasPrefix("long") }!.split(separator: " ")[1]
            #expect(short == long)
            #expect(Int(long)! < 400)
            #expect(Int(long)! > 26)
        }

        @Test func equalModifiersAreEquivalent() {
            let a = FixedSizeModifier(horizontal: true, vertical: false)
            #expect(a._isEquivalent(to: FixedSizeModifier(horizontal: true, vertical: false)))
            #expect(!a._isEquivalent(to: FixedSizeModifier(horizontal: true, vertical: true)))
        }
    }
}
