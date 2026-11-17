//
//  ScrollViewReader.swift
//  NucleantUI
//
//  Scrolling to a view by its id. The reader's proxy finds the view in the
//  tree as last placed — by `.id(_:)`, or as the element of a `ForEach` —
//  and asks the innermost scroll view around it to go there. Where "there"
//  is gets worked out again each pass as the content is placed: a lazy
//  container may not have built the view yet, so the first pass aims at
//  where its gap says it is, and the passes after correct the aim as the
//  rows come in.
//

/// A proxy value that supports programmatic scrolling of the scrollable
/// views within a view hierarchy.
///
/// You don't create instances of `ScrollViewProxy` directly. Instead, your
/// ``ScrollViewReader`` receives an instance of `ScrollViewProxy` in its
/// `content` view builder. You use actions within this view builder, such
/// as button and gesture handlers or the ``View/onChange(of:perform:)``
/// method, to call the proxy's ``ScrollViewProxy/scrollTo(_:anchor:)`` method.
public struct ScrollViewProxy {
    let reader: ScrollViewReaderState

    /// Scans all scroll views contained by the proxy for the first
    /// with a child view with identifier `id`, and then scrolls to
    /// that view.
    ///
    /// If `anchor` is `nil`, this method finds the container of the identified
    /// view, and scrolls the minimum amount to make the identified view
    /// wholly visible.
    ///
    /// If `anchor` is non-`nil`, it defines the points in the identified
    /// view and the scroll view to align. For example, setting `anchor` to
    /// ``UnitPoint/top`` aligns the top of the identified view to the top of
    /// the scroll view. Similarly, setting `anchor` to ``UnitPoint/bottom``
    /// aligns the bottom of the identified view to the bottom of the scroll
    /// view, and so on.
    ///
    /// Inside `withAnimation`, it scrolls there along the animation.
    ///
    /// - Parameters:
    ///   - id: The identifier of a child view to scroll to.
    ///   - anchor: The alignment behavior of the scroll action.
    @MainActor
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        guard let root = reader.node, let found = root.place(identifiedBy: id),
              let scrollNode = found.node.enclosingScrollView,
              let scroller = scrollNode.content(as: ScrollContent.self)?.scroller
        else { return }
        let transaction = TransactionScope.current
        let animation = transaction?.disablesAnimations == true ? nil : transaction?.animation
        scroller.request({ scroller, scrollNode in
            guard let place = scrollNode.place(identifiedBy: id) else { return nil }
            let rect = scroller.contentRect(place.frame(along: scroller.axes))
            return (scroller.offset(showing: rect, anchor: anchor), place.isBuilt)
        }, animation: animation)
    }
}

/// A view that provides programmatic scrolling, by working with a proxy
/// to scroll to known child views.
///
/// The scroll view reader's content view builder receives a ``ScrollViewProxy``
/// instance; you use the proxy's ``ScrollViewProxy/scrollTo(_:anchor:)`` to
/// perform scrolling.
///
/// The following example creates a ``ScrollView`` containing 100 views that
/// together display a color gradient. It also contains two buttons, one each
/// at the top and bottom. The top button tells the ``ScrollViewProxy`` to
/// scroll to the bottom button, and vice versa.
///
///     @Namespace var topID
///     @Namespace var bottomID
///
///     var body: some View {
///         ScrollViewReader { proxy in
///             ScrollView {
///                 Button("Scroll to Bottom") {
///                     withAnimation {
///                         proxy.scrollTo(bottomID)
///                     }
///                 }
///                 .id(topID)
///
///                 VStack(spacing: 0) {
///                     ForEach(0..<100) { i in
///                         color(fraction: Double(i) / 100)
///                             .frame(height: 32)
///                     }
///                 }
///
///                 Button("Top") {
///                     withAnimation {
///                         proxy.scrollTo(topID)
///                     }
///                 }
///                 .id(bottomID)
///             }
///         }
///     }
///
/// > Important: You may not use the ``ScrollViewProxy``
/// during execution of the `content` view builder; doing so results in a
/// runtime error. Instead, only actions created within `content` can call
/// the proxy, such as gesture handlers or a view's `onChange(of:perform:)`
/// method.
@View
public struct ScrollViewReader<Content: View> {
    /// The view builder that creates the reader's content.
    public var content: (ScrollViewProxy) -> Content

