//
//  DestinationScreen.swift
//  Atlas
//
//  A destination's own page: its poster across the top, what it is, when to
//  go, and its highlights. The page zooms out of its card in the gallery —
//  `.navigationTransition(.zoom(sourceID:in:))`, set where the root
//  registers the destination — and back into it when popped. Each
//  highlight is a link whose page slides in the stack's own way.
//
//  The page draws its own back button: the stack's is hidden with
//  `.navigationBarBackButtonHidden()`, and an `ArrowBack`, the same chevron
//  as a shape, takes its place in a `.navigation` toolbar item, filled with
//  the destination's sun.
//

import NucleantUI

@View
struct DestinationScreen {
    let atlas: Atlas
    let destination: Destination
    @Environment(\.navigationRouter) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Poster(destination: destination)
                        .frame(height: 280)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(destination.name)
                            .font(.system(size: 38, weight: .bold))
                        Text("\(destination.country) · \(destination.region.rawValue)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .foregroundStyle(Color.white)
                    .padding(24)
                }
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        Text(destination.tagline)
                            .font(.system(size: 20, weight: .semibold))
                        Spacer()
                        SaveButton(isSaved: atlas.isSaved(destination.id)) {
                            withAnimation(.snappy) { atlas.toggleSaved(destination.id) }
                        }
                    }
                    Text(destination.about)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.8))
                    HStack(alignment: .top, spacing: 12) {
                        Fact(title: "Best time", value: destination.bestMonths)
                        Fact(title: "Language", value: destination.language)
                        Fact(title: "Currency", value: destination.currency)
                    }
                    Text("Highlights")
                        .font(.system(size: 20, weight: .bold))
                        .padding(.top, 8)
                    ForEach(destination.highlights) { highlight in
                        NavigationLink(value: HighlightRoute(destination: destination.id, highlight: highlight.id)) {
                            HighlightRow(highlight: highlight, accent: destination.palette.sun)
                        }
                    }
                }
                .foregroundStyle(Color.white)
                .padding(24)
            }
        }
        .background(destination.palette.deep)
        .navigationTitle(destination.name)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ArrowBack()
                    .fill(destination.palette.sun)
                    .frame(width: 20, height: 20)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                    .onTapGesture { router?.pop() }
            }
        }
    }
}

@View
private struct SaveButton {
    let isSaved: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isSaved ? "Saved" : "Save")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSaved ? .atlasAccent : Color.white.opacity(0.15))
                .clipShape(Capsule())
        }
    }
}

@View
private struct Fact {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(value)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

@View
private struct HighlightRow {
    let highlight: Highlight
    let accent: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(highlight.title)
                    .font(.system(size: 16, weight: .semibold))
                Text(highlight.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            Spacer()
            Text(highlight.kind)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
            Text("›")
                .font(.system(size: 20))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
