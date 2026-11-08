//
//  Editor.swift
//  Slides
//
//  Editing a deck: the strip of slides down the side, the slide on stage
//  in the middle — every slide picked comes on with its entrance, and the
//  one it replaces goes off with its exit — and the inspector, where a
//  slide's words, look and effects are set.
//
//  The strip is a `ForEach` too: a slide added slides in from the side and
//  one deleted slides out, while the rest move up or down to make room.
//

import NucleantUI

@View
struct Editor {
    let deck: Deck

    var body: some View {
        HStack(spacing: 0) {
            SlideStrip(deck: deck)
                .frame(width: 214)
                .frame(maxHeight: .infinity)
                .background(Theme.sidebar)
            Divider()
            VStack(spacing: 0) {
                Toolbar(deck: deck)
                Divider()
                Stage(deck: deck)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.canvas)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            if let slide = deck.selected {
                Inspector(deck: deck, slide: slide)
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
                    .background(Theme.sidebar)
            }
        }
    }
}

// MARK: - The strip

@View
struct SlideStrip {
    let deck: Deck

    var body: some View {
        let deck = self.deck
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(deck.slides) { slide in
                        SlideStripRow(deck: deck, slide: slide)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 10) {
                Button("Add") { withAnimation(.snappy) { deck.addSlide() } }
                Button("Copy") { withAnimation(.snappy) { deck.duplicateSelection() } }
                Button("Delete") { withAnimation(.snappy) { deck.deleteSelection() } }
                Spacer()
                Button("↑") { withAnimation(.snappy) { deck.moveSelection(by: -1) } }
                Button("↓") { withAnimation(.snappy) { deck.moveSelection(by: 1) } }
            }
            .font(.system(size: 12))
            .padding(10)
        }
    }
}

@View
struct SlideStripRow {
    let deck: Deck
    let slide: Slide

    var body: some View {
        let deck = self.deck
        let id = slide.id
        let isSelected = deck.selection == id
        HStack(alignment: .top, spacing: 8) {
            Text("\(deck.number(of: id))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Thumbnail(slide: slide, width: 160)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 3)
                )
        }
        .contentShape(Rectangle())
        .onTapGesture { deck.select(id) }
    }
}

// MARK: - The toolbar

@View
struct Toolbar {
    @Bindable var deck: Deck

