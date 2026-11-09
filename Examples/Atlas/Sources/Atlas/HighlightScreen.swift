//
//  HighlightScreen.swift
//  Atlas
//
//  One highlight of a destination. It sets no transition of its own, so it
//  slides in the stack's `.automatic` way — over the destination page,
//  which drifts aside and dims.
//

import NucleantUI

@View
struct HighlightScreen {
    let destination: Destination
    let highlight: Highlight

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Tag(text: highlight.kind, color: destination.palette.sun)
                    Tag(text: highlight.hours, color: Color.white.opacity(0.7))
                }
                Text(highlight.title)
                    .font(.system(size: 32, weight: .bold))
                Text(highlight.summary)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(highlight.detail)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.75))
                Poster(destination: destination)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 8)
                Text("In \(destination.name), \(destination.country)")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .foregroundStyle(Color.white)
            .padding(24)
        }
        .background(destination.palette.deep)
        .navigationTitle(highlight.title)
    }
}

@View
private struct Tag {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
    }
}
