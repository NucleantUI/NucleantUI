//
//  ForEach.swift
//  NucleantUI
//

/// Builds one view per element of a collection.
///
/// Identity comes from `id`, not position: reordering a list keeps each row's
/// `@State` with its own element, which is the whole reason SwiftUI insists on
/// an id here.
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    public let data: Data
    /// Where an element keeps its id — the key path itself, which compares
    /// by value, where a closure reading it could not be compared at all.
    let id: KeyPath<Data.Element, ID>
    let build: (Data.Element) -> Content

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.id = id
        self.build = content
    }

    public var body: Never { bodyUnavailable() }

    /// `element`'s id.
    func identify(_ element: Data.Element) -> ID {
        element[keyPath: id]
    }
}

extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    public init(
        _ data: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach where Data == Range<Int>, ID == Int {
    public init(
        _ data: Range<Int>,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.init(data, id: \.self, content: content)
    }
}

/// One row of a `ForEach`: its element and the row closure, built in the
/// row's slot. The closure is user code, and may read an `@Observable`
/// model or `@State`: those reads are the row's, so a change to one runs
/// this row's closure again rather than every row's. A row whose element
/// and closure are the same as last time — equivalent element, the same
/// code over equivalent captures — is kept without running it at all.
@View
struct ForEachRow<Element, Content: View> {
    let element: Element
    let build: (Element) -> Content

    var body: Never { bodyUnavailable() }
}

extension ForEachRow: BuiltinView, LazyPassThrough {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        let row = trackingObservation(for: context.position.handle) { build(element) }
        return context.child(0) { ctx in buildNode(row, &ctx) }
    }
}

extension ForEach: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        // Inside a lazy stack or grid, only the elements in its window.
        if let cursor = context.lazyCursor {
            return makeLazyNode(&context, cursor: cursor)
        }
        // The id, not the ordinal, gives a row its slot — so a row keeps
        // its state when the collection is reordered.
        let slots = context.rowSlots(for: ID.self)
        let built = data.map { element in
            let index = slots.slot(for: identify(element))
            let isNew = context.isNewChild(at: index)
            let node = context.child(index) { ctx in
                buildNode(ForEachRow(element: element, build: build), &ctx)
            }
            return (index: index, node: node, isNew: isNew)
        }
        slots.forgetGone(from: context.position, built: built.count)
        // Rows added come in with their transition (a fade, without one);
        // rows removed go out with it.
        return ContentNode(content: GroupContent(), children: context.transitionChildren(built))
    }
}
