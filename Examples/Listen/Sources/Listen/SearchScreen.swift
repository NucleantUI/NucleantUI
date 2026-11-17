//
//  SearchScreen.swift
//  Listen
//
//  A search field over what it finds. Scrolling the results puts the
//  on-screen keyboard away as the finger starts to move
//  (`.scrollDismissesKeyboard(.immediately)`) — the field keeps its text,
//  and a tap brings the keyboard back. A handful of results fits on screen
//  and stays put under a finger rather than bouncing
//  (`.scrollBounceBehavior(.basedOnSize)`); a long list bounces as usual.
//  With nothing typed, the genres to start from.
//

import NucleantUI

@View
struct SearchScreen {
    let catalog: Catalog
    let player: Player
    let bottomInset: Double

    @State private var query = ""
    @FocusState private var isSearching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle(title: "Search", subtitle: "\(catalog.albums.count) albums · \(catalog.artists.count) artists")
            HStack(spacing: 10) {
                Glyph(kind: .search, size: 16).foregroundStyle(Theme.faint)
                TextField("Artists, albums, songs", text: $query)
                    .focused($isSearching)
                if !query.isEmpty {
                    Button("Clear") { query = "" }
                        .font(.footnote)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            .padding(.horizontal, 20)

            ScrollView {
                if query.isEmpty {
                    GenreGrid(genres: catalog.genres) { genre in query = genre }
                } else {
                    SearchResults(results: catalog.search(query), query: query, player: player)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaPadding(.bottom, bottomInset)
        }
        .padding(.top, 20)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: AlbumRoute.self) { route in
            AlbumScreen(album: catalog.album(route.album), catalog: catalog, player: player, bottomInset: bottomInset)
        }
    }
}

/// The genres as coloured tiles, two to a row.
@View
struct GenreGrid {
    let genres: [String]
    let pick: (String) -> Void

    private static let colors: [Color] = [
        Color(hex: 0x7B61FF), Color(hex: 0xFF8A3D), Color(hex: 0x1FA67A), Color(hex: 0xE84A7F), Color(hex: 0x2D7FF9),
        Color(hex: 0xB0841E), Color(hex: 0x5B5F97), Color(hex: 0x3AA7A3), Color(hex: 0xD64545), Color(hex: 0x8E5A9B),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by genre").font(.system(size: 19, weight: .bold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(genres.enumerated()), id: \.offset) { index, genre in
                    Button { pick(genre) } label: {
                        Text(genre)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(14)
                            .frame(height: 86, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Self.colors[index % Self.colors.count]))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }
}

@View
struct SearchResults {
    let results: (albums: [Album], tracks: [(album: Album, track: Track)])
    let query: String
    let player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if results.albums.isEmpty && results.tracks.isEmpty {
                Text("Nothing called “\(query)”.")
                    .font(.callout)
                    .foregroundStyle(Theme.faint)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
            }
            if !results.albums.isEmpty {
                SectionTitle(title: "Albums")
                ForEach(results.albums) { album in
                    NavigationLink(value: AlbumRoute(album: album.id)) {
                        HStack(spacing: 14) {
                            Cover(album: album, size: 56, showsTitle: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                                Text("Album · \(album.artist)").font(.footnote).foregroundStyle(Theme.faint).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .foregroundStyle(Theme.ink)
                    }
                }
            }
            if !results.tracks.isEmpty {
                SectionTitle(title: "Songs")
                ForEach(Array(results.tracks.enumerated()), id: \.offset) { index, song in
                    SongRow(rank: index + 1, album: song.album, track: song.track, isPlaying: player.isPlaying(song.track)) {
                        player.play(song.album, track: song.track.number - 1)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

@View
struct SectionTitle {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 19, weight: .bold))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}
