//
//  ListenNowScreen.swift
//  Listen
//
//  The front page:
//
//  * Featured albums in a paged carousel (`.scrollTargetBehavior(.paging)`):
//    a swipe turns one page, the dots under it follow the page in view
//    through `.scrollPosition(id:)`, and the same binding turns it on its
//    own — every few seconds, the countdown starting again whenever the
//    page changes, by hand or not (`.task(id:)`).
//  * Shelves of covers that come to rest with a cover at their leading
//    edge (`.viewAligned` over a `.scrollTargetLayout()`), drawn out to the
//    window's edges past their margins (`.scrollClipDisabled()`), each
//    cover shrinking and fading as it leaves (`.scrollTransition`), with
//    which covers are in view counted beside the shelf's title
//    (`.onScrollTargetVisibilityChange`).
//  * The big title shrinking into a bar once it is scrolled under, and a
//    button back to the top once a screen or more down — both read off the
//    scroll view's geometry (`.onScrollGeometryChange`); the button moves
//    the page through its `ScrollPosition`. The parts of the page and its
//    songs are scroll targets with ids (`.scrollTargetLayout()`, `.id`),
//    so the position records the one at the top; the root keeps it, and
//    the page built again when its tab is opened again goes back there.
//  * The page's content kept clear of the tab bar and mini player over its
//    bottom (`.safeAreaPadding`), and the tab bar told when the page is
//    scrolling (`.onScrollPhaseChange`), so it can step aside.
//

import Foundation
import NucleantUI

@View
struct ListenNowScreen {
    let catalog: Catalog
    let player: Player
    @Binding var position: ScrollPosition
    let bottomInset: Double
    @Binding var isScrolling: Bool

    @State private var showsCompactTitle = false
    @State private var showsBackToTop = false

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    var body: some View {
        ScrollView {
            // Each part of the page, and each song, is a scroll target with
            // an id: the position records the one at the top, and the page
            // built again for this tab goes back to it.
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(title: "Listen Now", subtitle: greeting)
                    .padding(.bottom, 30)
                    .id(ListenNowItem.title)
                FeaturedPager(albums: catalog.featured, player: player)
                    .padding(.bottom, 30)
                    .id(ListenNowItem.featured)
                Shelf(title: "New Releases", albums: catalog.newReleases, coverSize: 150)
                    .padding(.bottom, 30)
                    .id(ListenNowItem.newReleases)
                if !player.recentlyPlayed.isEmpty {
                    Shelf(title: "Recently Played", albums: player.recentlyPlayed, coverSize: 120)
                        .padding(.bottom, 30)
                        .id(ListenNowItem.recentlyPlayed)
                }
                Shelf(title: "Made for You", albums: catalog.madeForYou, coverSize: 150)
                    .padding(.bottom, 30)
                    .id(ListenNowItem.madeForYou)
                Text("Top Songs")
                    .font(.system(size: 21, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .id(ListenNowItem.topSongs)
                ForEach(Array(catalog.topSongs.enumerated()), id: \.offset) { index, song in
                    SongRow(rank: index + 1, album: song.album, track: song.track, isPlaying: player.isPlaying(song.track)) {
                        player.play(song.album, track: song.track.number - 1)
                    }
                    .id(ListenNowItem.song(song.track.id))
                }
            }
            .scrollTargetLayout()
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollPosition($position, anchor: .top)
        .safeAreaPadding(.bottom, bottomInset)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > 56
        } action: { _, compact in
            withAnimation(.easeOut(duration: 0.2)) { showsCompactTitle = compact }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > geometry.containerSize.height
        } action: { _, far in
            withAnimation(.smooth) { showsBackToTop = far }
        }
        .onScrollPhaseChange { _, phase in
            isScrolling = phase.isScrolling
        }
        .overlay(alignment: .top) {
            CompactTitleBar(title: "Listen Now")
                .opacity(showsCompactTitle ? 1 : 0)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if showsBackToTop {
                Button {
                    withAnimation(.smooth(duration: 0.5)) { position.scrollTo(edge: .top) }
                } label: {
                    Glyph(kind: .chevronUp, size: 18)
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.accent))
                }
                .padding(.trailing, 20)
                .padding(.bottom, bottomInset + 16)
                .transition(AnyTransition.scale.combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: AlbumRoute.self) { route in
            AlbumScreen(album: catalog.album(route.album), catalog: catalog, player: player, bottomInset: bottomInset)
        }
    }
}

// MARK: - Featured

/// The featured albums a page at a time, with dots for the pages.
@View
struct FeaturedPager {
    let albums: [Album]
    let player: Player

