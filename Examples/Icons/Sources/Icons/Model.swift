//
//  Model.swift
//  Icons
//
//  The icon library: every icon in the app's Material folder, by category,
//  and how the browser is set to show them. `IconLibrary` is the
//  `@Observable` model — the scope, the search, the style, the ink, the
//  selection and the favourites change through it; an `Icon` is a record
//  inside it. The catalog is the folder's listing, read once at launch;
//  an icon's SVG is parsed the first time it is drawn, in each style, and
//  kept.
//

import Foundation
import NucleantUI
import Observation

// MARK: - Values

/// The five styles every Material icon is drawn in, each its own file.
enum IconStyle: CaseIterable, Hashable {
    case filled, outlined, round, sharp, twoTone

    var name: String {
        switch self {
        case .filled:   return "Filled"
        case .outlined: return "Outlined"
        case .round:    return "Round"
        case .sharp:    return "Sharp"
        case .twoTone:  return "Two Tone"
        }
    }

    /// The file's name after the icon's: `home.svg`, `home-outlined.svg`, …
    var suffix: String {
        switch self {
        case .filled:   return ""
        case .outlined: return "-outlined"
        case .round:    return "-round"
        case .sharp:    return "-sharp"
        case .twoTone:  return "-twotone"
        }
    }
}

/// What the icons are painted in: a color or a gradient over each one as
/// a template.
enum Ink: CaseIterable, Hashable {
    case primary, blue, purple, pink, orange, green, sunset

    var name: String {
        switch self {
        case .primary: return "Primary"
        case .blue:    return "Blue"
        case .purple:  return "Purple"
        case .pink:    return "Pink"
        case .orange:  return "Orange"
        case .green:   return "Green"
        case .sunset:  return "Sunset"
        }
    }

