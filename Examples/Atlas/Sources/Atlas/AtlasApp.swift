//
//  AtlasApp.swift
//  Atlas
//
//  A travel guide, there to show a navigation stack's transitions doing
//  their job:
//
//  * A destination's page zooms out of its card in the gallery and shrinks
//    back into it on the way back: the card is marked with
//    `.matchedTransitionSource(id:in:)`, the page asks for
//    `.navigationTransition(.zoom(sourceID:in:))`, and both name the same
//    `@Namespace`, which the root owns.
//  * A highlight's page asks for nothing, so it slides in the stack's
//    `.automatic` way.
//  * The model is one `@Observable` class, `Atlas`, owned by the root
//    through `@State`; saving a destination or filtering the gallery goes
//    through its methods, and the cards fade and move under
//    `withAnimation` as the filter changes.
//

import NucleantUI

@View
struct AtlasRoot {
    @State private var atlas = Atlas(destinations: guide)
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            GalleryScreen(atlas: atlas, zoom: zoom)
                .navigationDestination(for: Destination.ID.self) { id in
                    if let destination = atlas.destination(id) {
                        DestinationScreen(atlas: atlas, destination: destination)
                            .navigationTransition(.zoom(sourceID: id, in: zoom))
                    }
                }
                .navigationDestination(for: HighlightRoute.self) { route in
                    if let found = atlas.highlight(route) {
                        HighlightScreen(destination: found.0, highlight: found.1)
                    }
                }
        }
        .colorScheme(.dark)
    }
}

@main
struct AtlasApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Atlas") {
            AtlasRoot()
        }
        .defaultSize(width: 960, height: 720)
    }
}
