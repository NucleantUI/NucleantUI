//
//  SafeAreaPadding.swift
//  NucleantUI
//
//  `.safeAreaPadding`: insets added to the safe area a view sees. There are
//  no safe areas to add to here otherwise, so it works out to what a view
//  in a safe area does: a scroll view keeps its frame, and insets its
//  content by the padding — the content scrolls past it, under the edges —
//  while any other view is laid out inside it, as `.padding` would. A
//  scroll view counts when it is what the modified view is, under the
//  modifiers and single-child containers around it.
//

extension View {
    /// Adds the provided insets into the safe area of this view.
    ///
    /// Use this modifier when you would like to add a fixed amount
    /// of space to the safe area a view sees.
    ///
    ///     ScrollView(.horizontal) {
    ///         HStack(spacing: 10.0) {
    ///             ForEach(items) { item in
    ///                 ItemView(item)
    ///             }
    ///         }
    ///     }
    ///     .safeAreaPadding(.horizontal, 20.0)
    public func safeAreaPadding(_ insets: EdgeInsets) -> some View {
        _ModifierView(content: self, modifier: SafeAreaPaddingModifier(insets: insets))
    }

    /// Adds the provided insets into the safe area of this view.
    ///
    /// Use this modifier when you would like to add a fixed amount
    /// of space to the safe area a view sees.
    ///
    ///     ScrollView(.horizontal) {
    ///         HStack(spacing: 10.0) {
    ///             ForEach(items) { item in
    ///                 ItemView(item)
    ///             }
    ///         }
    ///     }
    ///     .safeAreaPadding(.horizontal, 20.0)
    ///
    /// `nil` adds the default amount, 16 points, as `.padding`'s.
    public func safeAreaPadding(_ edges: Edge.Set = .all, _ length: Double? = nil) -> some View {
        _ModifierView(content: self, modifier: SafeAreaPaddingModifier(insets: EdgeInsets(edges, length ?? 16)))
    }

    /// Adds the provided insets into the safe area of this view.
    ///
    /// Use this modifier when you would like to add a fixed amount
    /// of space to the safe area a view sees.
    ///
    ///     ScrollView {
    ///         // ...
    ///     }
    ///     .safeAreaPadding(20.0)
    public func safeAreaPadding(_ length: Double) -> some View {
        _ModifierView(content: self, modifier: SafeAreaPaddingModifier(insets: EdgeInsets(length)))
    }
}

struct SafeAreaPaddingModifier: PrimitiveModifier, Equatable {
    let insets: EdgeInsets

    func makeContent(_ context: inout BuildContext) -> SafeAreaPaddingContent {
        SafeAreaPaddingContent(insets: insets)
    }
}

/// Hands its insets to the scroll view it wraps, through the draw context,
/// or pads what it wraps when that is no scroll view.
struct SafeAreaPaddingContent: NodeContent {
    let insets: EdgeInsets

    /// The scroll view `node` is: itself, or down through the nodes with a
    /// single view in their layout.
    private func scrollView(in node: ViewNode) -> ViewNode? {
        var probe = node
        while true {
            if probe.content(as: ScrollContent.self) != nil { return probe }
            let inner = probe.layoutChildren
            guard inner.count == 1 else { return nil }
            probe = inner[0]
        }
    }

    private func shrink(_ proposal: ProposedSize) -> ProposedSize {
        ProposedSize(
            width: proposal.width.map { max(0, $0 - insets.horizontal) },
            height: proposal.height.map { max(0, $0 - insets.vertical) }
        )
    }

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        guard let child = node.singleChild else {
            let inner = shrink(proposal).replacingUnspecifiedDimensions()
            return Size(width: inner.width + insets.horizontal, height: inner.height + insets.vertical)
        }
        if scrollView(in: child) != nil {
            return child.sizeThatFits(proposal)
        }
        let inner = child.sizeThatFits(shrink(proposal))
        return Size(width: inner.width + insets.horizontal, height: inner.height + insets.vertical)
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let child = node.singleChild else { return }
        if scrollView(in: child) != nil {
            var inner = context
            let padding = context.scrollSafeAreaPadding
            inner.scrollSafeAreaPadding = EdgeInsets(
                top: padding.top + insets.top,
                leading: padding.leading + insets.leading,
                bottom: padding.bottom + insets.bottom,
                trailing: padding.trailing + insets.trailing
            )
            child.place(in: rect, proposal: proposal, context: inner, into: &list)
        } else {
            child.place(in: rect.insetBy(insets), proposal: shrink(proposal), context: context, into: &list)
        }
    }
}
