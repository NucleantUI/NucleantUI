//
//  NowPlayingScreen.swift
//  Listen
//
//  What is playing, over everything, with its lyrics. The lyrics scroll
//  themselves to the line being sung, centered (`ScrollViewReader`, by the
//  line's place in its `ForEach`), with room above the first line and
//  below the last for both to reach the middle (`.contentMargins`). Lines
//  fade and shrink as they leave the middle of the view
//  (`.scrollTransition`). The listener can scroll them: from the moment a
//  finger or a wheel moves them they stop following, and a few seconds
//  after they come to rest they pick the song up again
//  (`.onScrollPhaseChange`). The lock keeps the listener's hands off
//  (`.scrollDisabled`) while the lyrics still follow the song — the app
//  scrolls a scroll view the user cannot. A tap on a line sings from it.
//

import NucleantUI

@View
struct NowPlayingScreen {
    let player: Player
    let close: () -> Void

    @State private var isLocked = false

    private let ink = Color.white

    var body: some View {
        if let album = player.album, let track = player.track {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    IconButton(glyph: .chevronDown, action: close)
                    VStack(spacing: 1) {
                        Text("NOW PLAYING").font(.system(size: 11, weight: .bold)).tracking(1).opacity(0.7)
                        Text(album.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    IconButton(glyph: isLocked ? .lock : .lockOpen) {
                        isLocked.toggle()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Lyrics(track: track, player: player, isLocked: isLocked, ink: ink)

                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        Cover(album: album, size: 52, showsTitle: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.system(size: 18, weight: .bold)).lineLimit(1)
                            Text(album.artist).font(.callout).opacity(0.7).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(spacing: 6) {
                        ProgressLine(progress: player.progress)
                        HStack {
                            Text(clock(player.position))
                            Spacer()
                            Text("-" + clock(track.duration - player.position))
                        }
                        .font(.caption)
                        .opacity(0.6)
                    }
                    HStack(spacing: 44) {
                        IconButton(glyph: .previous) { player.previous() }
                        Button { player.toggle() } label: {
                            Glyph(kind: player.isPlaying ? .pause : .play, size: 26)
                                .foregroundStyle(album.palette.deep)
                                .frame(width: 68, height: 68)
                                .background(Circle().fill(ink))
                        }
                        IconButton(glyph: .next) { player.next() }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .padding(.top, 8)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [album.palette.deep, Color(hex: 0x0B0B0E)], startPoint: .top, endPoint: .bottom))
        }
    }
}

/// The lyrics, following the song.
@View
struct Lyrics {
    let track: Track
    let player: Player
    let isLocked: Bool
    let ink: Color

    /// Keeping the line being sung in the middle. Off from when the
    /// listener moves the lyrics until a while after they let go.
    @State private var follows = true
    /// Counts the times the listener let the lyrics come to rest: following
    /// picks up again a few seconds after the last one.
    @State private var restings = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(track.lyrics.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(ink.opacity(index == player.line ? 1 : 0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.seek(toLine: index)
                                follows = true
                            }
                            .scrollTransition(.interactive.threshold(.visible(0.5))) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.25)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.9, anchor: .leading)
                            }
                    }
                }
                .padding(.horizontal, 28)
            }
            .contentMargins(.vertical, 160)
            .scrollDisabled(isLocked)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting {
                    follows = false
                } else if phase == .idle, !follows {
                    restings += 1
                }
            }
            .task(id: restings) {
                guard restings > 0 else { return }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                follows = true
                if let line = player.line {
                    withAnimation(.smooth(duration: 0.6)) { proxy.scrollTo(line, anchor: .center) }
                }
            }
            .onChange(of: player.line) { _, line in
                guard follows || isLocked, let line else { return }
                withAnimation(.smooth(duration: 0.5)) { proxy.scrollTo(line, anchor: .center) }
            }
            .onChange(of: track.id) { _, _ in
                follows = true
                proxy.scrollTo(0, anchor: .center)
            }
            .onAppear {
                if let line = player.line { proxy.scrollTo(line, anchor: .center) }
            }
        }
    }
}

/// A round, borderless icon button.
@View
struct IconButton {
    let glyph: GlyphKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Glyph(kind: glyph, size: 20)
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
    }
}
