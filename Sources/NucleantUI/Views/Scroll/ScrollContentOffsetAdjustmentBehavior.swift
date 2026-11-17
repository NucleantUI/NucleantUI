//
//  ScrollContentOffsetAdjustmentBehavior.swift
//  NucleantUI
//
//  Whether a scroll view at rest moves its offset to keep the content where
//  it was as sizes change — from the end it is anchored to
//  (`.defaultScrollAnchor(_:for: .sizeChanges)`), at the edge a scroll
//  position put it at, where its target behavior lets it rest in a resized
//  viewport. A transaction that disables it leaves the offset where it is
//  for the changes it makes (`Transaction.scrollContentOffsetAdjustmentBehavior`);
//  the scroll view still keeps it inside the content.
//

/// A type that defines the different kinds of content offset adjusting
/// behaviors a scroll view can have.
public struct ScrollContentOffsetAdjustmentBehavior {
    enum Role: Hashable {
        case automatic, disabled
    }

    let role: Role

    /// The automatic behavior.
    ///
    /// A scroll view may automatically adjust its content offset
    /// based on the current context. The absolute offset may be adjusted
    /// to keep content in relatively the same place. For example,
    /// when scrolled to the bottom, a scroll view may keep the bottom
    /// edge scrolled to the bottom when the overall size of its content
    /// changes.
    public static var automatic: ScrollContentOffsetAdjustmentBehavior {
        ScrollContentOffsetAdjustmentBehavior(role: .automatic)
    }

    /// The disabled behavior.
    ///
    /// A scroll view will not adjust its content offset.
    public static var disabled: ScrollContentOffsetAdjustmentBehavior {
        ScrollContentOffsetAdjustmentBehavior(role: .disabled)
    }
}
