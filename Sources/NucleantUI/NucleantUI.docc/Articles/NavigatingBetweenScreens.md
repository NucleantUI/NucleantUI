# Navigating between screens

Push screens onto a navigation stack and come back to them as you left them.

## Overview

A ``NavigationStack`` draws a bar with a back button, the title and the
screen's toolbar items over its current screen. A ``NavigationLink`` pushes a destination when it is tapped; the
pushed screen takes its title from the link:

```swift
@View
struct LibraryScreen {
    var body: some View {
        NavigationStack("Library") {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink("Shaders") {
                    ShaderGallery()
                }
                NavigationLink(title: "About") {
                    Text("NucleantUI").padding(20)
                } label: {
                    HStack {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                        Text("About")
                    }
                }
            }
            .padding(20)
        }
    }
}

@View
struct ShaderGallery {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(ShaderLibrary.all, id: \.name) { entry in
                Shader(entry.function).frame(height: 80)
            }
        }
        .padding(20)
    }
}
```

Screens under the top one stay alive: their state and scroll positions are
there when you come back.

## Navigating by value

A stack bound to a ``NavigationPath`` navigates by data: `NavigationLink(value:)`
appends a value, and `.navigationDestination(for:destination:)` says which
screen shows it.

## Toolbar items

A screen puts controls in the stack's bars with `.toolbar { }`. Each
``ToolbarItem`` names its place, and the bar arranges them the way an iOS
navigation bar does — on every platform, macOS included, where they go in
the stack's own bar rather than the window's title bar:

```swift
@View
struct NoteEditor {
    @Bindable var note: Note
    @Environment(\.navigationRouter) private var router

    var body: some View {
        TextEditor(text: $note.text)
            .navigationTitle(note.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { router?.pop() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { note.save(); router?.pop() }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Duplicate") { note.duplicate() }
                }
                ToolbarItem(placement: .status) {
                    Text("\(note.wordCount) words")
                }
            }
    }
}
```

- The leading side has `.topBarLeading`, `.cancellationAction`, then
  `.navigation`, nearest the title.
- The trailing side has `.automatic` (an item with no placement, and views
  put straight in `.toolbar { }`), `.topBarTrailing`, `.primaryAction`, then
  `.confirmationAction` and `.destructiveAction` at the edge.
- `.navigation` moves to the trailing side on a pushed screen, where the
  back button holds the leading edge.
- `.principal` takes the title's place, in the middle of the bar.
- `.secondaryAction` items are in a menu behind a "…" at the trailing edge.
- `.bottomBar` and `.status` items go in a bar along the bottom of the
  stack, a `.status` item centred. `.toolbarVisibility(.hidden, for:
  .bottomBar)` hides it.

``ToolbarItemGroup`` puts several views at one placement, and
``ToolbarSpacer`` adds room between items: `.flexible` pushes them apart,
`.fixed` parts them into two groups. Each item is built in the environment
of the view its `.toolbar` is on, and is kept up to date with the screen's
state. Several `.toolbar`s on one screen add up, an outer one's items before
an inner one's.

The bar shows when its screen has something for it: a title, toolbar items
or a back button. A root screen with none of them has no bar, unless it
asks for one with `.toolbarVisibility(.visible, for: .navigationBar)`.

### A back button of your own

The back button is a chevron in the primary label color. For any other
icon, label or color, hide it with `.navigationBarBackButtonHidden()` and
put your own in the `.navigation` placement, which then takes the leading
edge. The bar stays:

```swift
@View
struct DetailScreen {
    @Environment(\.navigationRouter) private var router

    var body: some View {
        DetailContent()
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Close") { router?.pop() }
                        .tint(.red)
                }
            }
    }
}
```

## Hiding the bar

A screen hides the stack's bar with `.toolbarVisibility(.hidden, for:
.navigationBar)` — or `.toolbar(.hidden, for: .navigationBar)`, its older
name — and gets the stack's whole height. The setting belongs to the
screen: pushing another screen shows the bar again, and coming back hides
it again.

The Back button goes with the bar, so a screen that hides it gives itself
a way back through the router:

```swift
@View
struct BookCover {
    let book: Book
    @Environment(\.navigationRouter) private var router

    var body: some View {
        ZStack(alignment: .topLeading) {
            CoverArt(book: book)
            Text("‹ Library")
                .padding(12)
                .onTapGesture { router?.pop() }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
```

The visibility can change while the screen is up — a reader that hides
the bar while you read and brings it back on a tap:

```swift
@View
struct ReadingPage {
    @State private var isImmersive = false

    var body: some View {
        PageText()
            .onTapGesture { isImmersive.toggle() }
            .toolbarVisibility(isImmersive ? .hidden : .visible, for: .navigationBar)
    }
}
```

## Moving between screens

A push slides the new screen in from the trailing edge, over the one it
covers, which drifts the other way and dims a little; a pop plays the same
slide backwards. That is the stack's ``AutomaticNavigationTransition``. A push
or pop made inside a transaction with `disablesAnimations` set happens at once.

A screen can grow out of a view on the screen it is pushed from, and shrink
back into it when you go back: mark the view with
`.matchedTransitionSource(id:in:)`, and give the destination
`.navigationTransition(.zoom(sourceID:in:))` with the same id. Both name a
``Namespace``, which the view that holds the stack owns:

```swift
@View
struct Gallery {
    let photos: [Photo]
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))]) {
                ForEach(photos) { photo in
                    NavigationLink(value: photo.id) {
                        Thumbnail(photo: photo)
                            .matchedTransitionSource(id: photo.id, in: zoom)
                    }
                }
            }
            .navigationDestination(for: Photo.ID.self) { id in
                PhotoDetail(id: id)
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
            }
        }
    }
}
```

While it zooms, the new screen is drawn scaled into a frame that grows from
the source's to its own, its corners rounding off from the source's; the
screen underneath recedes and dims, and the source itself is hidden. On the
way back the frame shrinks into wherever the source is then. With no source
on screen, the push slides in instead.

The source can be styled: clipped to a rounded rectangle, with a colour
behind it that also fills the shape as it grows:

```swift
Thumbnail(photo: photo)
    .matchedTransitionSource(id: photo.id, in: zoom) { source in
        source
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .background(photo.dominantColor)
    }
```

Unlike SwiftUI, every platform plays the same transitions, macOS included:
NucleantUI draws them itself. The source configuration's `shadow` is not
there yet. The <doc:AtlasExample> app shows both transitions at work.

A screen can also arrive through a shader of your own. `.shader(_:arguments:)`
draws the new screen through it over the one underneath, which stays put.
The shader's first argument, `progress`, runs from 0 to 1 on the push and back
on the pop: at 0 nothing of the screen shows, and at 1 all of it does.

```swift
PhotoDetail(photo)
    .navigationTransition(.shader(
        ShaderFunction("fragColor = layer(uv) * progress;"),
        timing: .smooth(duration: 0.6)
    ))
```

This is not in SwiftUI. The NucleantTransitions package builds its
ready-made shader transitions on it.
