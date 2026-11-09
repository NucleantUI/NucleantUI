//
//  Model.swift
//  Atlas
//
//  The guide: destinations, each with a poster's palette and scene and a
//  handful of highlights, and the reader's saved list. One `@Observable`
//  class owns what changes — which are saved, and what the gallery shows —
//  and the views change it only through its methods.
//

import NucleantUI
import Observation

enum Region: String, CaseIterable, Hashable {
    case europe = "Europe"
    case asia = "Asia"
    case americas = "Americas"
    case africa = "Africa"
    case oceania = "Oceania"
}

/// What a destination's poster shows on its horizon.
enum Landscape: Hashable {
    case mountains
    case coast
    case desert
    case city
    case forest
}

/// A poster's colours: the sky from top to bottom, the sun, and the land.
struct Palette: Hashable {
    let skyTop: Color
    let skyBottom: Color
    let sun: Color
    let land: Color
    /// Behind the poster and the screen that zooms out of it.
    let deep: Color
}

struct Highlight: Hashable, Identifiable {
    let id: Int
    let title: String
    let kind: String
    let summary: String
    let detail: String
    let hours: String
}

struct Destination: Identifiable, Hashable {
    let id: Int
    let name: String
    let country: String
    let region: Region
    let landscape: Landscape
    let palette: Palette
    let tagline: String
    let about: String
    let bestMonths: String
    let language: String
    let currency: String
    let highlights: [Highlight]
}

/// A highlight of a destination, as a value a link pushes.
struct HighlightRoute: Hashable {
    let destination: Destination.ID
    let highlight: Highlight.ID
}

@MainActor
@Observable
final class Atlas {
    let destinations: [Destination]
    private(set) var saved: Set<Destination.ID> = []
    /// `nil` for every region.
    private(set) var region: Region?
    private(set) var showsSavedOnly = false

    init(destinations: [Destination]) {
        self.destinations = destinations
    }

    /// What the gallery shows, in the guide's order.
    var shown: [Destination] {
        destinations.filter { destination in
            (region == nil || destination.region == region)
                && (!showsSavedOnly || saved.contains(destination.id))
        }
    }

    func destination(_ id: Destination.ID) -> Destination? {
        destinations.first { $0.id == id }
    }

    func highlight(_ route: HighlightRoute) -> (Destination, Highlight)? {
        guard let destination = destination(route.destination),
              let highlight = destination.highlights.first(where: { $0.id == route.highlight })
        else { return nil }
        return (destination, highlight)
    }

    func isSaved(_ id: Destination.ID) -> Bool {
        saved.contains(id)
    }

    func toggleSaved(_ id: Destination.ID) {
        if saved.contains(id) {
            saved.remove(id)
        } else {
            saved.insert(id)
        }
    }

    func show(_ region: Region?) {
        self.region = region
    }

    func toggleSavedOnly() {
        showsSavedOnly.toggle()
    }

    func count(in region: Region?) -> Int {
        region.map { r in destinations.filter { $0.region == r }.count } ?? destinations.count
    }
}
