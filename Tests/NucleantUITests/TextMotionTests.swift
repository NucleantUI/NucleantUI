//
//  TextMotionTests.swift
//  NucleantUITests
//
//  Text keeps its new size while it animates — it would reflow at every
//  frame otherwise — and travels by whichever of its edges and its middle
//  moved least: a caption whose text changes under an animation stays on
//  the edge it is aligned to, and one that only moves travels as any view
//  does.
//

import Foundation
import Observation
import Testing
@testable import NucleantUI

@MainActor
@Observable
private final class Caption {
    var text = "Circular"
    /// The height of what stands over the caption.
    var above = 10.0
}

/// A caption over a bar wider than it, aligned in the stack.
@View
private struct CaptionOverBar {
    let caption: Caption
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Color.blue.frame(width: 20, height: caption.above)
            Text(caption.text)
            Color.red.frame(width: 150, height: 10)
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite struct TextMotion {

        /// Where the caption is drawn.
        private func drawn(_ harness: Harness) throws -> Rect {
            let list = try #require(harness.host.windowContent)
            let drawn = list.commands.lazy.compactMap { command -> Rect? in
                guard case .text(let draw) = command else { return nil }
                return draw.frame
            }.first
            return try #require(drawn)
        }

        /// The caption in the frames of an animated change, from the one
        /// that makes it on.
        private func animating(_ harness: Harness, _ change: () -> Void) async throws -> [Rect] {
            withAnimation(.linear(duration: 0.5), change)
            harness.host.update()
            var shown = [try drawn(harness)]
            for _ in 0..<6 {
                await harness.frames(1)
                shown.append(try drawn(harness))
            }
            return shown
        }

        @Test(arguments: [HorizontalAlignment.leading, .center, .trailing])
        func changedItStaysOnTheEdgeItIsAlignedTo(alignment: HorizontalAlignment) async throws {
            let caption = Caption()
            let harness = Harness(CaptionOverBar(caption: caption, alignment: alignment))
            await harness.frames(2)
            let before = try drawn(harness)

            let shown = try await animating(harness) { caption.text = "Grid" }
            let rest = try #require(shown.last)
            #expect(rest.width < before.width, "the new text is shorter")
            let edge: (Rect) -> Double = switch alignment {
            case .leading: \.minX
            case .trailing: \.maxX
            default: \.midX
            }
            #expect(shown.allSatisfy { edge($0) == edge(rest) && $0.minY == rest.minY }, "\(shown.map(\.minX))")
        }

        @Test func movedItTravelsFromWhereItWas() async throws {
            let caption = Caption()
            let harness = Harness(CaptionOverBar(caption: caption, alignment: .leading))
            await harness.frames(2)
            let before = try drawn(harness)

            let shown = try await animating(harness) { caption.above = 60 }
            #expect(shown.first == before, "it sets off from where it was")
            #expect(zip(shown, shown.dropFirst()).allSatisfy { $0.minY < $1.minY }, "\(shown.map(\.minY))")
            #expect(shown.allSatisfy { $0.minX == before.minX })
        }
    }
}
