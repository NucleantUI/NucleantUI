//
//  Inspector.swift
//  Icons
//
//  The selected icon, and what an `SvgView` does with it:
//
//  * large, resizable and fitted to the preview, in the ink;
//  * in each of its styles, one click from becoming the browser's;
//  * at the document's own size (24 points, not `.resizable()`) and
//    resized — every size the same document, drawn sharp;
//  * in a box of another shape, where it keeps its proportions and sits
//    centered;
//  * in its own colors, as a template in a color and in a gradient, faded
//    and turned;
//  * in use: buttons whose tint reaches a template icon in their label,
//    a filled button, a tab bar, a settings row and a badge;
//  * and the code that draws it.
//

import NucleantUI

@View
struct Inspector {
    let library: IconLibrary
    let icon: Icon

    var body: some View {
        let library = self.library
        let icon = self.icon
        let image = library.image(icon, library.style)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Preview(library: library, icon: icon, image: image)
                if let image {
                    InspectorSection(title: "Styles") {
                        StylesRow(library: library, icon: icon)
                    }
                    InspectorSection(title: "Sizes") {
                        SizesRow(image: image, ink: library.tint)
                    }
                    InspectorSection(title: "In any box, in proportion") {
                        FittingRow(image: image, ink: library.tint)
                    }
                    InspectorSection(title: "Rendering") {
                        RenderingRow(image: image)
                    }
                    InspectorSection(title: "In use") {
                        InUse(library: library, image: image, title: icon.title)
                    }
                    InspectorSection(title: "Code") {
                        CodeSample(icon: icon, style: icon.resolved(library.style))
                    }
                }
            }
            .padding(16)
        }
    }
}

/// A heading over its content.
@View
struct InspectorSection<Content: View> {
    let title: String
    let content: Content

    init(title: String, _viewID: ViewID = #viewID, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self._viewID = _viewID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// The icon as large as the panel allows, its name, and the favourite
/// star.
@View
struct Preview {
    let library: IconLibrary
    let icon: Icon
    let image: SvgImage?

    var body: some View {
        let library = self.library
        let icon = self.icon
        let isFavorite = library.isFavorite(icon)
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(library.tint == nil ? AnyShapeStyle(Theme.paper) : AnyShapeStyle(Theme.tile))
                if let image {
                    SvgView(image)
                        .resizable()
                        .renderingMode(library.tint == nil ? .original : .template)
                        .foregroundStyle(library.tint ?? AnyShapeStyle(.primary))
                        .scaledToFit()
                        .padding(36)
                }
            }
            .frame(height: 200)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(icon.title)
                        .font(.system(size: 18, weight: .bold))
                    Text("\(icon.category) · \(icon.name) · \(icon.resolved(library.style).name)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: { library.toggleFavorite(icon) }) {
                    SvgView(library.chrome(isFavorite ? "toggle/star" : "toggle/star_border", .round)!)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 24, height: 24)
                }
                .tint(isFavorite ? Color(hex: 0xF5B400) : Color(white: 0.55))
            }
        }
    }
}

/// The five styles, each a click from becoming the browser's.
@View
struct StylesRow {
    let library: IconLibrary
    let icon: Icon

    var body: some View {
        let library = self.library
        let icon = self.icon
        HStack(spacing: 6) {
            ForEach(icon.styles, id: \.self) { style in
                let isCurrent = icon.resolved(library.style) == style
                VStack(spacing: 5) {
                    Glyph(image: library.image(icon, style), size: 28, ink: library.tint)
                    Text(style.name)
                        .font(.system(size: 10))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(isCurrent ? AnyShapeStyle(Theme.accent.opacity(0.16)) : AnyShapeStyle(Theme.tile)))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { library.style = style }
            }
        }
    }
}

