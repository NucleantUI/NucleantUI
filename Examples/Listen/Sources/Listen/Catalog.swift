//
//  Catalog.swift
//  Listen
//
//  Everything there is to listen to: sixteen albums by made-up artists,
//  forty more put together from word lists so the shelves run on past the
//  widest window (an iPad on its side), their tracks, and the lines each
//  track sings. A value built once (`Catalog.shared`) and handed to the
//  screens; the shelves on Listen Now are views of it.
//

import NucleantUI

struct Catalog {
    let albums: [Album]
    let friends = ["Ola", "Devi", "Priya", "Sam", "Lena", "Kofi", "Hana", "Ruben", "Theo", "Mei"]
    let genres = Catalog.genreNames

    static let shared = Catalog()

    private init() {
        var trackID = 0
        albums = (Self.sources + Self.generatedSources(count: 40)).enumerated().map { index, source in
            let tracks = source.tracks.enumerated().map { number, title in
                defer { trackID += 1 }
                return Track(
                    id: trackID,
                    number: number + 1,
                    title: title,
                    lyrics: Self.lyrics(for: trackID)
                )
            }
            return Album(
                id: index,
                title: source.title,
                artist: source.artist,
                year: source.year,
                genre: source.genre,
                palette: source.palette,
                motif: source.motif,
                isNew: source.isNew,
                blurb: source.blurb,
                tracks: tracks
            )
        }
    }

    func album(_ id: Int) -> Album {
        albums[id]
    }

    /// The pager at the top of Listen Now.
    var featured: [Album] { [albums[0], albums[5], albums[2], albums[8], albums[14]] }

    var newReleases: [Album] { albums.filter(\.isNew) }

    /// A hand-picked eight, then older albums from the rest: two dozen.
    var madeForYou: [Album] {
        let picked = [albums[3], albums[6], albums[9], albums[1], albums[11], albums[7], albums[12], albums[4]]
        let more = albums.dropFirst(Self.sources.count).filter { !$0.isNew }
        return Array((picked + more).prefix(24))
    }

    /// One song from each album, for the Top Songs list.
    var topSongs: [(album: Album, track: Track)] {
        albums.map { ($0, $0.tracks[($0.id * 3) % $0.tracks.count]) }
    }

    var artists: [String] { Array(Set(albums.map(\.artist))).sorted() }

    /// Albums whose title, artist or genre has `query` in it, and tracks
    /// whose title does.
    func search(_ query: String) -> (albums: [Album], tracks: [(album: Album, track: Track)]) {
        let needle = query.lowercased()
        let albums = albums.filter {
            $0.title.lowercased().contains(needle) || $0.artist.lowercased().contains(needle)
                || $0.genre.lowercased().contains(needle)
        }
        let tracks = self.albums.flatMap { album in
            album.tracks.filter { $0.title.lowercased().contains(needle) }.map { (album, $0) }
        }
        return (albums, tracks)
    }

    private static let genreNames = ["Dream pop", "Indie", "Afrobeat", "Synth-pop", "Folk", "Electronic", "Jazz", "Ambient", "Rock", "Soul"]

    // MARK: - The source

    private struct Source {
        let title: String
        let artist: String
        let year: Int
        let genre: String
        let palette: Palette
        let motif: Motif
        let isNew: Bool
        let blurb: String
        let tracks: [String]
    }

