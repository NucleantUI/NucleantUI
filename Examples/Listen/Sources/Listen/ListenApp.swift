//
//  ListenApp.swift
//  Listen
//
//  A music app, and the scroll views doing a music app's jobs:
//
//  * Listen Now — a paged carousel of featured albums turning itself every
//    few seconds, shelves of covers that come to rest on a cover and run
//    out to the window's edge past their margins, a title that shrinks
//    into a bar once it is scrolled under, a button back to the top once
//    far down, and a tab bar that slides out of the way while scrolling.
//    Its place is kept while another tab is open.
//  * An album's page — its cover stretching when pulled past the top and
//    drifting up slower than the page, and a jump to the playing track.
//  * Now Playing — the lyrics following the line being sung, held where
//    the listener scrolled them for a moment, and lockable.
//  * Search — the keyboard put away by scrolling the results.
//  * Friends — activity arriving at the top without moving what is being
//    read, a pill for what came in above, and what has been seen marked
//    read.
//

import NucleantUI

enum Theme {
    static let background = DynamicShapeStyle(light: Color(hex: 0xF6F5F2), dark: Color(hex: 0x0F0F12))
    static let card = DynamicShapeStyle(light: Color.white, dark: Color(hex: 0x1C1C21))
    static let chrome = DynamicShapeStyle(light: Color(hex: 0xFFFFFF, opacity: 0.97), dark: Color(hex: 0x19191E, opacity: 0.97))
    static let ink = DynamicShapeStyle(light: Color(hex: 0x16161A), dark: Color(hex: 0xF2F2F5))
    static let faint = DynamicShapeStyle(light: Color(white: 0, opacity: 0.45), dark: Color(white: 1, opacity: 0.45))
    static let rule = DynamicShapeStyle(light: Color(white: 0, opacity: 0.08), dark: Color(white: 1, opacity: 0.1))
    static let accent = Color(hex: 0xFF3B5C)
}

enum Tab: CaseIterable {
    case listenNow, search, friends

    var title: String {
        switch self {
        case .listenNow: "Listen Now"
        case .search: "Search"
        case .friends: "Friends"
        }
    }

    var glyph: GlyphKind {
        switch self {
        case .listenNow: .listen
        case .search: .search
        case .friends: .friends
        }
    }
}

@View
struct RootView {
    @State private var player = Player()
    @State private var feed = Feed(catalog: .shared)
    @State private var tab = Tab.listenNow
    /// Where Listen Now was left, for when its tab is opened again.
    @State private var listenNowPosition = ScrollPosition(idType: ListenNowItem.self, edge: .top)
    /// A scroll view of the open tab is moving: the tab bar steps aside.
    @State private var isScrolling = false
    @State private var showsNowPlaying = false
    @Environment(\.colorScheme) private var system

    /// How much of the window's bottom the tab bar and the mini player
    /// cover: the screens scroll their content clear of it.
    private var bottomInset: Double {
        (player.track == nil ? 0 : MiniPlayer.height) + TabBar.height
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Under Now Playing, the tabs take no presses: what is not a
            // control there would otherwise reach the page under it.
            Group {
                if tab == .listenNow {
                    NavigationStack {
                        ListenNowScreen(
                            catalog: .shared,
                            player: player,
                            position: $listenNowPosition,
                            bottomInset: bottomInset,
                            isScrolling: $isScrolling
                        )
                    }
                } else if tab == .search {
                    NavigationStack {
                        SearchScreen(catalog: .shared, player: player, bottomInset: bottomInset)
                    }
                } else {
                    NavigationStack {
                        FriendsScreen(feed: feed, player: player, bottomInset: bottomInset)
                    }
                }
            }
            .allowsHitTesting(!showsNowPlaying)
            BottomChrome(player: player, tab: $tab, isCollapsed: isScrolling) {
                withAnimation(.smooth) { showsNowPlaying = true }
            }
            .allowsHitTesting(!showsNowPlaying)
            if showsNowPlaying {
                NowPlayingScreen(player: player) {
                    withAnimation(.smooth) { showsNowPlaying = false }
                }
                .transition(AnyTransition.move(edge: .bottom))
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .colorScheme(AppearanceModel.shared.appearance.scheme ?? system)
        // The playhead: a fifth of a second at a time while playing.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                player.advance(by: 0.2)
            }
        }
        // Friends start listening to things now and then.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                feed.receive()
            }
        }
    }
}

@main
struct ListenApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Listen") {
            RootView()
        }
        .defaultSize(width: 430, height: 880)
        .commands { AppearanceCommands() }
    }
}

// MARK: - The bottom chrome

/// The mini player over the tab bar, the tab bar sliding down out of the
/// window while the open screen scrolls.
@View
struct BottomChrome {
    let player: Player
    @Binding var tab: Tab
    let isCollapsed: Bool
    let openNowPlaying: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if player.track != nil {
                MiniPlayer(player: player, open: openNowPlaying)
            }
            TabBar(tab: $tab)
        }
        .background(Theme.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        .offset(y: isCollapsed ? TabBar.height : 0)
        .animation(.smooth(duration: 0.3), value: isCollapsed)
    }
}

@View
struct TabBar {
    @Binding var tab: Tab

    static let height = 58.0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        Glyph(kind: item.glyph, size: 20)
                        Text(item.title).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(item == tab ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.faint))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
            }
        }
        .frame(height: Self.height)
    }
}

/// What is playing, with play/pause and next; a tap elsewhere opens Now
/// Playing.
@View
struct MiniPlayer {
    let player: Player
    let open: () -> Void

    static let height = 64.0

    var body: some View {
        if let album = player.album, let track = player.track {
            // The whole bar opens Now Playing — a press anywhere on it is the
            // bar's, not the page's under it — with the controls over it.
            ZStack(alignment: .top) {
                Button(action: open) {
                    HStack(spacing: 12) {
                        Cover(album: album, size: 44, showsTitle: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text(album.artist).font(.footnote).foregroundStyle(Theme.faint).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 110)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .foregroundStyle(Theme.ink)
                }
                HStack(spacing: 4) {
                    Button { player.toggle() } label: {
                        Glyph(kind: player.isPlaying ? .pause : .play, size: 22).padding(8).foregroundStyle(Theme.ink)
                    }
                    Button { player.next() } label: {
                        Glyph(kind: .next, size: 22).padding(8).foregroundStyle(Theme.ink)
                    }
                }
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                ProgressLine(progress: player.progress)
            }
            .frame(height: Self.height)
        }
    }
}

/// How far into the track: a hairline filled to `progress`.
@View
struct ProgressLine {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.rule)
                Rectangle().fill(Theme.accent).frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 2)
    }
}

/// A screen's big title, with what it is about under it.
@View
struct ScreenTitle {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subtitle.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.faint)
            Text(title).font(.system(size: 32, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

/// The bar a screen's title shrinks into once it is scrolled under.
@View
struct CompactTitleBar {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Theme.chrome)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
    }
}