/// The document's own size — no `.resizable()` — and the same document
/// resized.
@View
struct SizesRow {
    let image: SvgImage
    let ink: AnyShapeStyle?

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(spacing: 6) {
                if let ink {
                    SvgView(image)
                        .renderingMode(.template)
                        .foregroundStyle(ink)
                } else {
                    SvgView(image)
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.paper))
                }
                Caption(text: "own \(Int(image.size.width))")
            }
            ForEach([16.0, 32, 48, 64], id: \.self) { size in
                VStack(spacing: 6) {
                    Glyph(image: image, size: size, ink: ink)
                    Caption(text: "\(Int(size))")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `.resizable()` in boxes wider and taller than the icon: the box is
/// shaded, the icon fills as much of it as fits and is centered.
@View
struct FittingRow {
    let image: SvgImage
    let ink: AnyShapeStyle?

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            ForEach([Size(width: 128, height: 44), Size(width: 44, height: 88), Size(width: 72, height: 72)], id: \.self) { box in
                VStack(spacing: 6) {
                    SvgView(image)
                        .resizable()
                        .renderingMode(ink == nil ? .original : .template)
                        .foregroundStyle(ink ?? AnyShapeStyle(.primary))
                        .frame(width: box.width, height: box.height)
                        .background(RoundedRectangle(cornerRadius: 4).fill(ink == nil ? Theme.paper : Theme.accent.opacity(0.14)))
                    Caption(text: "\(Int(box.width)) × \(Int(box.height))")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The same document drawn five ways.
@View
struct RenderingRow {
    let image: SvgImage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RenderingCell(caption: "Original") {
                // Its own colors — black — on a light card in either mode.
                SvgView(image).resizable()
                    .frame(width: 32, height: 32)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
            }
            RenderingCell(caption: "Tinted") {
                SvgView(image).resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
            }
            RenderingCell(caption: "Gradient") {
                SvgView(image).resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Ink.sunset.style)
                    .frame(width: 32, height: 32)
            }
            RenderingCell(caption: "Faded") {
                SvgView(image).resizable()
                    .renderingMode(.template)
                    .frame(width: 32, height: 32)
                    .opacity(0.35)
            }
            RenderingCell(caption: "Turned") {
                SvgView(image).resizable()
                    .renderingMode(.template)
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(30))
            }
        }
    }
}

@View
struct RenderingCell<Content: View> {
    let caption: String
    let content: Content

    init(caption: String, _viewID: ViewID = #viewID, @ViewBuilder content: () -> Content) {
        self.caption = caption
        self.content = content()
        self._viewID = _viewID
    }

    var body: some View {
        VStack(spacing: 6) {
            content
                .frame(height: 44)
            Caption(text: caption)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The icon where an app would put it.
@View
struct InUse {
    let library: IconLibrary
    let image: SvgImage
    let title: String
    @State private var tab = 0
    @State private var taps = 0

    var body: some View {
        let library = self.library
        let image = self.image
        VStack(alignment: .leading, spacing: 12) {
            // A button hands its tint to its label as the foreground, so a
            // template icon in it takes the tint with the text.
            HStack(spacing: 14) {
                Button(action: { taps += 1 }) {
                    HStack(spacing: 6) {
                        SvgView(image).resizable()
                            .renderingMode(.template)
                            .frame(width: 18, height: 18)
                        Text(taps == 0 ? title : "\(title) ×\(taps)")
                    }
                }
                Button(action: { taps += 1 }) {
                    HStack(spacing: 6) {
                        SvgView(image).resizable()
                            .renderingMode(.template)
                            .frame(width: 16, height: 16)
                        Text("Filled")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.accent))
                }
                Button(action: { taps += 1 }) {
                    SvgView(image).resizable()
                        .renderingMode(.template)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Color.white)
                        .padding(8)
                        .background(Circle().fill(Color(hex: 0xF0487A)))
                }
            }

            // A tab bar: the icon as the first tab, three more beside it.
            HStack(spacing: 0) {
                TabItem(image: image, title: "This", isSelected: tab == 0) { tab = 0 }
                TabItem(image: library.chrome("action/home"), title: "Home", isSelected: tab == 1) { tab = 1 }
                TabItem(image: library.chrome("action/search"), title: "Search", isSelected: tab == 2) { tab = 2 }
                TabItem(image: library.chrome("action/settings"), title: "Settings", isSelected: tab == 3) { tab = 3 }
            }
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.tile))

            // A settings row: white on a colored square, a chevron after.
            HStack(spacing: 10) {
                SvgView(image).resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x8E5CF7)))
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(image: library.chrome("navigation/chevron_right"), size: 18, ink: AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.tile))

            // Under a badge.
            HStack(spacing: 18) {
                Glyph(image: image, size: 28, ink: AnyShapeStyle(.primary))
                    .overlay(alignment: .topTrailing) {
                        Text("3")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color(hex: 0xFF3B30)))
                            .offset(x: 8, y: -6)
                    }
                Glyph(image: image, size: 28, ink: AnyShapeStyle(.secondary))
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(Color(hex: 0x22B573))
                            .frame(width: 9, height: 9)
                            .offset(x: 2, y: -1)
                    }
            }
            .padding(.leading, 4)
        }
    }
}

/// A tab: its icon over its title, in the accent when it is the open one.
@View
struct TabItem {
    let image: SvgImage?
    let title: String
    let isSelected: Bool
    let open: () -> Void

    var body: some View {
        let ink: AnyShapeStyle = isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary)
        VStack(spacing: 3) {
            Glyph(image: image, size: 22, ink: ink)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}

/// What draws the icon as it is shown, a line per `Text` so the indented
/// ones can be indented.
@View
struct CodeSample {
    let icon: Icon
    let style: IconStyle

    var body: some View {
        let lines: [(indent: Bool, text: String)] = [
            (false, "// Material/\(icon.category)/\(icon.name)/"),
            (true, "\(icon.name + style.suffix).svg"),
            (false, "let icon ="),
            (true, "SvgImage(contentsOf: url)!"),
            (false, ""),
            (false, "SvgView(icon)"),
            (true, ".resizable()"),
            (true, ".renderingMode(.template)"),
            (true, ".foregroundStyle(.blue)"),
            (true, ".frame(width: 48, height: 48)"),
        ]
        VStack(alignment: .leading, spacing: 3) {
            ForEach(lines.indices, id: \.self) { index in
                if lines[index].text.isEmpty {
                    Color.clear
                        .frame(height: 6)
                } else {
                    Text(lines[index].text)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .padding(.leading, lines[index].indent ? 26 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.tile))
    }
}

@View
struct Caption {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