    @State private var reader = ScrollViewReaderState()

    /// Creates an instance that can perform programmatic scrolling of its
    /// child scroll views.
    ///
    /// - Parameter content: The reader's content, containing one or more
    /// scroll views. This view builder receives a ``ScrollViewProxy``
    /// instance that you use to perform scrolling.
    public init(_viewID: ViewID = #viewID, @ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content
        self._viewID = _viewID
    }

    public var body: Never { bodyUnavailable() }
}

/// What a reader's proxy finds its views from: the reader's node as last
/// built. Kept on the reader's position, so a proxy kept by an action
/// reaches the reader as it stands now.
@MainActor
final class ScrollViewReaderState {
    weak var node: ViewNode?
}

extension ScrollViewReader: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        let proxy = ScrollViewProxy(reader: reader)
        // The closure is the app's: what it reads is the reader's.
        let built = trackingObservation(for: context.position.handle) { content(proxy) }
        let child = context.child(0) { ctx in buildNode(built, &ctx) }
        let node = ContentNode(content: ScrollViewReaderContent(), children: [child])
        reader.node = node
        return node
    }
}

/// A reader's node: it lays out and places what it wraps, as it is.
struct ScrollViewReaderContent: NodeContent {}

extension ScrollViewReaderContent { static var placesPurely: Bool { true } }

// MARK: - Finding a view by its id

/// Where the view an id names stands, as last placed.
@MainActor
enum IdentifiedPlace {
    /// Built: its node.
    case view(ViewNode)
    /// Outside a lazy container's window: the gap standing in for it, and
    /// which of the gap's elements it is.
    case unbuilt(gap: ViewNode, index: Int, count: Int)

    var node: ViewNode {
        switch self {
        case .view(let node): node
        case .unbuilt(let gap, _, _): gap
        }
    }

    var isBuilt: Bool {
        if case .view = self { return true }
        return false
    }

    /// Its frame — for one not built, its share of its gap's length along
    /// the axis the scroll view scrolls (the gap's longer side, when it
    /// scrolls both ways).
    func frame(along axes: Axis.Set) -> Rect {
        switch self {
        case .view(let node):
            // A transparent node — a `ForEach` row that carries an `.id` of
            // its own, a `Group` of views — is never placed itself: the box
            // around the views it stands for.
            guard node.isTransparent else { return node.frame }
            var frame: Rect?
            for child in node.layoutChildren {
                frame = frame.map { $0.union(child.frame) } ?? child.frame
            }
            return frame ?? node.frame
        case .unbuilt(let gap, let index, let count):
            var frame = gap.frame
            let axis: Axis
            if axes == .horizontal {
                axis = .horizontal
            } else if axes == .vertical {
                axis = .vertical
            } else {
                axis = frame.width > frame.height ? .horizontal : .vertical
            }
            let share = frame.size[axis] / Double(max(count, 1))
            frame.origin[axis] += share * Double(index)
            frame.size[axis] = share
            return frame
        }
    }
}

extension ViewNode {
    /// The view `id` names in this subtree — by `.id(_:)`, or as the
    /// element of a `ForEach` — the first found, depth first.
    func place<ID: Hashable>(identifiedBy id: ID) -> IdentifiedPlace? {
        guard !traits.contains(.parked), removal == nil else { return nil }
        if isTransparent {
            if let identified = content(as: IdentifiedContent<ID>.self), identified.id == id {
                return .view(identified.view)
            }
            if let forEach = content(as: ForEachContent<ID>.self) {
                if let row = forEach.row(for: id) { return .view(row) }
                if let unit = forEach.unitOfID?(id) {
                    for child in children {
                        if let gap = child.content(as: LazyGapContent.self), gap.units.contains(unit) {
                            return .unbuilt(gap: child, index: unit - gap.start, count: gap.count)
                        }
                    }
                }
            }
        }
        for child in children {
            if let found = child.place(identifiedBy: id) { return found }
        }
        return nil
    }

    /// The innermost `ScrollView` this node is placed in.
    var enclosingScrollView: ViewNode? {
        var probe = parent
        while let current = probe {
            if current.content(as: ScrollContent.self) != nil { return current }
            probe = current.parent
        }
        return nil
    }
}