    var body: some View {
        let deck = self.deck
        HStack(spacing: 12) {
            TextField("Deck name", text: $deck.name)
                .font(.system(size: 16, weight: .semibold))
                .frame(minWidth: 140, maxWidth: 280)
            Spacer()
            Text("\(deck.slides.count) slides")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button("Show Again") { deck.replay() }
            Button("Play from Here") {
                withAnimation(.smooth(duration: 0.5)) { deck.present(fromStart: false) }
            }
            Button("Play") {
                withAnimation(.smooth(duration: 0.5)) { deck.present(fromStart: true) }
            }
            .tint(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - The inspector

@View
struct Inspector {
    let deck: Deck
    let slide: Slide

    var body: some View {
        let deck = self.deck
        let slide = self.slide
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                Heading("Slide")
                Picker("Layout", selection: binding(\.layout)) {
                    ForEach(SlideLayout.allCases) { layout in
                        Text(layout.name)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ThemeSwatches(selection: binding(\.theme))

                Labeled("Title") {
                    TextField("Title", text: binding(\.title))
                }
                if slide.layout != .bullets && slide.layout != .statement {
                    Labeled(slide.layout == .quote ? "Said by" : "Subtitle") {
                        TextField("Subtitle", text: binding(\.subtitle))
                    }
                    .transition(.opacity)
                }
                if slide.layout == .bullets {
                    PointsEditor(deck: deck, slide: slide)
                        .transition(.opacity)
                }

                Divider()
                Heading("Effects")
                Labeled("Comes on with") {
                    EffectPicker(title: "Entrance", selection: binding(\.entrance))
                }
                Labeled("Goes off with") {
                    EffectPicker(title: "Exit", selection: binding(\.exit))
                }
                if slide.layout == .bullets {
                    Labeled("Each point with") {
                        EffectPicker(title: "Build", selection: binding(\.build))
                    }
                    .transition(.opacity)
                }
                Labeled("Takes \(String(format: "%.1f", slide.duration)) s") {
                    Slider(value: binding(\Slide.duration), in: 0.2...2.0, step: 0.1)
                }
                Labeled("On a curve") {
                    Picker("Curve", selection: binding(\.curve)) {
                        ForEach(Curve.allCases) { curve in
                            Text(curve.name)
                        }
                    }
                    .labelsHidden()
                }
                Button("Show Again") { deck.replay() }
                    .tint(Theme.accent)
            }
            .padding(16)
        }
    }

    /// A field of the inspected slide, written back through the deck.
    private func binding<Value>(_ keyPath: WritableKeyPath<Slide, Value>) -> Binding<Value> {
        let deck = self.deck
        let id = slide.id
        let shown = slide[keyPath: keyPath]
        return Binding(
            get: { deck.slides.first { $0.id == id }?[keyPath: keyPath] ?? shown },
            set: { value in deck.edit(id) { $0[keyPath: keyPath] = value } }
        )
    }
}

/// The slide's points, each its own field, added and removed in place.
@View
struct PointsEditor {
    let deck: Deck
    let slide: Slide

    var body: some View {
        let deck = self.deck
        let id = slide.id
        VStack(alignment: .leading, spacing: 8) {
            Text("Points")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(slide.bullets) { bullet in
                HStack(spacing: 8) {
                    TextField("Point", text: Binding(
                        get: { deck.slides.first { $0.id == id }?.bullets.first { $0.id == bullet.id }?.text ?? bullet.text },
                        set: { text in
                            deck.edit(id) { slide in
                                guard let index = slide.bullets.firstIndex(where: { $0.id == bullet.id }) else { return }
                                slide.bullets[index].text = text
                            }
                        }
                    ))
                    .frame(maxWidth: .infinity)
                    Button("Remove") { withAnimation(.snappy) { deck.removePoint(bullet.id, from: id) } }
                        .font(.system(size: 12))
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            Button("Add Point") { withAnimation(.snappy) { deck.addPoint(to: id) } }
                .font(.system(size: 12))
        }
    }
}

/// Every effect, the framework's first and then the app's own.
@View
struct EffectPicker {
    let title: String
    let selection: Binding<Effect>

    var body: some View {
        Picker(title, selection: selection) {
            ForEach(Effect.builtIn) { effect in
                Text(effect.name)
            }
            Divider()
            ForEach(Effect.custom) { effect in
                Text(effect.name)
            }
        }
        .labelsHidden()
    }
}

/// A swatch per theme; the slide's is ringed.
@View
struct ThemeSwatches {
    let selection: Binding<Int>

    var body: some View {
        let selection = self.selection
        HStack(spacing: 10) {
            ForEach(SlideTheme.all.indices, id: \.self) { index in
                let theme = SlideTheme.all[index]
                ZStack {
                    Circle().fill(theme.background).frame(width: 24, height: 24)
                    Circle().fill(theme.accent).frame(width: 8, height: 8)
                    Circle()
                        .stroke(selection.wrappedValue == index ? Theme.accent : Color.clear, lineWidth: 2)
                        .frame(width: 30, height: 30)
                }
                .frame(width: 30, height: 30)
                .contentShape(Circle())
                .onTapGesture { selection.wrappedValue = index }
            }
        }
    }
}

@View
struct Heading {
    let text: String

    init(_ text: String, _viewID: ViewID = #viewID) {
        self.text = text
        self._viewID = _viewID
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
    }
}

/// A control with its label over it.
@View
struct Labeled<Content: View> {
    let label: String
    let content: Content

    init(_ label: String, _viewID: ViewID = #viewID, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
        self._viewID = _viewID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            content
        }
    }
}
