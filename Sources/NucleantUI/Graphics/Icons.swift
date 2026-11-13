//
//  Icons.swift
//  NucleantUI
//
//  The icons NucleantUI's own controls draw. Each is a Material Icons SVG
//  (Apache 2.0, `Resources/Icons/MaterialIcons-LICENSE.txt`), copied into
//  `Resources/Icons` when a control needs it, not the whole set, and
//  compiled into the library (`.embedInCode` in Package.swift). So every
//  platform has it with no file to find at run time.
//

import Foundation

@MainActor
final class Icons {

    /// The one every control draws from, so each icon is parsed once.
    static let shared = Icons()

    /// The navigation bar's back button: Material's `arrow_back_ios_new`,
    /// a chevron pointing back, in a 24-point box.
    private(set) lazy var back = Self.parse(PackageResources.arrow_back_ios_new_svg)

    /// The navigation bar's "…", which opens the `.secondaryAction` items:
    /// Material's `more_horiz`, three dots in a row.
    private(set) lazy var more = Self.parse(PackageResources.more_horiz_svg)

    /// One of our own files, which a test parses: one that doesn't parse
    /// is a broken build, not a state a control has to handle.
    private static func parse(_ bytes: [UInt8]) -> SvgImage {
        guard let image = SvgImage(data: Data(bytes)) else {
            fatalError("NucleantUI: a bundled icon is not SVG")
        }
        return image
    }
}
