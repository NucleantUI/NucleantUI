//
//  IconsApp.swift
//  Icons
//
//  A browser for nine hundred Material icons, every one an SVG file drawn
//  by `SvgView` — the way an icon catalog app works:
//
//  * the sidebar: all icons, the favourites, and each category, counted;
//  * the grid: the icons in the style picked above it (Filled, Outlined,
//    Round, Sharp, Two Tone), each a template painted in the chosen ink —
//    a color, or a gradient across the icon — or in its own colors, at the
//    tile size the slider sets, filtered by the search;
//  * the inspector: the selected icon large, in all five styles, at its own
//    size and resized, fitted in proportion into a box of another shape,
//    and in use — in buttons that hand it their tint, a tab bar, a list
//    row, under a badge — with the code that draws it.
//
//  The app's own controls are Material icons too, from the same library.
//

import NucleantUI

enum Theme {
    static let sidebar = ShapeStyle.dynamic(light: Color(hex: 0xEEEEF2), dark: Color(hex: 0x16181D))
    static let bar = ShapeStyle.dynamic(light: Color(hex: 0xF7F7F9), dark: Color(hex: 0x1B1D23))
    static let tile = ShapeStyle.dynamic(light: Color.white, dark: Color(hex: 0x22252C))
    static let accent = Color(hex: 0x2F7CF6)
    /// What an icon in its own colors — black — is shown on, in either
    /// mode.
    static let paper = Color.white
}

@View
struct IconsView {
    @State private var library = IconLibrary()
    @Environment(\.colorScheme) private var system

    var body: some View {
        let library = self.library
        HStack(spacing: 0) {
            Sidebar(library: library)
                .frame(width: 220)
                .frame(maxHeight: .infinity)
                .background(Theme.sidebar)
            Divider()
            IconGrid(library: library)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let icon = library.selected {
                Divider()
                Inspector(library: library, icon: icon)
                    .frame(width: 360)
                    .frame(maxHeight: .infinity)
                    .background(Theme.bar)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShapeStyle.secondaryBackground)
        .tint(Theme.accent)
        .colorScheme(AppearanceModel.shared.appearance.scheme ?? system)
    }
}

@main
struct IconsApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Icons") {
            IconsView()
        }
        .defaultSize(width: 1440, height: 860)
        .commands { AppearanceCommands() }
    }
}

// MARK: - Sidebar

/// All icons, the favourites, and the categories, each with its icon.
@View
struct Sidebar {
    @Bindable var library: IconLibrary

    /// The icon standing for each category in the list.
    private static let categoryIcons = [
        "action": "action/settings",
        "alert": "alert/warning",
        "av": "av/play_circle",
        "communication": "communication/chat",
        "content": "content/content_paste",
        "file": "file/folder",
        "navigation": "navigation/apps",
        "toggle": "toggle/toggle_on",
    ]

    var body: some View {
        let library = self.library
        List(selection: $library.scope) {
            Section("Library") {
                SidebarRow(image: library.chrome("navigation/apps"), title: "All Icons")
                    .tag(Scope.all)
                    .badge(library.all.count)
                SidebarRow(image: library.chrome("toggle/star"), title: "Favorites")
                    .tag(Scope.favorites)
                    .badge(library.favoriteIcons.count)
            }
            Section("Categories") {
                ForEach(library.categories) { category in
                    SidebarRow(
                        image: library.chrome(Self.categoryIcons[category.id] ?? category.icons[0].id),
                        title: category.title
                    )
                    .tag(Scope.category(category.id))
                    .badge(category.icons.count)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// An icon in the accent and a title.
@View
struct SidebarRow {
    let image: SvgImage?
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Glyph(image: image, size: 16, ink: .color(Theme.accent))
            Text(title)
                .lineLimit(1)
        }
    }
}

/// One SVG at `size` × `size`, as a template painted in `ink` — or, with
/// no ink, in its own colors, on paper. Nothing when there is no document.
@View
struct Glyph {
    let image: SvgImage?
    let size: Double
    let ink: ShapeStyle?

    var body: some View {
        if let image, let ink {
            SvgView(image)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(ink)
                .frame(width: size, height: size)
        } else if let image {
            SvgView(image)
                .resizable()
                .frame(width: size, height: size)
                .padding((size * 0.2).rounded())
                .background(RoundedRectangle(cornerRadius: (size * 0.2).rounded()).fill(Theme.paper))
        } else {
            Color.clear
                .frame(width: size, height: size)
        }
    }
}
