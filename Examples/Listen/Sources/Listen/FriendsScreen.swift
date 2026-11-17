//
//  FriendsScreen.swift
//  Listen
//
//  What friends are listening to, the newest at the top, with more
//  arriving while the screen is open.
//
//  Where it goes in depends on where the reader is. The page keeps its
//  distance from its bottom as its size changes
//  (`.defaultScrollAnchor(.bottom, for: .sizeChanges)`), so an entry
//  arriving above someone reading further down goes in out of sight and
//  what they are reading stays where it is; a pill counts what came in
//  above, and a tap on it scrolls up (`ScrollPosition`). At the top, the
//  reader wants to see it: the entry goes in under a transaction that
//  turns that adjustment off (`scrollContentOffsetAdjustmentBehavior =
//  .disabled`), so the page stays at the top and the new entry appears
//  there. Whether the page is at the top is read off its geometry
//  (`.onScrollGeometryChange`), and each entry is marked read once most
//  of it has been on screen (`.onScrollVisibilityChange`).
//

import NucleantUI

@View
struct FriendsScreen {
    let feed: Feed
    let player: Player
    let bottomInset: Double

    @State private var position = ScrollPosition(edge: .top)
    @State private var isAtTop = true
    /// Entries that went in above what is being read.
    @State private var newAbove = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle(title: "Friends", subtitle: "Listening now")
                    .padding(.bottom, 10)
                ForEach(feed.entries) { activity in
                    ActivityRow(activity: activity, isUnread: feed.unread.contains(activity.id)) {
                        player.play(activity.album, track: activity.track.number - 1)
                    }
                    .onScrollVisibilityChange(threshold: 0.8) { visible in
                        if visible { feed.markRead(activity.id) }
                    }
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .safeAreaPadding(.bottom, bottomInset)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y <= 8
        } action: { _, atTop in
            isAtTop = atTop
            if atTop { withAnimation(.smooth) { newAbove = 0 } }
        }
        .onChange(of: feed.incoming.count) { _, count in
            if count > 0 { showIncoming() }
        }
        .onAppear { showIncoming() }
        .overlay(alignment: .top) {
            if newAbove > 0 {
                Button {
                    withAnimation(.smooth(duration: 0.5)) { position.scrollTo(edge: .top) }
                } label: {
                    HStack(spacing: 6) {
                        Glyph(kind: .chevronUp, size: 12)
                        Text(newAbove == 1 ? "1 new" : "\(newAbove) new").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.accent))
                }
                .padding(.top, 12)
                .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: AlbumRoute.self) { route in
            AlbumScreen(album: Catalog.shared.album(route.album), catalog: .shared, player: player, bottomInset: bottomInset)
        }
    }

    /// What arrived, put in at the top: shown where the reader is at the
    /// top, slipped in above them otherwise.
    private func showIncoming() {
        guard !feed.incoming.isEmpty else { return }
        if isAtTop {
            var transaction = Transaction(animation: .smooth)
            transaction.scrollContentOffsetAdjustmentBehavior = .disabled
            withTransaction(transaction) { feed.showIncoming() }
        } else {
            let count = feed.showIncoming()
            withAnimation(.smooth) { newAbove += count }
        }
    }
}

@View
struct ActivityRow {
    let activity: Activity
    let isUnread: Bool
    let play: () -> Void

    private static let avatarColors: [Color] = [
        Color(hex: 0x6C5CE7), Color(hex: 0x00B894), Color(hex: 0xE17055), Color(hex: 0x0984E3), Color(hex: 0xD63031),
        Color(hex: 0xFDCB6E), Color(hex: 0xE84393), Color(hex: 0x00CEC9), Color(hex: 0x636E72), Color(hex: 0xA29BFE),
    ]

    var body: some View {
        Button(action: play) {
            HStack(alignment: .top, spacing: 12) {
                Text(String(activity.friend.prefix(1)))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Self.avatarColors[activity.friend.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.avatarColors.count]))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(activity.friend).font(.system(size: 15, weight: .bold))
                        Text("is listening to")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.faint)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ago(activity.date)).font(.caption).foregroundStyle(Theme.faint)
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 8, height: 8)
                            .opacity(isUnread ? 1 : 0)
                            .animation(.easeOut(duration: 0.4), value: isUnread)
                    }
                    HStack(spacing: 12) {
                        Cover(album: activity.album, size: 54, showsTitle: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.track.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text("\(activity.album.artist) · \(activity.album.title)")
                                .font(.footnote)
                                .foregroundStyle(Theme.faint)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .foregroundStyle(Theme.ink)
        }
    }
}
