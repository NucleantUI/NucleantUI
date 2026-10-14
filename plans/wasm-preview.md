# Create self updating wasm host for preview marked content made with NucleantUI






```swift
#Preview("preview0") {
    Color.red
}

#Preview("preview1") {
    Text("hello")
}

#Preview("preview2") {
    Button("hello2") {
        print("preview button clicked")
    }
}
```

```swift
public struct PreviewRuntime {
    @MainActor static var previews: [Int:AnyView] = [:]

    @MainActor
    public static func addPreview(key: Int, view: AnyView) { // key == hash of viewID
        // #Preview somehow calls this with the clossure content as view input for AnyView
        // and creates Tabbed view with each preview entry
        // so you can switch between previews like xcode + swiftui live preview
    } 

    // setup + run function
    // which launches the app with previews instead of body from App 

}


```


in 

```swift
extension NucleantApp {
    #if NUCLEANT_PREVIEW
    public static func main() {
        let runtime = PreviewRuntime()
        runtime.setup()
        runtime.run()
    }
    #else
    /// What `@main` calls. Builds the platform application, presents the
    /// scene's windows on launch, and runs the event loop.
    public static func main() {
        let runtime = AppRuntime(app: Self())
        runtime.setup()
        runtime.run()
    }
    #endif
}
```


## Plan (2026-10-12)

The loop: edit a Swift file → save → the editor rebuilds the app for
wasm with `NUCLEANT_PREVIEW` on → the panel beside the editor reloads
and shows the file's previews. Four pieces, each usable on its own:

1. **Registration** — how a preview declared in some file reaches
   `PreviewRuntime` with no static initializers in Swift.
2. **`PreviewRuntime`** — the sketch above: collects the previews and
   shows them in a window with a switcher, instead of the app's scenes.
3. **The switch** — `NUCLEANT_PREVIEW` turns 2 on, and only in a
   preview build.
4. **The host** — a VS Code extension at the root of the workspace
   (`NucleantDevelopment/nucleant-preview/`, written as the example):
   watches saves, runs the build, serves the page, reloads it.

### 1. Registration: section records (verified)