    private static let sources: [Source] = [
        Source(
            title: "Glass Harbor", artist: "Mara Lind", year: 2026, genre: "Dream pop",
            palette: Palette(light: Color(hex: 0x8EC5E8), deep: Color(hex: 0x23466E), ink: Color(hex: 0xF4F8FC)),
            motif: .rings, isNew: true,
            blurb: "Reverb-soaked songs written in a lighthouse keeper's cottage over one long winter.",
            tracks: ["Harbor Lights", "Glass Coast", "Undertow", "Fog Bell", "Paper Boats", "Slow Signal", "Low Beam", "Home Before Dark"]
        ),
        Source(
            title: "Night Ferry", artist: "The Lanterns", year: 2025, genre: "Indie",
            palette: Palette(light: Color(hex: 0xF2B880), deep: Color(hex: 0x3B2A4D), ink: Color(hex: 0xFFF1DF)),
            motif: .waves, isNew: false,
            blurb: "A crossing in ten songs: late trains, harbour bars and the long way home.",
            tracks: ["Last Crossing", "Deck Chairs", "Port Town", "Midnight Timetable", "Rope & Anchor", "Gulls", "The Far Shore", "Lantern Song", "Morning Dock", "Return Ticket"]
        ),
        Source(
            title: "Copper Sun", artist: "Ade Okafor", year: 2026, genre: "Afrobeat",
            palette: Palette(light: Color(hex: 0xF7C548), deep: Color(hex: 0xA3381E), ink: Color(hex: 0x2B1308)),
            motif: .sun, isNew: true,
            blurb: "Horns, talking drums and a rhythm section that never once sits still.",
            tracks: ["Copper Sun", "Market Day", "Highlife Road", "Dance Floor Prayer", "Lagos at Six", "Brass Parade", "Ember", "Long Afternoon", "Golden Hour"]
        ),
        Source(
            title: "Paper Satellites", artist: "Juno Vale", year: 2024, genre: "Synth-pop",
            palette: Palette(light: Color(hex: 0xF5A6C8), deep: Color(hex: 0x3D2C8D), ink: Color(hex: 0xFFFFFF)),
            motif: .dots, isNew: false,
            blurb: "Bright synths and big choruses about being far away from everyone you love.",
            tracks: ["Orbit", "Paper Satellites", "Static Hearts", "Signal Lost", "Moon Mail", "Gravity", "Comet Tail", "Ground Control"]
        ),
        Source(
            title: "Low Tide Choir", artist: "Fen & Arlo", year: 2023, genre: "Folk",
            palette: Palette(light: Color(hex: 0xB8D8BA), deep: Color(hex: 0x33533B), ink: Color(hex: 0xF1F7EE)),
            motif: .waves, isNew: false,
            blurb: "Two voices, one guitar and the sea doing the rest.",
            tracks: ["Low Tide", "Saltmarsh", "Two Voices", "Wading Song", "Driftwood", "The Estuary", "Shell Road", "Choir of Gulls"]
        ),
        Source(
            title: "Neon Orchard", artist: "Kite District", year: 2026, genre: "Electronic",
            palette: Palette(light: Color(hex: 0x9BF6D5), deep: Color(hex: 0x14213D), ink: Color(hex: 0xC6FF5E)),
            motif: .grid, isNew: true,
            blurb: "Club music grown slowly, track by track, from a single drum machine.",
            tracks: ["Seedling", "Neon Orchard", "Grafted", "Pollen Count", "Night Bloom", "Harvest Loop", "Greenhouse", "Afterhours Fruit", "Ripe"]
        ),
        Source(
            title: "Slow Weather", artist: "Ines Moreau", year: 2022, genre: "Jazz",
            palette: Palette(light: Color(hex: 0xC9C3E6), deep: Color(hex: 0x4A4063), ink: Color(hex: 0xF7F3FF)),
            motif: .stripes, isNew: false,
            blurb: "A late-night trio session with brushes, upright bass and a lot of rain.",
            tracks: ["Slow Weather", "Brushwork", "Rain Check", "Blue Window", "Umbrella Waltz", "Overcast", "Quiet Storm", "Clearing"]
        ),
        Source(
            title: "Field Notes", artist: "Tomas Berg", year: 2025, genre: "Ambient",
            palette: Palette(light: Color(hex: 0xE9E4D4), deep: Color(hex: 0x6B6250), ink: Color(hex: 0x2E2A22)),
            motif: .rings, isNew: false,
            blurb: "Recordings from a year of walks, folded into long, patient pieces.",
            tracks: ["First Frost", "Birch Line", "Pond at Noon", "Lichen", "Field Notes", "Dusk Chorus", "Snowfield"]
        ),
        Source(
            title: "Bright Static", artist: "Polar Youth", year: 2026, genre: "Rock",
            palette: Palette(light: Color(hex: 0xFF6B6B), deep: Color(hex: 0x1F1F24), ink: Color(hex: 0xFFE66D)),
            motif: .stripes, isNew: true,
            blurb: "Three chords, a loud amp and a debut that sounds like summer break.",
            tracks: ["Bright Static", "Basement Show", "Feedback", "Skate Park", "Loud Enough", "Tape Hiss", "Fuse Box", "Encore"]
        ),
        Source(
            title: "Velvet Hours", artist: "Noor Haddad", year: 2024, genre: "Soul",
            palette: Palette(light: Color(hex: 0xE8A87C), deep: Color(hex: 0x5C2A3A), ink: Color(hex: 0xFFF3E8)),
            motif: .sun, isNew: false,
            blurb: "Warm keys, a string section and a voice that takes its time.",
            tracks: ["Velvet Hours", "Slow Burn", "Honey", "Late Show", "Golden Thread", "Stay a While", "Candlelight", "Sunday"]
        ),
        Source(
            title: "Northern Lines", artist: "Sela", year: 2023, genre: "Electronic",
            palette: Palette(light: Color(hex: 0x7DE2D1), deep: Color(hex: 0x0B3C49), ink: Color(hex: 0xE6FFFB)),
            motif: .grid, isNew: false,
            blurb: "Minimal techno mapped onto a city's night bus routes.",
            tracks: ["N1", "Interchange", "Last Stop", "Depot", "Night Route", "Terminus", "Overground"]
        ),
        Source(
            title: "Salt & Cedar", artist: "Wren Hollow", year: 2025, genre: "Folk",
            palette: Palette(light: Color(hex: 0xD4A373), deep: Color(hex: 0x4F3824), ink: Color(hex: 0xFEFAE0)),
            motif: .dots, isNew: false,
            blurb: "Songs about the coast and the woods behind it, sung in close harmony.",
            tracks: ["Cedar", "Salt", "Woodsmoke", "Coastal Road", "Kindling", "Harmony Hill", "Pines"]
        ),
        Source(
            title: "Afterglow Park", artist: "Mara Lind", year: 2023, genre: "Dream pop",
            palette: Palette(light: Color(hex: 0xFFD6A5), deep: Color(hex: 0x9D4EDD), ink: Color(hex: 0xFFFFFF)),
            motif: .sun, isNew: false,
            blurb: "The first record: summer evenings, a borrowed four-track and a swing set.",
            tracks: ["Afterglow", "Swing Set", "Park Lights", "Sprinklers", "Late Bus", "Fireflies", "Goodnight Park"]
        ),
        Source(
            title: "Tin Roof Radio", artist: "The Lanterns", year: 2022, genre: "Indie",
            palette: Palette(light: Color(hex: 0xA8DADC), deep: Color(hex: 0x1D3557), ink: Color(hex: 0xF1FAEE)),
            motif: .stripes, isNew: false,
            blurb: "Recorded live in a barn, rain on the roof included at no extra cost.",
            tracks: ["Tin Roof", "Radio Static", "Barn Dance", "Long Wave", "Dial Tone", "Rainy Session", "Sign Off"]
        ),
        Source(
            title: "Midnight Garden", artist: "Ines Moreau", year: 2026, genre: "Jazz",
            palette: Palette(light: Color(hex: 0x95D5B2), deep: Color(hex: 0x081C15), ink: Color(hex: 0xD8F3DC)),
            motif: .rings, isNew: true,
            blurb: "Her quartet in full bloom: modal tunes written among the night flowers.",
            tracks: ["Moonflower", "Night Jasmine", "Midnight Garden", "Gate Latch", "Dew", "Owl Hours", "Nocturne", "First Light"]
        ),
        Source(
            title: "Open Water", artist: "Fen & Arlo", year: 2026, genre: "Folk",
            palette: Palette(light: Color(hex: 0x90E0EF), deep: Color(hex: 0x03045E), ink: Color(hex: 0xCAF0F8)),
            motif: .waves, isNew: true,
            blurb: "The second record leaves the shore behind: bigger songs, wider skies.",
            tracks: ["Open Water", "Swell", "Horizon", "Sea Legs", "Cross Current", "Sailmaker", "Landfall", "Deep Blue"]
        ),
    ]

