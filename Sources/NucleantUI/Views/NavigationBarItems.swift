//
//  NavigationBarItems.swift
//  NucleantUI
//
//  Where the toolbar entries a screen filed go in its stack's bars, and
//  the view that draws one of them there.
//
//  Each placement has a weight on each side of the navigation bar it can
//  go on. A side lists its entries by weight, lightest first, left to
//  right, and in the order they were written where weights are equal. So
//  `.confirmationAction` (the heaviest trailing) ends up at the trailing
//  edge and `.navigation` (the heaviest leading) next to the title.
//

/// One entry of a screen's toolbars, with where it was filed from: which
/// `.toolbar` (its path in the tree) and that toolbar's environment.
struct FiledToolbarEntry: Identifiable {
    struct ID: Hashable {
        let path: [Int]
        let index: Int
    }

    let id: ID
    let entry: ToolbarEntry
    /// The environment where the `.toolbar` was written, which the entry's
    /// view is built in, as if it were still there.
    let environment: EnvironmentValues

    var placement: ToolbarItemPlacement.Kind { entry.placement.kind }

    var isFlexibleSpace: Bool {
        if case .spacer(.flexible) = entry.content { return true }
        return false
    }
}

/// A screen's toolbar entries, sorted into the bars' places.
struct NavigationBarItems {
    /// Between neighbouring items, and between the back button and the
    /// first leading item.
    static let spacing: Double = 12

    private(set) var leading: [FiledToolbarEntry] = []
    /// The first `.principal` view: what the bar shows instead of the
    /// title.
    private(set) var principal: FiledToolbarEntry?
    private(set) var trailing: [FiledToolbarEntry] = []
    /// `.secondaryAction` items, behind the "…" at the trailing edge.
    private(set) var overflow: [FiledToolbarEntry] = []
    /// `.bottomBar` and `.status` entries, in the order written.
    private(set) var bottom: [FiledToolbarEntry] = []

    /// `entries` in the order written. `backButtonShown`: a pushed screen
    /// whose back button isn't hidden, which takes the leading edge and
    /// sends `.navigation` items to the trailing side.
    init(_ entries: [FiledToolbarEntry], backButtonShown: Bool) {
        var leading: [(weight: Int, order: Int, entry: FiledToolbarEntry)] = []
        var trailing: [(weight: Int, order: Int, entry: FiledToolbarEntry)] = []
        for (order, entry) in entries.enumerated() {
            switch entry.placement {
            case .principal:
                // A space has nothing to show in the title's place.
                if principal == nil, case .view = entry.entry.content { principal = entry }
            case .secondaryAction:
                overflow.append(entry)
            case .status, .bottomBar:
                bottom.append(entry)
            case .navigation:
                if backButtonShown {
                    trailing.append((20, order, entry))
                } else {
                    leading.append((30, order, entry))
                }
            case .cancellationAction:
                leading.append((20, order, entry))
            case .topBarLeading:
                leading.append((10, order, entry))
            case .confirmationAction, .destructiveAction:
                trailing.append((40, order, entry))
            case .primaryAction:
                trailing.append((30, order, entry))
            case .topBarTrailing:
                trailing.append((10, order, entry))
            case .automatic:
                trailing.append((0, order, entry))
            }
        }
        let byWeight = { (a: (weight: Int, order: Int, entry: FiledToolbarEntry), b: (weight: Int, order: Int, entry: FiledToolbarEntry)) in
            a.weight != b.weight ? a.weight < b.weight : a.order < b.order
        }
        self.leading = leading.sorted(by: byWeight).map(\.entry)
        self.trailing = trailing.sorted(by: byWeight).map(\.entry)
    }

    /// Whether the navigation bar has anything from the toolbars to show.
    var fillsNavigationBar: Bool {
        !leading.isEmpty || principal != nil || !trailing.isEmpty || !overflow.isEmpty
    }
}

/// A toolbar entry drawn in a bar: its view, built in the environment of
/// the `.toolbar` that listed it, or a space.
@View
struct ToolbarEntryView {
    let entry: FiledToolbarEntry

    var body: some View {
        switch entry.entry.content {
        case .view(let view):
            _ModifierView(content: view, modifier: ToolbarItemEnvironmentModifier(environment: entry.environment))
        case .spacer(.flexible):
            Spacer(minLength: 0)
        case .spacer(.fixed):
            // Nothing wide, but one more gap: the items on either side read
            // as two groups.
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

/// A toolbar item's view built in the environment of the `.toolbar` that
/// listed it. Built again whenever its parent is.
struct ToolbarItemEnvironmentModifier: PrimitiveModifier {
    let environment: EnvironmentValues

    func modifyEnvironment(_ values: inout EnvironmentValues) {
        // Where the item was written, except for the menu it is a row of:
        // the "…" menu's, when it is in one.
        let menu = values.contextMenu
        let level = values.menuLevel
        values = environment
        values.contextMenu = menu
        values.menuLevel = level
    }

    func makeContent(_ context: inout BuildContext) -> EnvironmentContent {
        environmentContent(context)
    }

    func _isEquivalent(to other: ToolbarItemEnvironmentModifier) -> Bool { false }
}
