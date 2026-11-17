//
//  AlbumScreen.swift
//  Listen
//
//  An album's page. Its header is placed like any view and then moved by
//  where it is in the scroll view (`.visualEffect`): pulled down past the
//  top, the rubber band stretches it from its bottom edge; scrolled up, it
//  drifts up at half the page's speed and fades under the tracks. The
//  album's title goes into the bar once the header is gone
//  (`.onScrollGeometryChange`), and while one of its tracks plays, a
//  button scrolls the list to it (`ScrollViewReader`, by the track's id in
//  its `ForEach`).
//

import NucleantUI

@View
struct AlbumScreen {
    let album: Album
    let catalog: Catalog
    let player: Player
    let bottomInset: Double

    @State private var showsTitleInBar = false

    private var playingTrack: Track? {
        player.album?.id == album.id ? player.track : nil
    }

    private var moreByArtist: [Album] {
        catalog.albums.filter { $0.artist == album.artist && $0.id != album.id }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AlbumHeader(album: album)
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.title).font(.system(size: 28, weight: .bold))
                            Text(album.artist).font(.system(size: 19, weight: .medium)).foregroundStyle(Theme.accent)
                            Text("\(album.genre) · \(String(album.year)) · \(album.tracks.count) songs, \(Int(album.length / 60)) min")
                                .font(.footnote)
                                .foregroundStyle(Theme.faint)
                        }
                        Text(album.blurb).font(.callout).foregroundStyle(Theme.faint)
                        HStack(spacing: 12) {
                            PillButton(title: "Play", glyph: .play, isProminent: true) {
                                player.play(album)
                            }
                            if let playingTrack {
                                PillButton(title: "Playing: \(playingTrack.title)", glyph: .listen, isProminent: false) {
                                    withAnimation(.smooth) { proxy.scrollTo(playingTrack.id, anchor: .center) }
                                }
                            }
                        }
                        VStack(spacing: 0) {
                            ForEach(album.tracks) { track in
                                TrackRow(track: track, isPlaying: playingTrack?.id == track.id) {
                                    player.play(album, track: track.number - 1)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background)
                    if !moreByArtist.isEmpty {
                        Shelf(title: "More by \(album.artist)", albums: moreByArtist, coverSize: 130)
                            .padding(.bottom, 24)
                            .background(Theme.background)
                    }
                }
            }
            .safeAreaPadding(.bottom, bottomInset)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > AlbumHeader.height - 40
            } action: { _, gone in
                showsTitleInBar = gone
            }
        }
        .navigationTitle(showsTitleInBar ? album.title : "")
    }
}

/// The album's cover on its colours, moved by where it is in the scroll
/// view: stretched when pulled down, drifting up and fading when scrolled.
@View
struct AlbumHeader {
    let album: Album

    static let height = 320.0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [album.palette.deep, album.palette.light], startPoint: .top, endPoint: .bottom))
            Cover(album: album, size: 230, showsTitle: true)
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .visualEffect { content, proxy in
            let top = proxy.frame(in: .scrollView).minY
            let height = max(proxy.size.height, 1)
            return content
                .scaleEffect(top > 0 ? 1 + top / height : 1, anchor: .bottom)
                .offset(y: top < 0 ? -top * 0.5 : 0)
                .opacity(top < 0 ? max(0, 1 + top / height) : 1)
        }
    }
}

@View
struct TrackRow {
    let track: Track
    let isPlaying: Bool
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: 14) {
                Group {
                    if isPlaying {
                        Glyph(kind: .listen, size: 14).foregroundStyle(Theme.accent)
                    } else {
                        Text("\(track.number)").font(.system(size: 15)).foregroundStyle(Theme.faint)
                    }
                }
                .frame(width: 22)
                Text(track.title)
                    .font(.system(size: 16, weight: isPlaying ? .semibold : .regular))
                    .foregroundStyle(isPlaying ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.ink))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(clock(track.duration)).font(.footnote).foregroundStyle(Theme.faint)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
            .contentShape(Rectangle())
            .foregroundStyle(Theme.ink)
        }
    }
}

/// A rounded button with an icon.
@View
struct PillButton {
    let title: String
    let glyph: GlyphKind
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Glyph(kind: glyph, size: 14)
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(isProminent ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.accent))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(isProminent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.12))))
        }
    }
}