    // MARK: - Made-up albums

    /// `count` albums put together from word lists — no two titles alike,
    /// none like the sixteen above — each with a colour of its own; every
    /// third one new this year.
    private static func generatedSources(count: Int) -> [Source] {
        let adjectives = [
            "Silver", "Quiet", "Electric", "Hollow", "Golden", "Lucid", "Wild", "Crystal",
            "Faded", "Secret", "Amber", "Distant", "Restless", "Gentle", "Static", "Burning",
        ]
        let nouns = [
            "Rivers", "Signals", "Echoes", "Machines", "Seasons", "Islands", "Letters", "Engines",
            "Mirrors", "Orchids", "Valleys", "Tides", "Postcards", "Cities", "Weather", "Horizons",
        ]
        let artists = [
            "Lumen Bay", "Oskar Vale", "Lantern Hill Club", "Nadia Sol", "Iris & The Fold", "Marlow",
            "Echo Park Social", "Yara Quinn", "North Atlas", "Celeste Ono", "The Driftwood Set", "Kai Moreno",
            "Saffron Hill", "Linnea Strand", "Low Orbit", "Tobias Rae",
        ]
        let firstWords = ["Midnight", "Summer", "Little", "Open", "Broken", "Golden", "Second", "Paper", "Slow", "Neon", "Long", "Silent"]
        let secondWords = ["Drive", "Heart", "Window", "Light", "Road", "Song", "Rain", "Fire", "Morning", "Dance", "Wave", "Line"]
        let motifs: [Motif] = [.rings, .stripes, .sun, .grid, .waves, .dots]
        let blurbs = [
            "recorded in a week, mostly live, mostly at night.",
            "a record about leaving, and about coming back.",
            "big choruses, small rooms, and one very loud organ.",
            "songs written on the road between two long tours.",
            "the sound of a band finally finding its own.",
        ]
        return (0..<count).map { index in
            let genre = genreNames[(index * 7) % genreNames.count]
            let artist = artists[(index * 3) % artists.count]
            let isNew = index % 3 == 0
            let hue = Double((index * 47) % 360) / 360
            return Source(
                title: "\(adjectives[index % adjectives.count]) \(nouns[(index * 7 + index / adjectives.count + 3) % nouns.count])",
                artist: artist,
                year: isNew ? 2026 : 2018 + index % 8,
                genre: genre,
                palette: Palette(
                    light: shade(hue, saturation: 0.38, brightness: 0.96),
                    deep: shade(hue + 0.07, saturation: 0.78, brightness: 0.36),
                    ink: Color(white: 0.98)
                ),
                motif: motifs[(index * 5) % motifs.count],
                isNew: isNew,
                blurb: "\(genre) from \(artist): \(blurbs[index % blurbs.count])",
                tracks: (0..<(7 + index % 4)).map { number in
                    "\(firstWords[(index + number * 5) % firstWords.count]) \(secondWords[(index * 3 + number * 7) % secondWords.count])"
                }
            )
        }
    }

