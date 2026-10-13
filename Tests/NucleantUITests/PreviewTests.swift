//
//  PreviewTests.swift
//  NucleantUITests
//
//  `@Preview` functions reach `PreviewRuntime` through their linker-section
//  records (this target builds with NUCLEANT_PREVIEW, as an app's preview
//  build does), one file's previews can be picked out by path, and the
//  browser shows the selected one.
//

import Testing
@testable import NucleantUI

@Preview("Greeting")
@MainActor
func greetingPreview() -> some View {
    Text("hello")
}

@Preview
@MainActor
func swatchPreview() -> some View {
    Color.red
        .frame(width: 40, height: 40)
}

/// Notes in `log` when it appears, under `name`.
@View
struct AppearingPreview {
    let name: String
    let log: Log

    var body: some View {
        Color.gray
            .onAppear { log(name) }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct PreviewTests {

        /// This file's previews, as the runtime collects them.
        static func ownPreviews() -> [_PreviewEntry] {
            PreviewRuntime.collect().filter { $0.fileID == "NucleantUITests/PreviewTests.swift" }
        }

        @Test func everyPreviewFunctionIsCollectedInSourceOrder() {
            let previews = Self.ownPreviews()
            #expect(previews.map(\.name) == ["Greeting", "swatchPreview"])
            #expect(previews.map(\.line) == [14, 20])
        }

        @Test func eachPreviewKnowsTheFileItIsDeclaredIn() {
            #expect(Self.ownPreviews().map(\.filePath) == [#filePath, #filePath])
        }

        @Test func aFileShowsOnlyThePreviewsDeclaredInIt() {
            let all = [
                _PreviewEntry(name: "One", fileID: "App/A.swift", filePath: "/app/A.swift", line: 1) { Text("one") },
                _PreviewEntry(name: "Two", fileID: "App/B.swift", filePath: "/app/B.swift", line: 1) { Text("two") },
                _PreviewEntry(name: "Three", fileID: "App/B.swift", filePath: "/app/B.swift", line: 9) { Text("three") },
            ]
            #expect(PreviewRuntime.previews(in: "/app/B.swift", from: all).map(\.name) == ["Two", "Three"])
            #expect(PreviewRuntime.previews(in: nil, from: all).map(\.name) == ["One", "Two", "Three"])
            #expect(PreviewRuntime.previews(in: "/app/C.swift", from: all).isEmpty)
            // This file's, from everything linked into the test target.
            #expect(PreviewRuntime.previews(in: #filePath, from: PreviewRuntime.collect()).map(\.name) == ["Greeting", "swatchPreview"])
        }

        @Test func anAddedPreviewIsCollectedAndMakesItsView() async throws {
            let log = Log()
            PreviewRuntime.addPreview("Added", fileID: "Added.swift", filePath: "/Added.swift", line: 1) {
                AppearingPreview(name: "added", log: log)
            }
            let added = try #require(PreviewRuntime.collect().first { $0.fileID == "Added.swift" })
            #expect(added.name == "Added")
            let harness = Harness(added.make())
            await harness.settle()
            #expect(log.take() == ["added"])
        }

        @Test func theBrowserShowsOnlyTheFirstPreviewAtLaunch() async {
            let log = Log()
            let previews = [
                _PreviewEntry(name: "First", fileID: "A.swift", filePath: "/A.swift", line: 1) { AppearingPreview(name: "first", log: log) },
                _PreviewEntry(name: "Second", fileID: "A.swift", filePath: "/A.swift", line: 2) { AppearingPreview(name: "second", log: log) },
            ]
            let harness = Harness(PreviewBrowser(previews: previews, initialSelection: 0), size: Size(width: 400, height: 300))
            await harness.settle()
            #expect(log.take() == ["first"])
        }

        @Test func theBrowserOpensOnTheInitialSelection() async {
            let log = Log()
            let previews = [
                _PreviewEntry(name: "First", fileID: "A.swift", filePath: "/A.swift", line: 1) { AppearingPreview(name: "first", log: log) },
                _PreviewEntry(name: "Second", fileID: "A.swift", filePath: "/A.swift", line: 2) { AppearingPreview(name: "second", log: log) },
            ]
            let harness = Harness(PreviewBrowser(previews: previews, initialSelection: 1), size: Size(width: 400, height: 300))
            await harness.settle()
            #expect(log.take() == ["second"])
        }

        @Test func aSelectionIsFoundAgainByFileAndTitleNotLine() {
            let previews = Self.ownPreviews()
            #expect(previews[1].id == "NucleantUITests/PreviewTests.swift#swatchPreview")
            // As after an edit above it: same file and title, another line.
            let moved = [
                _PreviewEntry(name: "Greeting", fileID: "NucleantUITests/PreviewTests.swift", filePath: "/NucleantUITests/PreviewTests.swift", line: 40) { Text("hello") },
                _PreviewEntry(name: "swatchPreview", fileID: "NucleantUITests/PreviewTests.swift", filePath: "/NucleantUITests/PreviewTests.swift", line: 46) { Text("swatch") },
            ]
            #expect(PreviewRuntime.index(of: previews[1].id, in: moved) == 1)
            #expect(PreviewRuntime.index(of: "Gone.swift#Removed", in: moved) == 0)
            #expect(PreviewRuntime.index(of: nil, in: moved) == 0)
        }
    }
}
