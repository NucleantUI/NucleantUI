//
//  FixedSizeApp.swift
//  FixedSize
//
//  `.fixedSize()`, in the navigation bar and in a screen's content, with a
//  switch that turns it off everywhere at once to compare:
//
//  * The bar — a "Draft" status pill on the leading side and a "Publish
//    now" button on the trailing side. Narrow the window: fixed, they keep
//    their one line and the title truncates; not fixed, the bar squeezes
//    them and their labels wrap.
//  * Text in a column — `.fixedSize(horizontal: false, vertical: true)`
//    gives it every line it needs at the width it has, instead of
//    truncating to its share of the column's height.
//  * A row with a description and a "Download now" button — fixed, the
//    button keeps its label on one line and the description wraps instead.
//  * Two plan cards side by side, one short and one long —
//    `.fixedSize(horizontal: false, vertical: true)` makes the row as tall
//    as its tallest card, and both cards fill that height; not fixed, the
//    row takes all the height the screen has left.
//

import NucleantUI

@main
struct FixedSizeApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Fixed Size") {
            NavigationStack {
                DraftScreen()
            }
        }
        .defaultSize(width: 340, height: 760)
    }
}

@View
struct DraftScreen {
    @State private var isFixed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle("Fixed size", isOn: $isFixed)
            Text("Narrow the window and turn this off: the bar's pill and button, the download button and the plan cards lose their size to the room they are offered.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: isFixed)
            DownloadRow(isFixed: isFixed)
            PlanCards(isFixed: isFixed)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Spring release notes")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("Draft · saved")
                    .font(.footnote)
                    .padding(horizontal: 10, vertical: 4)
                    .background(Capsule().fill(Color(hex: 0xF2C94C, opacity: 0.35)))
                    .fixedSize(horizontal: isFixed, vertical: isFixed)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Publish now") {}
                    .fixedSize(horizontal: isFixed, vertical: isFixed)
            }
        }
    }
}

/// A description and a button beside it; the button must not wrap.
@View
struct DownloadRow {
    let isFixed: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline copy").font(.headline)
                Text("Every chapter and image, about 48 MB, to read without a connection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Download now") {}
                .fixedSize(horizontal: isFixed, vertical: isFixed)
        }
        // On the row, not the text in it: the whole row takes the height
        // the description needs, so the text doesn't spill out under it.
        .fixedSize(horizontal: false, vertical: isFixed)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.secondaryBackground))
    }
}

/// Two cards as tall as the taller of them.
@View
struct PlanCards {
    let isFixed: Bool

    var body: some View {
        HStack(spacing: 12) {
            PlanCard(name: "Free", detail: "Read online.")
            PlanCard(
                name: "Plus",
                detail: "Read offline, sync your highlights across devices, and get every new edition the day it comes out."
            )
        }
        .fixedSize(horizontal: false, vertical: isFixed)
    }
}

@View
struct PlanCard {
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.secondaryBackground))
    }
}