    /// The colour of `hue` (0…1, wrapping) at that saturation and
    /// brightness.
    private static func shade(_ hue: Double, saturation: Double, brightness: Double) -> Color {
        let h = (hue - hue.rounded(.down)) * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double)
        switch Int(h) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return Color(red: Float(r + m), green: Float(g + m), blue: Float(b + m))
    }

    // MARK: - Lyrics

    /// The lines track `id` sings: some of one of the verse sets, started
    /// at a different line for each track so no two read alike.
    private static func lyrics(for id: Int) -> [String] {
        let verses = verseSets[id % verseSets.count]
        let start = (id / verseSets.count) % verses.count
        return Array((verses[start...] + verses[..<start]).prefix(8 + id % 5))
    }

    private static let verseSets: [[String]] = [
        [
            "The harbor lights are coming on",
            "One by one along the shore",
            "I count them like the days you're gone",
            "And then I count them all once more",
            "The tide goes out, the tide comes in",
            "It never asks me where I've been",
            "So hold the rope and hold it tight",
            "We're sailing home tonight",
            "The gulls are quiet on the pier",
            "The fog rolls in and settles here",
            "I hear your voice across the bay",
            "It's calling me to stay",
        ],
        [
            "Turn the radio up, let the static sing",
            "Every station's playing the same old thing",
            "But I don't mind, I've got time to spare",
            "Driving nowhere with the windows down",
            "Sunlight dripping on the edge of town",
            "Every song sounds like a summer dare",
            "Hey, hey, we were only seventeen",
            "Hey, hey, painting everything in green",
            "And the night was ours to keep",
            "Too awake to fall asleep",
            "Turn it up, turn it up again",
            "Sing it louder than we did back then",
        ],
        [
            "Under copper skies we dance",
            "Feet on the ground, hands in the air",
            "Give the rhythm one more chance",
            "Let it carry you anywhere",
            "The drums are talking, listen close",
            "They tell the story we know most",
            "From the market to the sea",
            "Every heartbeat sets us free",
            "Golden hour, golden hour",
            "Feel the music's gentle power",
            "Under copper skies we stay",
            "Till the night becomes the day",
        ],
        [
            "Paper satellites in a cardboard sky",
            "I folded every one and taught them how to fly",
            "Send a signal if you hear me out there",
            "Static in the wires, static in the air",
            "Orbit round the kitchen, orbit round the bed",
            "Every word I meant to say is spinning in my head",
            "Ground control, are you still awake",
            "Tell me how much distance one heart can take",
            "Comets on the ceiling glow a pale green",
            "Brightest thing I've ever seen",
            "Paper satellites, falling slow",
            "Catch them all before you go",
        ],
        [
            "Rain against the window, slow and soft",
            "The kettle hums, the lights are low",
            "An umbrella drying in the loft",
            "Nowhere else we need to go",
            "Let the weather take its time",
            "Let the clouds go drifting by",
            "Every minute feels like rhyme",
            "Every sound a lullaby",
            "Brush the snare and bend the note",
            "Hum the words you never wrote",
            "When the clearing comes at last",
            "We'll be dancing in the past",
        ],
    ]
}
