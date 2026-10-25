//
//  PreviewRuntime.swift
//  NucleantUI
//
//  What `NucleantApp.main()` runs in a `NUCLEANT_PREVIEW` build: the app's
//  `@Preview` functions, one tab each, in a window of their own — instead of
//  the app's scenes.
//
//  Which previews: all of them, or with NUCLEANT_PREVIEW_FILE set to a
//  source file's path, only the ones declared in it — the file open in the
//  editor. That is read at launch, not compiled in, so showing another
//  file's previews is a relaunch of the same build.
//
//  A preview build is rebuilt and relaunched on every save, so which tab is
//  open has to outlive the process. The runtime takes no storage of its own
//  for that: it reads the tab to open from NUCLEANT_PREVIEW_SELECTED at
//  launch, and prints `NUCLEANT_PREVIEW_SELECTED=<id>` when the tab changes.
//  Whatever launches it keeps the last such line and hands it back the next
//  time — in the browser, the preview page does (nucleant-preview).
//

import CNucleantPreview
import Foundation

/// Collects the app's previews and runs them in place of the app.
///
/// `NucleantApp.main()` does this when `NUCLEANT_PREVIEW` is defined; the
/// app's own `body` is never built. The previews are every `@Preview`
/// function linked into the app, plus any added with `addPreview`, sorted
/// by file and line.
@MainActor
public final class PreviewRuntime {

    /// Previews registered in code rather than with `@Preview`.
    private static var added: [_PreviewEntry] = []

    /// What the preview window shows; set by `setup()`.
    static var previews: [_PreviewEntry] = []

    /// The file whose previews are shown, from NUCLEANT_PREVIEW_FILE; all
    /// of the app's when `nil`.
    static var file: String?

    /// The tab open at launch: the preview `NUCLEANT_PREVIEW_SELECTED` names,
    /// else the first.
    static var initialSelection = 0

    /// Told the selected preview's `id` when the tab changes. Prints the
    /// line a launcher keeps (see the top of this file).
    static var selectionChanged: @MainActor (String) -> Void = { id in
        print("NUCLEANT_PREVIEW_SELECTED=\(id)")
    }

    private var app: AppRuntime<PreviewApp>?

    public init() {}

    /// Adds a preview that has no `@Preview` function — one made by a tool
    /// or a test. Call it before `setup()`.
    public static func addPreview<Content: View>(
        _ name: String,
        fileID: String = #fileID,
        filePath: String = #filePath,
        line: Int = #line,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        added.append(_PreviewEntry(name: name, fileID: fileID, filePath: filePath, line: line, content: content))
    }

    /// Every preview in the app: the `@Preview` records linked in, and the
    /// added ones, by file then line.
    static func collect() -> [_PreviewEntry] {
        (records() + added).sorted { ($0.fileID, $0.line) < ($1.fileID, $1.line) }
    }

    /// Reads the `@Preview` records from their linker section.
    private static func records() -> [_PreviewEntry] {
        guard let start = nucleant_preview_records_start(),
              let end = nucleant_preview_records_end() else { return [] }
        let count = start.distance(to: end) / MemoryLayout<_PreviewRecord>.stride
        let records = UnsafeBufferPointer(start: start.assumingMemoryBound(to: _PreviewRecord.self), count: count)
        let entry = UnsafeMutablePointer<_PreviewEntry>.allocate(capacity: 1)
        defer { entry.deallocate() }
        return records.map { record in
            record(entry)
            return entry.move()
        }
    }

    /// The previews declared in `file` (a path, as `#filePath` spells it);
    /// all of them when `file` is `nil`.
    static func previews(in file: String?, from previews: [_PreviewEntry]) -> [_PreviewEntry] {
        guard let file else { return previews }
        return previews.filter { $0.filePath == file }
    }

    /// Where the preview `id` is in `previews`; the first when there is no
    /// such preview any more (renamed, deleted) or none was named.
    static func index(of id: String?, in previews: [_PreviewEntry]) -> Int {
        previews.firstIndex { $0.id == id } ?? 0
    }

    /// Collects the previews and builds the platform application around
    /// the preview window.
    public func setup() {
        let environment = ProcessInfo.processInfo.environment
        Self.file = environment["NUCLEANT_PREVIEW_FILE"].flatMap { $0.isEmpty ? nil : $0 }
        Self.previews = Self.previews(in: Self.file, from: Self.collect())
        Self.initialSelection = Self.index(of: environment["NUCLEANT_PREVIEW_SELECTED"], in: Self.previews)
        let app = AppRuntime(app: PreviewApp())
        app.setup()
        self.app = app
    }

    /// Runs the platform event loop, as `AppRuntime.run()` does for an app.
    public func run() {
        app?.run()
    }
}

/// The app a preview build runs: one window holding the browser.
struct PreviewApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Previews") {
            PreviewBrowser(
                previews: PreviewRuntime.previews,
                initialSelection: PreviewRuntime.initialSelection,
                file: PreviewRuntime.file
            )
        }
        .defaultSize(width: 900, height: 640)
    }
}

/// A row of tabs, one per preview, over the selected preview's view.
@View
struct PreviewBrowser {
    let previews: [_PreviewEntry]
    let initialSelection: Int
    /// The file the previews were picked from, if only one's are shown.
    var file: String? = nil
    /// The tab picked since launch; `initialSelection` until one is.
    @State private var picked: Int? = nil

    var body: some View {
        let selection = min(picked ?? initialSelection, max(previews.count - 1, 0))
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<previews.count) { index in
                    Button(previews[index].name) {
                        picked = index
                        PreviewRuntime.selectionChanged(previews[index].id)
                    }
                    .tint(index == selection ? .color(Color(hex: 0x4C8DFF)) : .fill)
                }
                Spacer()
            }
            .padding(horizontal: 10, vertical: 8)
            .background(ShapeStyle.secondaryBackground)

            if previews.isEmpty {
                Text(file.map { "No @Preview functions in \($0.split(separator: "/").last ?? "")" } ?? "No @Preview functions in this app")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                previews[selection].make()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ShapeStyle.background)
    }
}