    var style: AnyShapeStyle {
        switch self {
        case .primary: return AnyShapeStyle(.primary)
        case .blue:    return AnyShapeStyle(Color(hex: 0x2F7CF6))
        case .purple:  return AnyShapeStyle(Color(hex: 0x8E5CF7))
        case .pink:    return AnyShapeStyle(Color(hex: 0xF0487A))
        case .orange:  return AnyShapeStyle(Color(hex: 0xF59E0B))
        case .green:   return AnyShapeStyle(Color(hex: 0x22B573))
        case .sunset:  return AnyShapeStyle(.linearGradient(colors: [Color(hex: 0xF59E0B), Color(hex: 0xF0487A), Color(hex: 0x8E5CF7)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

/// One icon: its folder, named after it, inside its category's.
struct Icon: Identifiable, Hashable {
    /// `"category/name"` — a few names are in more than one category.
    let id: String
    let name: String
    let category: String
    /// The styles it has a file for — nearly always all five.
    let styles: [IconStyle]

    /// `"chat_bubble"` as "Chat Bubble".
    var title: String {
        name.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// `style` if it has it, else the first it has.
    func resolved(_ style: IconStyle) -> IconStyle {
        styles.contains(style) ? style : (styles.first ?? .filled)
    }
}

struct IconCategory: Identifiable, Hashable {
    let id: String
    let icons: [Icon]

    var title: String { id == "av" ? "Audio & Video" : id.prefix(1).uppercased() + id.dropFirst() }
}

/// Where the grid is looking.
enum Scope: Hashable {
    case all
    case favorites
    case category(String)
}

// MARK: - The library

@MainActor
@Observable
final class IconLibrary {
    let categories: [IconCategory]
    let all: [Icon]

    var scope: Scope? = .all
    var search = ""
    var style = IconStyle.filled
    var ink = Ink.primary
    /// Each icon in its own colors rather than the ink — what tells the
    /// two-tone style's faded parts from the rest.
    var showsOriginalColors = false
    var tileSize = 104.0
    private(set) var selectedID: Icon.ID?
    private(set) var favorites: Set<Icon.ID> = []

    /// The Material folder in the app's resources.
    @ObservationIgnored private let folder: URL?
    /// Every SVG parsed so far, by file — drawing never changes a
    /// document, so one is shared by every view showing that file.
    @ObservationIgnored private var images: [String: SvgImage] = [:]

    init() {
        let folder = Bundle.module.url(forResource: "Material", withExtension: nil)
        self.folder = folder
        let files = FileManager.default
        var categories: [IconCategory] = []
        for category in (folder.flatMap { try? files.contentsOfDirectory(atPath: $0.path) } ?? []).sorted() {
            guard let categoryURL = folder?.appendingPathComponent(category),
                  let names = try? files.contentsOfDirectory(atPath: categoryURL.path) else { continue }
            let icons: [Icon] = names.sorted().compactMap { name in
                let present = Set((try? files.contentsOfDirectory(atPath: categoryURL.appendingPathComponent(name).path)) ?? [])
                let styles = IconStyle.allCases.filter { present.contains(name + $0.suffix + ".svg") }
                return styles.isEmpty ? nil : Icon(id: category + "/" + name, name: name, category: category, styles: styles)
            }
            if !icons.isEmpty {
                categories.append(IconCategory(id: category, icons: icons))
            }
        }
        self.categories = categories
        self.all = categories.flatMap(\.icons).sorted { $0.name < $1.name }
        // A few to start the Favorites list with.
        favorites = ["action/favorite", "action/home", "action/search", "content/send", "file/folder"]
        selectedID = all.first { $0.name == "favorite" }?.id ?? all.first?.id
    }

    // MARK: Reading

    /// `icon` in `style` — or the first style it has, when not that one.
    /// `nil` only for a file that is not an SVG.
    func image(_ icon: Icon, _ style: IconStyle) -> SvgImage? {
        let style = icon.resolved(style)
        let file = icon.id + "/" + icon.name + style.suffix + ".svg"
        if let image = images[file] { return image }
        guard let url = folder?.appendingPathComponent(file),
              let image = SvgImage(contentsOf: url) else { return nil }
        images[file] = image
        return image
    }

    /// The app's own icons — the sidebar's, the buttons' — by
    /// `"category/name"`, in the style the browser is set to.
    func chrome(_ id: Icon.ID, _ style: IconStyle? = nil) -> SvgImage? {
        guard let slash = id.firstIndex(of: "/") else { return nil }
        let icon = Icon(id: id, name: String(id[id.index(after: slash)...]), category: String(id[..<slash]), styles: IconStyle.allCases)
        return image(icon, style ?? self.style)
    }

    var selected: Icon? {
        guard let selectedID else { return nil }
        return all.first { $0.id == selectedID }
    }

    func isFavorite(_ icon: Icon) -> Bool { favorites.contains(icon.id) }

    var favoriteIcons: [Icon] { all.filter { favorites.contains($0.id) } }

    /// The scope's icons whose name holds every word of the search.
    var visibleIcons: [Icon] {
        let icons: [Icon]
        switch scope ?? .all {
        case .all:
            icons = all
        case .favorites:
            icons = favoriteIcons
        case .category(let id):
            icons = categories.first { $0.id == id }?.icons ?? []
        }
        let words = search.lowercased().split(separator: " ")
        guard !words.isEmpty else { return icons }
        return icons.filter { icon in
            let name = icon.name.replacingOccurrences(of: "_", with: " ")
            return words.allSatisfy { name.contains($0) }
        }
    }

    var scopeTitle: String {
        switch scope ?? .all {
        case .all: return "All Icons"
        case .favorites: return "Favorites"
        case .category(let id): return categories.first { $0.id == id }?.title ?? id
        }
    }

    /// The ink an icon is painted in, or `nil` for its own colors.
    var tint: AnyShapeStyle? { showsOriginalColors ? nil : ink.style }

    // MARK: Changing

    func select(_ icon: Icon) {
        selectedID = icon.id
    }

    func toggleFavorite(_ icon: Icon) {
        if favorites.contains(icon.id) {
            favorites.remove(icon.id)
        } else {
            favorites.insert(icon.id)
        }
    }
}
