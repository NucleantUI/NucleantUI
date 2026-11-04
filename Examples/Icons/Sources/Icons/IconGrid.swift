//
//  IconGrid.swift
//  Icons
//
//  The icons of the scope as a `LazyVGrid` of tiles, as many columns as fit
//  at the tile size. Each tile is an `SvgView` resized to a share of the
//  tile — the same document drawn sharp at every size the slider gives it —
//  painted as a template in the ink, or in its own colors. Of nine hundred
//  tiles, only those near the visible part are built, so only their SVGs
//  are ever parsed.
//

import NucleantUI

@View
struct IconGrid {
    let library: IconLibrary

    var body: some View {
        let library = self.library
        let icons = library.visibleIcons
        VStack(spacing: 0) {
            GridBar(library: library, count: icons.count)
            StyleBar(library: library)
            Divider()
            if icons.isEmpty {
                VStack(spacing: 10) {
                    Glyph(image: library.chrome("action/search"), size: 40, ink: .secondary)
                    Text(library.search.isEmpty ? "No Icons" : "No icons match “\(library.search)”")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: library.tileSize), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(icons) { icon in
                            IconTile(library: library, icon: icon)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
}

/// The scope's title and count, the tile size, and the search.
@View
struct GridBar {
    @Bindable var library: IconLibrary
    let count: Int

    var body: some View {
        let library = self.library
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(library.scopeTitle)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                Text("\(count) icons")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Glyph(image: library.chrome("navigation/apps"), size: 12, ink: .secondary)
                Slider(value: $library.tileSize, in: 72...200)
                    .frame(width: 130)
                Glyph(image: library.chrome("navigation/apps"), size: 20, ink: .secondary)
            }
            SearchField(library: library)
                .frame(width: 240)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bar)
    }
}

/// A text field between a search icon and a clear button.
@View
struct SearchField {
    @Bindable var library: IconLibrary

    var body: some View {
        let library = self.library
        HStack(spacing: 6) {
            Glyph(image: library.chrome("action/search"), size: 16, ink: .secondary)
            TextField("Search icons", text: $library.search)
                .textFieldStyle(.plain)
            if !library.search.isEmpty {
                Button(action: { library.search = "" }) {
                    SvgView(library.chrome("navigation/close")!)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 14, height: 14)
                }
                .tint(ShapeStyle.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(ShapeStyle.fill))
    }
}

/// One icon over its name. Clicking selects it; its menu (and the star)
/// adds it to the favourites or takes it out.
@View
struct IconTile {
    let library: IconLibrary
    let icon: Icon

    var body: some View {
        let library = self.library
        let icon = self.icon
        let isSelected = library.selectedID == icon.id
        let size = library.tileSize
        VStack(spacing: 6) {
            Glyph(image: library.image(icon, library.style), size: (size * 0.36).rounded(), ink: library.tint)
                .frame(maxHeight: .infinity)
            Text(icon.title)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? ShapeStyle.color(Theme.accent) : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .padding(.horizontal, 6)
        .frame(height: size)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? ShapeStyle.color(Theme.accent.opacity(0.16)) : Theme.tile))
        .overlay(alignment: .topTrailing) {
            if library.isFavorite(icon) {
                Glyph(image: library.chrome("toggle/star", .filled), size: 13, ink: .color(Color(hex: 0xF5B400)))
                    .padding(6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { library.select(icon) }
        .contextMenu {
            Button(library.isFavorite(icon) ? "Remove from Favorites" : "Add to Favorites") {
                library.toggleFavorite(icon)
            }
            Button("Show in Inspector") { library.select(icon) }
        }
    }
}

/// The style the icons are drawn in, the ink they are painted in, and
/// their own colors instead.
@View
struct StyleBar {
    @Bindable var library: IconLibrary

    var body: some View {
        let library = self.library
        HStack(spacing: 6) {
            Picker("Style", selection: $library.style) {
                ForEach(IconStyle.allCases, id: \.self) { style in
                    Text(style.name).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 440, alignment: .leading)
            Spacer()
            ForEach(Ink.allCases, id: \.self) { ink in
                InkSwatch(ink: ink, isSelected: library.ink == ink && !library.showsOriginalColors) {
                    library.ink = ink
                    library.showsOriginalColors = false
                }
            }
            Toggle("Original colors", isOn: $library.showsOriginalColors)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Theme.bar)
    }
}

/// A circle filled with the ink, ringed when it is the one in use.
@View
struct InkSwatch {
    let ink: Ink
    let isSelected: Bool
    let choose: () -> Void

    var body: some View {
        Circle()
            .fill(ink.style)
            .frame(width: 18, height: 18)
            .padding(3)
            .overlay(Circle().stroke(isSelected ? Theme.accent : .clear, lineWidth: 2))
            .contentShape(Circle())
            .onTapGesture(perform: choose)
    }
}
