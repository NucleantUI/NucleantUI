//
//  ScrollGeometry.swift
//  NucleantUI
//

/// A type that defines the geometry of a scroll view.
///
/// SwiftUI provides you values of this type when using modifiers like
/// ``View/onScrollGeometryChange(for:of:action:)`` or
/// ``View/onScrollPhaseChange(_:)``.
public struct ScrollGeometry: Equatable, Sendable {
    /// The content offset of the scroll view.
    ///
    /// This is the position of the scroll view within its overall
    /// content size. This value may extend before zero or beyond
    /// the content size when the content insets of the scroll view
    /// are non-zero or when rubber banding.
    public var contentOffset: Point

    /// The size of the content of the scroll view.
    ///
    /// Unlike the container size of the scroll view, this refers to the
    /// total size of the content of the scroll view which can be smaller
    /// or larger than its containing size.
    public var contentSize: Size

    /// The content insets of the scroll view.
    ///
    /// Adding these insets to the content size of the scroll view
    /// will give you the total scrollable space of the scroll view.
    public var contentInsets: EdgeInsets

    /// The size of the container of the scroll view.
    ///
    /// This is the overall size of the scroll view. Combining this
    /// and the content offset will give you the current visible rect
    /// of the scroll view.
    public var containerSize: Size

    /// Creates a scroll geometry.
    public init(contentOffset: Point, contentSize: Size, contentInsets: EdgeInsets, containerSize: Size) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.containerSize = containerSize
    }

    /// The visible rect of the scroll view.
    ///
    /// This value is computed from the scroll view's content offset, content
    /// insets, and its container size: the whole of the scroll view, in the
    /// content's space.
    public var visibleRect: Rect {
        Rect(origin: contentOffset, size: containerSize)
    }

    /// The bounds rect of the scroll view.
    ///
    /// Unlike the visible rect, this value is within the content insets
    /// of the scroll view.
    public var bounds: Rect {
        Rect(
            x: contentOffset.x + contentInsets.leading,
            y: contentOffset.y + contentInsets.top,
            width: max(0, containerSize.width - contentInsets.horizontal),
            height: max(0, containerSize.height - contentInsets.vertical)
        )
    }
}

extension ScrollGeometry: CustomDebugStringConvertible {
    public var debugDescription: String {
        "ScrollGeometry(contentOffset: \(contentOffset), contentSize: \(contentSize), "
            + "contentInsets: \(contentInsets), containerSize: \(containerSize))"
    }
}