Swift has no static initializers, so nothing can call
`addPreview(key:view:)` at load time on its own. What does work, with
the 6.3.3 toolchain on macOS **and** wasm32-wasip1 (checked with a
scratch package, run under the toolchain's `wasmkit`): each preview
becomes a record placed in a named linker section, and the runtime
walks the section at startup.

```swift
// what a preview expands to (macro output; the section name differs per
// object format, so the declaration is emitted once per branch)
#if os(macOS) || os(iOS)
@section("__DATA,nucleant_prev") @used
let $preview_fMu_: PreviewRecord = ({ out in
    out.initializeMemory(as: PreviewEntry.self,
                         to: PreviewEntry(name: "preview1", fileID: #fileID, line: 12) { Text("hello") })
})
#else                                   // ELF (Linux, Android) and wasm
@section("nucleant_previews") @used
let $preview_fMu_: PreviewRecord = /* same */
#endif

public typealias PreviewRecord = @convention(c) (UnsafeMutableRawPointer) -> Void
```

* `@section` / `@used` (SE-0492) are accepted by 6.3.3 with no feature
  flag. The value must be statically initialisable: a `@convention(c)`
  closure literal is; a `String` or a Swift closure is not — hence the
  record is one C function pointer that *writes* the real
  `PreviewEntry` (name, `fileID`, line, the `() -> AnyView` maker) into
  memory the runtime hands it. Same trick swift-testing uses for
  `@Test` discovery.
* The section's bounds come from the linker: `section$start$__DATA$…`
  / `section$end$__DATA$…` on Mach-O, `__start_…` / `__stop_…` on ELF
  and wasm-ld (weak, so a module with no previews links and reads
  zero). Those names cannot be spelled from Swift, so a tiny C target
  in NucleantUI returns the two pointers, one `#if __APPLE__` inside
  the C file.
* A preview's id is `fileID:line` (stable across rebuilds as long as
  the lines above it don't move) — the user's `key: Int` becomes that.
  `PreviewRuntime` keeps the *maker*, not a built `AnyView`, so only
  the selected preview is built, and switching away and back starts it
  with fresh `@State`. `AnyView` is right here: the set of previews is
  heterogeneous and unbounded, the exact boundary case CLAUDE.md allows.

### 1b. Decided: `@Preview` on a function, not `#Preview { }`

`#Preview { Counter() }` cannot construct a `@View` struct — the blocker
from `preview-macro.md`, and not Xcode's: our own freestanding macro hits
it too (reproduced with a stand-in member macro that adds `init()`):

```
#Prev("counter") { Counter() }
error: 'Counter' cannot be constructed because it has no accessible initializers
```

A macro's arguments are type-checked before expansion, without the
members other macros generate, and `@View` always generates the init (it
carries `_viewID: ViewID = …`). So previews are functions, with the macro
attached — the body is then an ordinary declaration, checked after
expansion:

```swift
@Preview("Progress ring")
@MainActor
func progressRingPreview() -> some View {
    ProgressRing(progress: 0.4, color: .red)
}
```

* File scope, no parameters, not `async`/`throws`, returns its view; the
  macro says so otherwise. The tab is the name given, or the function's.
* `@MainActor` is needed: `View` is main-actor isolated, so a
  nonisolated function cannot call a view's init in Swift 6 mode, and an
  attached macro cannot add isolation to the function it is attached to.

### 1c. Implemented (2026-10-12)

* `Sources/CNucleantPreview/` — the section bounds (`#if __APPLE__` in
  the C file only). An app with no records links and reads an empty range
  (checked with ld64, `-dead_strip` included).
* `Sources/NucleantUIMacros/PreviewMacro.swift` — `@Preview`: a peer
  `private let` record, wrapped in `#if NUCLEANT_PREVIEW`.
* `Sources/NucleantUI/Preview/` — `Preview.swift` (the macro,
  `_PreviewRecord`, `_PreviewEntry`), `PreviewRuntime.swift` (collect,
  `addPreview`, `setup`/`run` through an `AppRuntime` of its own
  `PreviewApp`, and `PreviewBrowser`: a row of tab buttons over the
  selected preview).
* `App.swift` — `main()` as sketched above, `#if NUCLEANT_PREVIEW`.
* Tests: `NucleantUIMacrosTests/PreviewMacroTests` (expansions,
  refusals); `NucleantUITests/PreviewTests` (records read from the
  section in source order, `addPreview`, the browser shows the first
  preview) — that test target builds with `NUCLEANT_PREVIEW` defined.
* Example: Pomodoro has previews of its clock face, progress rings, plan
  panel and whole screen.

### 2. `PreviewRuntime`

As sketched: `setup()` walks the section, builds the entry list,
sorted by `fileID` then line; `run()` brings up the platform app (same
`NucleantApplication` path `AppRuntime` uses) with one window whose root
is a switcher — the previews as tabs/sidebar, the selected one's
`AnyView` filling the rest.

* **Which preview is shown** survives a reload (implemented): the
  runtime opens the tab `NUCLEANT_PREVIEW_SELECTED` names (`fileID#name`,
  not the line, which moves with edits; the first tab if it is gone) and
  prints `NUCLEANT_PREVIEW_SELECTED=<id>` when the tab changes. No
  storage or DOM bridge of its own — env in, stdout out, the same on
  every platform; the launcher keeps the last line. In the browser the
  extension does: its page script catches the line on `console.log`
  (where WASI stdout goes), the extension stores it per app (workspace
  state) and adds it to `runNucleantApp({ env })` in every `index.html`
  it serves.
* **Previews of the file in the editor** (implemented): with
  `NUCLEANT_PREVIEW_FILE` set to a source file's path, the runtime shows
  only the previews declared in it; unset, all of the app's. The record
  carries the file's `#filePath` next to its `#fileID` (the macro asks
  its expansion context for both), so the runtime compares paths — the
  build holds every file's previews, and switching files is a relaunch
  with another environment, not a rebuild. (A compile-time switch could
  not do this: a macro cannot read the environment and `#if` cannot
  compare strings.) The extension sets it to the focused file when that
  file belongs to the package and has a `@Preview` in it, and keeps the
  open tab per file. A lock (title-bar button) stops it following the
  editor: the panel stays on its file through focus changes, and builds
  from saves elsewhere still reload it.
