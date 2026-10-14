//
//  Preview.swift
//  NucleantUI
//
//  `@Preview` and the record it leaves behind.
//

/// Shows this function's view as a preview: in a build with
/// `NUCLEANT_PREVIEW` defined, the app launches `PreviewRuntime` instead of
/// its scenes, with one tab per `@Preview` function in the app.
///
/// ```swift
/// @Preview("Progress ring")
/// @MainActor
/// func progressRingPreview() -> some View {
///     ProgressRing(progress: 0.4, color: .red)
/// }
/// ```
///
/// The function is declared at file scope, takes no parameters and returns
/// its view; the tab is titled `name`, or the function's name without one.
/// It is `@MainActor`, as everything that makes views is — an attached
/// macro cannot add that to the function it is attached to. In any other
/// build it is an ordinary function nothing calls.
@attached(peer)
public macro Preview(_ name: String? = nil) = #externalMacro(module: "NucleantUIMacros", type: "PreviewMacro")

/// What `@Preview` places in the previews' linker section: a C function
/// that writes the preview's `_PreviewEntry` into the memory it is given.
/// Plumbing for the macro's expansion; not for direct use.
public typealias _PreviewRecord = @convention(c) (UnsafeMutableRawPointer) -> Void

/// One preview: where it was declared, what its tab says, and how to make
/// its view.
public struct _PreviewEntry {
    /// The tab's title.
    public let name: String
    /// `Module/File.swift` of the `@Preview`.
    public let fileID: String
    /// The full path of that file, as the compiler was given it: what
    /// `NUCLEANT_PREVIEW_FILE` names to show one file's previews.
    public let filePath: String
    /// Line of the `@Preview`.
    public let line: Int
    /// What names this preview across rebuilds: its file and title, not its
    /// line, which moves with every edit above it.
    public var id: String { "\(fileID)#\(name)" }
    /// The view, made each time the browser's body runs — a fresh one per
    /// selection, so a preview starts over with fresh state when it is
    /// selected again.
    let make: @MainActor () -> AnyView

    init<Content: View>(name: String, fileID: String, filePath: String, line: Int, content: @escaping @MainActor () -> Content) {
        self.name = name
        self.fileID = fileID
        self.filePath = filePath
        self.line = line
        self.make = { AnyView(content()) }
    }

    /// What a `_PreviewRecord` does. Called by `@Preview`'s expansion.
    public static func _write<Content: View>(
        to memory: UnsafeMutableRawPointer,
        name: String,
        fileID: String,
        filePath: String,
        line: Int,
        content: @escaping @MainActor () -> Content
    ) {
        memory.initializeMemory(
            as: _PreviewEntry.self,
            to: _PreviewEntry(name: name, fileID: fileID, filePath: filePath, line: line, content: content)
        )
    }
}
