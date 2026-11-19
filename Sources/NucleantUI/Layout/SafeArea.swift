//
//  SafeArea.swift
//  NucleantUI
//
//  The parts of the window views are laid out clear of. The host lays its
//  root view out inside them, and `.ignoresSafeArea` lets a view back out
//  into them. Two regions make them: the window's own edges (`.container`:
//  on iOS the status bar, the sensor housing, the home indicator and the
//  rounded corners) and the on-screen keyboard (`.keyboard`), which covers
//  the bottom one.
//
//  A view reaches into the safe area at an edge only where its frame is on
//  the safe area's edge: laid out inside it, a view at the bottom has the
//  home indicator under it, a view higher up has nothing. Its inset at that
//  edge is then from its own edge out as far as the regions it ignores go,
//  as SwiftUI resolves them: to the window's edge for every region, to just
//  above the home indicator for the keyboard alone.
//
//  A scroll view's content is placed with none: it scrolls, so where it is
//  in the window says nothing about the window's edges.
//

/// A set of symbolic safe area regions.
public struct SafeAreaRegions: OptionSet, Sendable {
    public let rawValue: UInt

    /// Creates a new option set from the given raw value.
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// The safe area defined by the device and containers within the
    /// user interface, including elements such as top and bottom bars.
    ///
    /// The window's edges, where the platform says it has some: on iOS the
    /// status bar, the sensor housing, the home indicator and the rounded
    /// corners. None on the desktop platforms.
    public static let container = SafeAreaRegions(rawValue: 1 << 0)

    /// The safe area matching the current extent of any software
    /// keyboard displayed over the view content.
    public static let keyboard = SafeAreaRegions(rawValue: 1 << 1)

    /// All safe area regions.
    public static let all = SafeAreaRegions(rawValue: .max)
}

/// The safe area a view is placed in: insets into the window's rect, each
/// belonging to one or more regions. Rects are in layout space, as the
/// ones views are placed in.
struct SafeArea: Equatable, Sendable {
    struct Element: Equatable, Sendable {
        var regions: SafeAreaRegions
        var insets: EdgeInsets
    }

    /// The rect the insets are measured into: the window's.
    var container: Rect

    /// Outermost first.
    var elements: [Element]

    /// How near the safe area's edge a view's edge counts as on it: half a
    /// pixel, and a hair more for rounding.
    var tolerance: Double

    /// No safe area: everything is laid out over the whole window.
    static let none = SafeArea(container: .zero, elements: [], tolerance: 0)

    /// The insets of `regions` together. An edge that an element of another
    /// region already covers — one inside the elements of `regions` — is
    /// that region's: ignoring only the keyboard does not reach past the
    /// window's own bar under it, and ignoring only the window's bars does
    /// not reach under the keyboard.
    func insets(of regions: SafeAreaRegions) -> EdgeInsets {
        var selected = EdgeInsets()
        var open = Edge.Set.all
        for element in elements.reversed() {
            let insets = element.insets
            if element.regions.isDisjoint(with: regions) {
                if insets.top != 0 { open.remove(.top) }
                if insets.leading != 0 { open.remove(.leading) }
                if insets.bottom != 0 { open.remove(.bottom) }
                if insets.trailing != 0 { open.remove(.trailing) }
            } else {
                if open.contains(.top) { selected.top += insets.top }
                if open.contains(.leading) { selected.leading += insets.leading }
                if open.contains(.bottom) { selected.bottom += insets.bottom }
                if open.contains(.trailing) { selected.trailing += insets.trailing }
            }
        }
        return selected
    }

    /// Every element's insets together: where the safe area's edges are.
    var total: EdgeInsets {
        var total = EdgeInsets()
        for element in elements {
            total.top += element.insets.top
            total.leading += element.insets.leading
            total.bottom += element.insets.bottom
            total.trailing += element.insets.trailing
        }
        return total
    }

    /// How far a view placed in `rect` can reach into the safe area of
    /// `regions` at each edge: at an edge that is on the safe area's edge or
    /// past it, from there out over those regions' insets — what the other
    /// regions leave of the window — and 0 at any other.
    func insets(of regions: SafeAreaRegions, at rect: Rect) -> EdgeInsets {
        let selected = insets(of: regions)
        guard selected != .zero else { return EdgeInsets() }
        let total = self.total
        let safe = container.insetBy(total)
        let outer = container.insetBy(EdgeInsets(
            top: total.top - selected.top,
            leading: total.leading - selected.leading,
            bottom: total.bottom - selected.bottom,
            trailing: total.trailing - selected.trailing
        ))
        var reach = EdgeInsets()
        if rect.minY - tolerance < safe.minY, outer.minY < rect.minY + tolerance {
            reach.top = rect.minY - outer.minY
        }
        if safe.maxY < rect.maxY + tolerance, rect.maxY - tolerance < outer.maxY {
            reach.bottom = outer.maxY - rect.maxY
        }
        if rect.minX - tolerance < safe.minX, outer.minX < rect.minX + tolerance {
            reach.leading = rect.minX - outer.minX
        }
        if safe.maxX < rect.maxX + tolerance, rect.maxX - tolerance < outer.maxX {
            reach.trailing = outer.maxX - rect.maxX
        }
        return reach
    }
}