    /// The album whose page is in view; `nil` until the pager reports one,
    /// which is the first.
    @State private var page: Int? = nil

    private var pageIndex: Int {
        albums.firstIndex { $0.id == page } ?? 0
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(albums) { album in
                            FeaturedCard(album: album, player: player)
                                .padding(.horizontal, 20)
                                .frame(width: proxy.size.width)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
            }
            .frame(height: 220)
            PageDots(count: albums.count, current: pageIndex) { index in
                withAnimation(.smooth) { page = albums[index].id }
            }
        }
        // Turns itself after a while on a page; any turn starts it again.
        .task(id: page) {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            let next = albums[(pageIndex + 1) % albums.count].id
            withAnimation(.smooth(duration: 0.6)) { page = next }
        }
    }
}

@View
struct FeaturedCard {
    let album: Album
    let player: Player

    var body: some View {
        NavigationLink(value: AlbumRoute(album: album.id)) {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(LinearGradient(colors: [album.palette.light, album.palette.deep], startPoint: .top, endPoint: .bottom))
                MotifShape(motif: album.motif, seed: album.id + 100)
                    .fill(album.palette.ink.opacity(0.18))
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(album.isNew ? "NEW ALBUM" : "FEATURED")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .opacity(0.8)
                        Text(album.title).font(.system(size: 26, weight: .bold)).lineLimit(1)
                        Text("\(album.artist) · \(album.genre)").font(.subheadline).opacity(0.85).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        player.play(album)
                    } label: {
                        Glyph(kind: .play, size: 18)
                            .foregroundStyle(album.palette.deep)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(album.palette.ink))
                    }
                }
                .foregroundStyle(album.palette.ink)
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

@View
struct PageDots {
    let count: Int
    let current: Int
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.faint))
                    .frame(width: index == current ? 22 : 8, height: 8)
                    .onTapGesture { select(index) }
            }
        }
        .animation(.smooth, value: current)
    }
}

// MARK: - Shelves

/// A row of covers that rests with one at its leading edge.
@View
struct Shelf {
    let title: String
    let albums: [Album]
    let coverSize: Double

    /// The covers mostly in view, for the count beside the title.
    @State private var inView: [Int] = []

    private var countLabel: String {
        let shown = albums.indices.filter { inView.contains(albums[$0].id) }
        guard let first = shown.first, let last = shown.last else { return "\(albums.count)" }
        return "\(first + 1)–\(last + 1) of \(albums.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                Text(title)
                    .font(.system(size: 21, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(countLabel).font(.footnote).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink(value: AlbumRoute(album: album.id)) {
                            AlbumTile(album: album, coverSize: coverSize)
                        }
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                .opacity(phase.isIdentity ? 1 : 0.45)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.6) { ids in
                inView = ids
            }
            .padding(.horizontal, 20)
        }
    }
}

@View
struct AlbumTile {
    let album: Album
    let coverSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Cover(album: album, size: coverSize, showsTitle: coverSize >= 140)
            VStack(alignment: .leading, spacing: 1) {
                Text(album.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(album.artist).font(.footnote).foregroundStyle(Theme.faint).lineLimit(1)
            }
            .frame(width: coverSize, alignment: .leading)
        }
        .foregroundStyle(Theme.ink)
    }
}

// MARK: - Top songs

/// The parts of Listen Now, and its songs, as scroll targets: what the
/// page's position records.
enum ListenNowItem: Hashable, Sendable {
    case title, featured, newReleases, recentlyPlayed, madeForYou, topSongs
    case song(Int)
}

@View
struct SongRow {
    let rank: Int
    let album: Album
    let track: Track
    let isPlaying: Bool
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: 14) {
                Text("\(rank)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 24, alignment: .trailing)
                Cover(album: album, size: 46, showsTitle: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isPlaying ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.ink))
                        .lineLimit(1)
                    Text("\(album.artist) · \(album.title)").font(.footnote).foregroundStyle(Theme.faint).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(clock(track.duration)).font(.footnote).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .foregroundStyle(Theme.ink)
        }
    }
}
