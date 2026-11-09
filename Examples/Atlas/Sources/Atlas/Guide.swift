//
//  Guide.swift
//  Atlas
//
//  The destinations the guide covers.
//

import NucleantUI

private func palette(_ top: UInt32, _ bottom: UInt32, sun: UInt32, land: UInt32, deep: UInt32) -> Palette {
    Palette(
        skyTop: Color(hex: top),
        skyBottom: Color(hex: bottom),
        sun: Color(hex: sun),
        land: Color(hex: land),
        deep: Color(hex: deep)
    )
}

@MainActor private var nextHighlight = 0

@MainActor private func highlight(_ title: String, _ kind: String, _ summary: String, _ detail: String, hours: String) -> Highlight {
    nextHighlight += 1
    return Highlight(id: nextHighlight, title: title, kind: kind, summary: summary, detail: detail, hours: hours)
}

@MainActor
let guide: [Destination] = [
    Destination(
        id: 1, name: "Lofoten", country: "Norway", region: .europe, landscape: .mountains,
        palette: palette(0x2B3A67, 0xF2A65A, sun: 0xFFE3A3, land: 0x1B2440, deep: 0x141B33),
        tagline: "Granite peaks straight out of the sea",
        about: "A chain of islands above the Arctic Circle where fishing villages sit on stilts at the foot of sheer mountains. In summer the sun never sets; in winter the northern lights do the work.",
        bestMonths: "Jun – Aug, Feb – Mar", language: "Norwegian", currency: "NOK",
        highlights: [
            highlight("Reinebringen", "Hike", "A stone staircase to the view on every postcard.", "Nearly two thousand steps climb from Reine to a ridge four hundred metres above the fjord. Go late in the evening in summer, when the light is low and the crowds have gone.", hours: "2–3 h"),
            highlight("Nusfjord", "Village", "One of the oldest fishing villages in Norway.", "Red rorbuer cabins around a narrow harbour, a general store unchanged since the 1900s, and stockfish drying on wooden racks from February to June.", hours: "Half a day"),
            highlight("Haukland Beach", "Beach", "White sand and water that looks Caribbean — at 8°C.", "Walk the old road around Mannen from here, or simply sit out the midnight sun on the sand.", hours: "Any time"),
        ]
    ),
    Destination(
        id: 2, name: "Kyoto", country: "Japan", region: .asia, landscape: .city,
        palette: palette(0xF6C1B4, 0xFDEBD2, sun: 0xE8505B, land: 0x3B2C35, deep: 0x2A1F26),
        tagline: "A thousand temples and a river of lanterns",
        about: "Japan's capital for a thousand years, still laid out on its old grid: wooden machiya houses, moss gardens, and shrines tucked between ordinary streets.",
        bestMonths: "Mar – May, Oct – Nov", language: "Japanese", currency: "JPY",
        highlights: [
            highlight("Fushimi Inari", "Shrine", "Thousands of vermilion gates up a forested hill.", "The torii tunnel thins out the higher you go; past the halfway crossing you may have the path to yourself. Start at dawn.", hours: "2–3 h"),
            highlight("Gion at dusk", "Walk", "Lantern-lit lanes of teahouses.", "Hanamikoji and the stone lanes of Shirakawa are at their best as the lamps come on. Keep to the street: the alleys are private.", hours: "1–2 h"),
            highlight("Arashiyama", "Nature", "A bamboo grove and a monkey park above the river.", "Arrive before eight for the grove, then cross Togetsukyo bridge and climb to Iwatayama for the view over the city.", hours: "Half a day"),
        ]
    ),
    Destination(
        id: 3, name: "Patagonia", country: "Chile & Argentina", region: .americas, landscape: .mountains,
        palette: palette(0x7FB7D9, 0xD8ECF2, sun: 0xFFFFFF, land: 0x46505A, deep: 0x232A31),
        tagline: "Wind, ice and granite towers",
        about: "The southern tip of the continent: glaciers calving into turquoise lakes, steppe where guanacos outnumber people, and weather that changes four times a day.",
        bestMonths: "Nov – Mar", language: "Spanish", currency: "CLP / ARS",
        highlights: [
            highlight("Torres del Paine", "Hike", "The W trek past the three towers.", "Four to five days between refugios, ending at sunrise below the towers. Book the refugios months ahead.", hours: "4–5 days"),
            highlight("Perito Moreno", "Glacier", "A wall of ice seventy metres high.", "Walkways face the glacier's front; wait long enough and a block the size of a house will fall into the lake.", hours: "Half a day"),
            highlight("Fitz Roy", "Hike", "Laguna de los Tres from El Chaltén.", "Twenty kilometres there and back, the last hour a steep scramble — rewarded with the peak reflected in the lagoon.", hours: "8–10 h"),
        ]
    ),
    Destination(
        id: 4, name: "Sahara", country: "Morocco", region: .africa, landscape: .desert,
        palette: palette(0xE9A15C, 0xF7D9A6, sun: 0xFFF3D6, land: 0xC9682F, deep: 0x5A2A12),
        tagline: "Dunes that glow at sunset",
        about: "The ergs of Merzouga and Chegaga: dunes up to a hundred and fifty metres high, a night in a desert camp, and more stars than you have ever seen.",
        bestMonths: "Oct – Apr", language: "Arabic, Amazigh, French", currency: "MAD",
        highlights: [
            highlight("Erg Chebbi", "Desert", "Ride out to camp by camel.", "Leave Merzouga an hour before sunset, climb the highest dune on foot, and stay up for the stars — there is no light for a hundred kilometres.", hours: "Overnight"),
            highlight("Todra Gorge", "Canyon", "Walls three hundred metres high, ten metres apart.", "The narrowest stretch is at the entrance; follow the river upstream into the palm groves where few people go.", hours: "Half a day"),
            highlight("Aït Benhaddou", "Village", "A fortified ksar of earth and straw.", "Climb to the granary at the top at sunrise, before the tour buses from Marrakech arrive.", hours: "2 h"),
        ]
    ),
    Destination(
        id: 5, name: "Great Barrier Reef", country: "Australia", region: .oceania, landscape: .coast,
        palette: palette(0x4FC3E8, 0xB8EEF5, sun: 0xFFF6B0, land: 0x1C8C9E, deep: 0x0C3E50),
        tagline: "The largest living thing on Earth",
        about: "Two thousand kilometres of coral off Queensland: reefs, cays and islands, sea turtles and manta rays, best seen from the water itself.",
        bestMonths: "Jun – Oct", language: "English", currency: "AUD",
        highlights: [
            highlight("Outer reef", "Snorkel", "A day boat to the reef edge.", "The outer reef has the clearest water and the most life. Choose a small operator out of Port Douglas for fewer people per site.", hours: "Full day"),
            highlight("Whitehaven Beach", "Beach", "Seven kilometres of pure silica sand.", "Walk up to Hill Inlet lookout at low tide, when the sand and water swirl together below.", hours: "Half a day"),
            highlight("Lady Elliot Island", "Island", "A coral cay where manta rays feed.", "Stay overnight: the lagoon at low tide is full of turtles, and in winter humpbacks pass close to shore.", hours: "1–2 days"),
        ]
    ),
    Destination(
        id: 6, name: "Amalfi Coast", country: "Italy", region: .europe, landscape: .coast,
        palette: palette(0x5DA9E9, 0xFCE1C4, sun: 0xFFD27F, land: 0x2F6E8C, deep: 0x16384A),
        tagline: "Lemon groves above a turquoise sea",
        about: "Pastel towns stacked on cliffs, connected by a road carved into the rock and paths that climb from the sea to the hills.",
        bestMonths: "May – Jun, Sep", language: "Italian", currency: "EUR",
        highlights: [
            highlight("Path of the Gods", "Hike", "From Bomerano to Nocelle, high above Positano.", "A balcony path along the cliffs with the whole coast below. Walk it west to east and finish with the steps down to Positano.", hours: "3 h"),
            highlight("Ravello", "Town", "Villas and gardens on a hilltop.", "Villa Cimbrone's Terrace of Infinity looks straight down to the sea; come in the late afternoon.", hours: "Half a day"),
            highlight("Fiordo di Furore", "Cove", "A tiny beach at the bottom of a gorge.", "Steps lead down from the road to a pebble beach under a stone bridge; swim early before the boats arrive.", hours: "1–2 h"),
        ]
    ),
    Destination(
        id: 7, name: "Banff", country: "Canada", region: .americas, landscape: .forest,
        palette: palette(0x8EC5E8, 0xE3F1E8, sun: 0xFFFBEA, land: 0x2D5A43, deep: 0x16301F),
        tagline: "Glacier lakes in the Rockies",
        about: "Canada's first national park: turquoise lakes, hot springs, and a road along a chain of icefields where elk graze at the side.",
        bestMonths: "Jun – Sep, Dec – Mar", language: "English, French", currency: "CAD",
        highlights: [
            highlight("Moraine Lake", "Lake", "The Valley of the Ten Peaks at sunrise.", "Only shuttles go up now; take the first one and climb the rockpile for the view.", hours: "2 h"),
            highlight("Icefields Parkway", "Drive", "Two hundred and thirty kilometres of glaciers.", "Stop at Peyto Lake, Bow Lake and the Athabasca Glacier; allow a whole day and fill the tank before you leave.", hours: "Full day"),
            highlight("Johnston Canyon", "Hike", "Catwalks bolted to a canyon wall.", "The lower falls are an easy half hour; carry on to the upper falls and the ink pots for fewer people.", hours: "3 h"),
        ]
    ),
    Destination(
        id: 8, name: "Hội An", country: "Vietnam", region: .asia, landscape: .city,
        palette: palette(0xF4A259, 0xF9E3B4, sun: 0xE63946, land: 0x6D2E46, deep: 0x3A1828),
        tagline: "A lantern town on the river",
        about: "An old trading port of yellow shophouses, wooden assembly halls and a Japanese bridge, lit by silk lanterns every night.",
        bestMonths: "Feb – Apr", language: "Vietnamese", currency: "VND",
        highlights: [
            highlight("Old Town at night", "Walk", "Lanterns on the Thu Bồn river.", "Buy a paper lantern from the children on the bank and float it downstream; the streets are closed to cars after dark.", hours: "2 h"),
            highlight("An Bàng Beach", "Beach", "A quiet stretch of sand by bicycle.", "Fifteen minutes' ride through rice fields from town; the beach bars rent loungers for the price of a coffee.", hours: "Half a day"),
            highlight("Mỹ Sơn", "Ruins", "Cham temples in a jungle valley.", "Go at opening time to see the brick towers in the morning mist, before the heat and the groups.", hours: "Half a day"),
        ]
    ),
    Destination(
        id: 9, name: "Cape Town", country: "South Africa", region: .africa, landscape: .mountains,
        palette: palette(0x4D7EA8, 0xF5C396, sun: 0xFFE6B3, land: 0x2E3E4F, deep: 0x18222C),
        tagline: "A city under a flat-topped mountain",
        about: "Table Mountain above, two oceans below: beaches with penguins, vineyards an hour away, and the Cape of Good Hope at the end of the road.",
        bestMonths: "Nov – Mar", language: "English, Afrikaans, Xhosa", currency: "ZAR",
        highlights: [
            highlight("Table Mountain", "Hike", "Up Platteklip Gorge, down by cable car.", "Start early to beat the heat and the cloud — the 'tablecloth' can roll in by noon and close the cableway.", hours: "3 h"),
            highlight("Boulders Beach", "Wildlife", "A colony of African penguins.", "Boardwalks lead past the nests; the small beach next to them is shared with the penguins themselves.", hours: "2 h"),
            highlight("Chapman's Peak", "Drive", "Nine kilometres of cliff road.", "One hundred and fourteen curves between Hout Bay and Noordhoek; stop at the lookouts for the sunset.", hours: "1 h"),
        ]
    ),
    Destination(
        id: 10, name: "Milford Sound", country: "New Zealand", region: .oceania, landscape: .forest,
        palette: palette(0x6A8CAF, 0xC9D8E3, sun: 0xF2F6FA, land: 0x24453C, deep: 0x10241E),
        tagline: "Waterfalls down sheer fjord walls",
        about: "A fjord cut by glaciers into Fiordland: cliffs rising straight from black water, rainforest clinging to them, and hundreds of waterfalls after rain.",
        bestMonths: "Dec – Mar", language: "English, Māori", currency: "NZD",
        highlights: [
            highlight("The fjord by boat", "Cruise", "Out to the Tasman Sea and back.", "Rain is good news here: the waterfalls only run after it. Fur seals bask on the rocks near the mouth.", hours: "2 h"),
            highlight("Milford Road", "Drive", "Through the Homer Tunnel.", "Stop at Mirror Lakes and the Chasm; keas wait at the tunnel entrance to inspect your car.", hours: "Half a day"),
            highlight("Milford Track", "Hike", "Four days to the fjord.", "Fifty-three kilometres from Lake Te Anau over Mackinnon Pass to Sandfly Point; permits sell out on the day they open.", hours: "4 days"),
        ]
    ),
]
