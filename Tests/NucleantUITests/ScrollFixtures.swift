//
//  ScrollFixtures.swift
//  NucleantUITests
//
//  What the scroll tests share: probes the views under test report into,
//  and the ways a test moves a hosted scroll view — frames, a flick, a drag
//  with no speed.
//

import Foundation
import Testing
@testable import NucleantUI

/// Where the content of a scroll view is, and how often it was built.
@MainActor
final class ScrollProbe {
    /// The top of the content in the scroll view's space: minus the offset.
    var top = 0.0
    var leading = 0.0
    /// The content's width, where a test lays it out across the scroll view.
    var width = 0.0
    var builds = 0
    var taps = 0
}

/// What a test drives a `ScrollViewReader` with, and what its views report.
@MainActor
final class ReaderProbe {
    var proxy: ScrollViewProxy?
    var top = 0.0
    /// Where row `watched` is in the scroll view, once placed.
    var watched = -1
    var watchedTop: Double?
}

/// The bindings a scroll position test writes to, and where the content is.
@MainActor
final class PositionProbe {
    var position: Binding<ScrollPosition>?
    var scrolledID: Binding<Int?>?
    var rows: Binding<Int>?
    var top = 0.0
}

/// What a scroll target behavior of the test's own was told.
@MainActor
final class SeenContext {
    var container: Size = .zero
    var content: Size = .zero
    var axes: Axis.Set = []
    var scheme: ColorScheme?
}

extension Harness {
    /// `count` frames, a sixtieth of a second apart.
    func frames(_ count: Int) async {
        for _ in 0..<count { await settle(1.0 / 60) }
    }

    /// A finger from `from` moving by `step` `count` times, 10 ms apart —
    /// 100 events a second — and lifted where it got to, at `step` per
    /// 10 ms.
    func flick(from: Point, step: Point, count: Int) async {
        host.pointerDown(at: from)
        var point = from
        for _ in 0..<count {
            try? await Task.sleep(for: .milliseconds(10))
            point += step
            host.pointerMoved(to: point)
        }
        host.pointerUp(at: point)
    }

    /// A finger moved by `distance` in two moves with no time between, and
    /// lifted: a scroll that lets go with no speed.
    func drag(from: Point, by distance: Point) {
        host.pointerDown(at: from)
        host.pointerMoved(to: from + distance / 2)
        host.pointerMoved(to: from + distance)
        host.pointerUp(at: from + distance)
    }
}