* `addPreview(key:view:)` stays public for previews registered by hand
  (tests, tools), next to the section walk.

### 3. The switch: `NUCLEANT_PREVIEW`

Give the define to **every** module of the build, not just NucleantUI,
through the toolset — not through `Package.swift`:

* `build_wasm_app.py` already passes a toolset for the wasm build
  only (it keeps flags off the host build of the `@View` plugin). In
  preview mode it adds `-DNUCLEANT_PREVIEW` to
  `swiftCompiler.extraCLIOptions`. NucleantUI's `NucleantApp.main()`
  sees it (the `#if` above), and so does the app's own module — so the
  macro can wrap its record in `#if NUCLEANT_PREVIEW` and a normal
  build carries no preview records at all. A define set only in
  NucleantUI's manifest would not reach the app's module, and the
  records would ship in every build.
* Preview builds get their own scratch path
  (`.build/wasm-preview`, next to `.build/wasm`): flipping a define
  for every module rebuilds everything, so sharing one scratch would
  rebuild the whole graph each time you switch between running the
  app and previewing it — and would race a normal build of the same
  example.
* So: `build_wasm_app.py` has a preview mode (implemented) — on with
  `--preview` or `NUCLEANT_PREVIEW=1` in its environment: the extra
  define, the separate scratch, the page in `.build/wasm-preview-app`.
  Additive; a run without it is what it was.
* Native (macOS) previews later: the same toolset define through
  `swift build --toolset`, same `PreviewRuntime`, a normal window.

### 4. The host: VS Code extension (`nucleant-preview/`)

Plain JS, no build step. Two buttons in the editor title bar of a Swift
file:

* **Run App to the Side** — the app as `@main` runs it
  (`build_wasm_app.py`, page in `.build/wasm-live/<Product>`).
* **Show Previews to the Side** — `build_wasm_app.py --preview`, page in
  `.build/wasm-preview-app/<Product>`.

Both find the nearest `Package.swift` above the file, its executable
products (`swift package dump-package`, executable targets included),
and `build_wasm_app.py` by walking up to a sibling `NucleantApplication`.

* **Trigger**: saving a `.swift` / `Package.swift` anywhere in the
  development tree, `.build` ignored; debounced; a save during a build
  queues exactly one more build.
* **Server**: its own local HTTP server (random port, `no-store`) over
  the page directory, alive across builds. It adds a script to
  `index.html`: progress (a bar and a label at the top left, from
  SwiftPM's `[n/m]` lines), the compiler's `error:` lines when a build
  fails (the last good build keeps running underneath), a reload when a
  build lands — none when nothing relinked. A `.wasm` rebuilt outside the
  extension also clears a failure and reloads.
* **Page reports**: the page posts its WebGPU/JSPI support, the app
  starting, a sampled frame (drawn or blank), console errors and
  uncaught exceptions back; they are logged as `[page]` lines.
* **Panel**: a webview beside the editor holding the page in an iframe,
  kept alive while hidden; the status bar and the panel title show the
  build's progress. The page asks the panel to reload it; for previews
  the panel loads the new page in a second iframe underneath and drops
  the old one once the new one has drawn (or failed, or after 20 s), so
  the last frame stays up instead of a black window while the module
  loads. The app reloads in place. Inside the panel the page lets the
  app focus its window only while the panel has the keyboard, so a reload
  doesn't take it from the editor. `Open Preview in Browser` opens the same page in a
  browser.
* **Verified in VS Code 1.139.1** (`nucleant-preview/test/run.js`, a
  real VS Code with its own profile): WebGPU (a real adapter) and JSPI
  work in the webview, and Pomodoro and Finder start and draw.

### Next

* Follow the cursor: open the preview nearest the cursor's line.
* Native (macOS) previews: the same define through `swift build
  --toolset`, same `PreviewRuntime`, a normal window.
