//
//  Model.swift
//  Listen
//
//  What the app works on: the catalog's albums and tracks (values), the
//  player — what is playing, where in it, what was played — and the feed of
//  what friends are listening to, new activity arriving as it goes. The
//  player and the feed change over time, so each is an `@Observable` class
//  the root view owns and changes through its methods.
//

import Foundation
import NucleantUI
import Observation

/// The colours a cover is drawn in: a light and a deep shade of its field,
/// and the ink of its motif.
struct Palette: Hashable {
    let light: Color
    let deep: Color
    let ink: Color
}

/// The pattern drawn on a cover.
enum Motif: Hashable {
    case rings, stripes, sun, grid, waves, dots
}

struct Track: Identifiable, Hashable {
    /// Unique across the catalog.
    let id: Int
    let number: Int
    let title: String
    /// Its lyrics, a line at a time; each line is sung for `lineLength`
    /// seconds after an intro of the same length.
    let lyrics: [String]

    static let lineLength = 4.0

    var duration: Double { Double(lyrics.count + 2) * Self.lineLength }

    /// The line sung at `position` seconds in, or `nil` in the intro and
    /// outro.
    func line(at position: Double) -> Int? {
        let line = Int((position - Self.lineLength) / Self.lineLength)
        guard position >= Self.lineLength, line < lyrics.count else { return nil }
        return line
    }

    /// Where `line` begins.
    func start(of line: Int) -> Double {
        Double(line + 1) * Self.lineLength
    }
}

struct Album: Identifiable, Hashable {
    let id: Int
    let title: String
    let artist: String
    let year: Int
    let genre: String
    let palette: Palette
    let motif: Motif
    let isNew: Bool
    let blurb: String
    let tracks: [Track]

    var length: Double { tracks.reduce(0) { $0 + $1.duration } }
}

/// A screen pushed for an album.
struct AlbumRoute: Hashable {
    let album: Int
}

/// "3:05" for 185 seconds.
func clock(_ seconds: Double) -> String {
    let whole = max(0, Int(seconds))
    return "\(whole / 60):" + String(format: "%02d", whole % 60)
}

// MARK: - The player

@MainActor
@Observable
final class Player {
    private(set) var album: Album?
    private(set) var trackIndex = 0
    /// Seconds into the track.
    private(set) var position = 0.0
    private(set) var isPlaying = false
    /// Albums played, the latest first.
    private(set) var recentlyPlayed: [Album] = []

    var track: Track? { album.map { $0.tracks[trackIndex] } }

    /// The lyric line being sung.
    var line: Int? { track?.line(at: position) }

    var progress: Double {
        guard let track else { return 0 }
        return position / track.duration
    }

    func isPlaying(_ track: Track) -> Bool {
        self.track?.id == track.id
    }

    func play(_ album: Album, track index: Int = 0) {
        self.album = album
        trackIndex = min(max(index, 0), album.tracks.count - 1)
        position = 0
        isPlaying = true
        recentlyPlayed.removeAll { $0.id == album.id }
        recentlyPlayed.insert(album, at: 0)
    }

    func toggle() {
        guard album != nil else { return }
        isPlaying.toggle()
    }

    func next() {
        guard let album else { return }
        if trackIndex + 1 < album.tracks.count {
            trackIndex += 1
            position = 0
        } else {
            trackIndex = 0
            position = 0
            isPlaying = false
        }
    }

    func previous() {
        guard album != nil else { return }
        if position > 3 || trackIndex == 0 {
            position = 0
        } else {
            trackIndex -= 1
            position = 0
        }
    }

    /// Sing from the start of `line`.
    func seek(toLine line: Int) {
        guard let track else { return }
        position = track.start(of: line)
        isPlaying = true
    }

    /// Time passing: `seconds` more of the track while playing, and the
    /// next one when it ends.
    func advance(by seconds: Double) {
        guard isPlaying, let track else { return }
        position += seconds
        if position >= track.duration { next() }
    }
}

// MARK: - The feed

/// A friend listening to something.
struct Activity: Identifiable, Hashable {
    let id: Int
    let friend: String
    let album: Album
    let track: Track
    let date: Date
}

@MainActor
@Observable
final class Feed {
    /// What is shown, the newest first.
    private(set) var entries: [Activity] = []
    /// What arrived and is not shown yet — the screen decides how it goes in.
    private(set) var incoming: [Activity] = []
    /// What has not been on screen yet.
    private(set) var unread: Set<Int> = []

    private let catalog: Catalog
    private var nextID = 0
    private var generator = SeededGenerator(seed: 7)

    init(catalog: Catalog) {
        self.catalog = catalog
        let start = Date().addingTimeInterval(-3 * 3600)
        for minute in stride(from: 0, to: 180, by: 9) {
            entries.insert(makeActivity(at: start.addingTimeInterval(Double(minute) * 60)), at: 0)
        }
    }

    /// A friend started listening to something.
    func receive() {
        let activity = makeActivity(at: Date())
        incoming.append(activity)
        unread.insert(activity.id)
    }

    /// What arrived, put at the top of the feed; how many there were.
    @discardableResult
    func showIncoming() -> Int {
        let count = incoming.count
        entries.insert(contentsOf: incoming.reversed(), at: 0)
        incoming.removeAll()
        return count
    }

    func markRead(_ id: Int) {
        unread.remove(id)
    }

    private func makeActivity(at date: Date) -> Activity {
        let album = catalog.albums[Int(generator.next() % UInt64(catalog.albums.count))]
        let track = album.tracks[Int(generator.next() % UInt64(album.tracks.count))]
        let friend = catalog.friends[Int(generator.next() % UInt64(catalog.friends.count))]
        defer { nextID += 1 }
        return Activity(id: nextID, friend: friend, album: album, track: track, date: date)
    }
}

/// The same "random" feed on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
}

/// "now", "4 min", "2 h".
func ago(_ date: Date, from now: Date = Date()) -> String {
    let minutes = Int(now.timeIntervalSince(date) / 60)
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes) min" }
    return "\(minutes / 60) h"
}
