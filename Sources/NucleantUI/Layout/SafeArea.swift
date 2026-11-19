//
//  SafeArea.swift
//  NucleantUI
//
//  The parts of the window views are laid out clear of. The host lays its
//  root view out inside them, and `.ignoresSafeArea` lets a view back out
//  into them. So far only the on-screen keyboard makes one: the window's
//  own edges (a status bar, a home indicator) are not safe areas yet.
//
//  A view reaches into the safe area at an edge only where its frame is on
//  the safe area's edge: laid out inside it, a view at the bottom has the
//  keyboard under it, a view higher up has nothing. Its inset at that edge
//  is then from its own edge out to the window's, as SwiftUI resolves them.
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
    /// Nothing is in it yet: views are laid out over the whole window,
    /// under its bars and corners.
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

    /// How far a view placed in `rect` can reach into the safe area of
    /// `regions` at each edge: from its edge out to the window's, at an edge
    /// that is on the safe area's edge or past it, and 0 at any other.
    func insets(of regions: SafeAreaRegions, at rect: Rect) -> EdgeInsets {
        let selected = insets(of: regions)
        guard selected != .zero else { return EdgeInsets() }
        let outer = container
        let safe = container.insetBy(selected)
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
