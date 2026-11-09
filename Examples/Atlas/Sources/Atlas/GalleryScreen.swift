//
//  GalleryScreen.swift
//  Atlas
//
//  The guide's front page: every destination as a poster card in a grid,
//  filtered by region or to the saved ones. Each card is a link that pushes
//  the destination, and is marked as the source its page zooms out of —
//  `.matchedTransitionSource(id:in:)`, clipped to the card's corners with
//  its deep colour behind, which also fills the page as it grows.
//

import NucleantUI

@View
struct GalleryScreen {
    let atlas: Atlas
    let zoom: Namespace.ID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Where next?")
                        .font(.system(size: 30, weight: .bold))
                    Text("\(atlas.shown.count) of \(atlas.destinations.count) destinations · \(atlas.saved.count) saved")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Filters(atlas: atlas)
                if atlas.shown.isEmpty {
                    Text("Nothing saved here yet. Open a destination and save it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 40)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], spacing: 16) {
                    ForEach(atlas.shown) { destination in
                        NavigationLink(value: destination.id) {
                            DestinationCard(destination: destination, isSaved: atlas.isSaved(destination.id))
                                .matchedTransitionSource(id: destination.id, in: zoom) { source in
                                    source
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .background(destination.palette.deep)
                                }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Atlas")
    }
}

/// The region chips and the saved switch.
@View
private struct Filters {
    let atlas: Atlas

    var body: some View {
        HStack(spacing: 8) {
            Chip(title: "All", count: atlas.count(in: nil), isOn: atlas.region == nil) {
                withAnimation(.smooth) { atlas.show(nil) }
            }
            ForEach(Region.allCases, id: \.self) { region in
                Chip(title: region.rawValue, count: atlas.count(in: region), isOn: atlas.region == region) {
                    withAnimation(.smooth) { atlas.show(region) }
                }
            }
            Spacer()
            Chip(title: "Saved", count: atlas.saved.count, isOn: atlas.showsSavedOnly) {
                withAnimation(.smooth) { atlas.toggleSavedOnly() }
            }
        }
    }
}

@View
private struct Chip {
    let title: String
    let count: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text("\(count)").font(.system(size: 12)).foregroundStyle(isOn ? ShapeStyle.color(Color.white.opacity(0.8)) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? ShapeStyle.color(.white) : .primary)
            .background(isOn ? ShapeStyle.color(.atlasAccent) : .fill)
            .clipShape(Capsule())
        }
    }
}

/// A destination's card: its poster over its name, country and tagline.
@View
struct DestinationCard {
    let destination: Destination
    let isSaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Poster(destination: destination)
                    .frame(height: 150)
                if isSaved {
                    Text("Saved")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.atlasAccent)
                        .clipShape(Capsule())
                        .padding(10)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(destination.name)
                    .font(.system(size: 18, weight: .bold))
                Text("\(destination.country) · \(destination.region.rawValue)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                Text(destination.tagline)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(2)
            }
            .foregroundStyle(Color.white)
            .padding(14)
            // Room for two lines of tagline, used or not: the cards in a
            // row line up.
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        }
    }
}

extension Color {
    /// The guide's one accent: chips that are on, the save button.
    static let atlasAccent = Color(hex: 0xE8505B)
}
