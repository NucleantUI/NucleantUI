//
//  FontRegistry.swift
//  NucleantUI
//
//  Which face a `Font` is drawn in: a name for it, the file it comes from,
//  and the Skia face loaded from that file (`SkiaFonts` draws and measures
//  with it). The name is ours, so a `Font` maps to one deterministically;
//  a face is accepted once Skia has read its file.
//
//  Everything here is cached — *including failures*. Resolution sits on the
//  layout hot path (every text measurement asks for it), and an uncached miss
//  costs a full file read plus a parse attempt. Without the negative caches
//  below, one rebuild of a modest view tree spent ~300ms re-reading the same
//  unparseable font over and over.
//

import Foundation
import NucleantSkia
// Apple-only: the system-font lookup below. Everywhere else the bundled
// Roboto faces are the whole story — on Android they are also what the OS
// itself ships, so there is nothing a platform query would add.
#if canImport(CoreText)
import CoreText
#endif

@MainActor
public enum FontRegistry {

    /// What a `Font` actually resolves to, so the whole lookup below runs once
    /// per distinct font rather than once per measurement. `nil` values are
    /// cached too — a font with no usable face must not be re-searched.
    private static var resolutions: [ResolutionKey: String?] = [:]

    private struct ResolutionKey: Hashable {
        let family: String?
        let design: FontDesign
        let isBold: Bool
        let isItalic: Bool
    }

    /// Face names whose file Skia read, and ones already proven unusable —
    /// either not found on disk or not readable as a face.
    private static var loaded: Set<String> = []
    private static var failed: Set<String> = []

    /// Explicit registrations: our family name → file path.
    private static var registeredPaths: [String: String] = [:]

    /// Every face accepted: family name → the file it came from, and the
    /// face read from it.
    private static var loadedPaths: [String: String] = [:]
    private static var loadedTypefaces: [String: SkTypeface] = [:]

    /// Where the built-in designs come from, in preference order. The bundled
    /// faces (`bundledFaces`) lead: they are in the library's resource bundle
    /// on every platform, so the default look never depends on what the OS
    /// ships — iOS has no Helvetica Neue outside a `.ttc`, Linux has none of
    /// these. The system names after them are what an explicit request or a
    /// design without a bundled face (serif) falls through to; ordered so a
    /// single-face file comes first — macOS ships Helvetica and Menlo *only*
    /// as `.ttc` collections, which are not looked for (see
    /// `fontExtensions`).
    private static let builtinFaces: [FontDesign: [String]] = [
        .default:    ["Roboto", "Helvetica Neue", "Arial", "Geneva", "Helvetica"],
        .serif:      ["Times New Roman", "Georgia", "Palatino", "Roboto"],
        .monospaced: ["Roboto Mono", "Monaco", "Courier New", "Andale Mono", "Menlo"],
        .rounded:    ["Roboto", "Arial Rounded Bold", "Arial", "Geneva"],
    ]

    /// Face name → file in the library's `Resources/Fonts`. Roboto and Roboto
    /// Mono, Apache 2.0 / OFL; the licences sit next to the files.
    private static let bundledFaces: [String: String] = [
        "Roboto":                  "Roboto-Regular",
        "Roboto Bold":             "Roboto-Bold",
        "Roboto Italic":           "Roboto-Italic",
        "Roboto Bold Italic":      "Roboto-BoldItalic",
        "Roboto Mono":             "RobotoMono-Regular",
        "Roboto Mono Bold":        "RobotoMono-Bold",
        "Roboto Mono Italic":      "RobotoMono-Italic",
        "Roboto Mono Bold Italic": "RobotoMono-BoldItalic",
    ]

    /// Directories scanned for a face named by `builtinFaces` as a
    /// `Family Bold.ttf`-style file — the macOS layout. iOS keeps its fonts in
    /// subdirectories (`Core/`, `WebFonts/`, …) under names without spaces
    /// (`ArialBold.ttf`), so a face not found here is asked of CoreText
    /// instead, which knows the file for a family on both platforms.
    private static let searchDirectories = [
        "/System/Library/Fonts",
        "/System/Library/Fonts/Supplemental",
        "/Library/Fonts",
        NSHomeDirectory() + "/Library/Fonts",
    ]

    /// Extensions worth trying. `.ttc` is absent: a TrueType *Collection*
    /// holds several faces in one file, and which of them a name means is
    /// not in its file name — the faces chosen here are the single-face
    /// files the names above lead to, as they always were.
    private static let fontExtensions = [".ttf", ".otf"]

    /// Register a font file under a family name usable as `Font.custom(_:size:)`.
    /// Returns false when the file can't be read as a face.
    @discardableResult
    public static func register(path: String, as family: String) -> Bool {
        registeredPaths[family] = path
        failed.remove(family)
        loaded.remove(family)
        resolutions.removeAll(keepingCapacity: true)
        return load(family: family, from: path)
    }

    /// The name of the face `font` is drawn in, its file read on first use.
    /// `nil` when none was found: the platform's default face draws it.
    static func resolve(_ font: Font) -> String? {
        let key = ResolutionKey(
            family: font.family,
            design: font.design,
            isBold: font.weight.isBoldFace,
            isItalic: font.isItalic
        )
        if let cached = resolutions[key] { return cached }

        let resolved = search(key)
        resolutions[key] = resolved
        return resolved
    }

    /// The file behind a name `resolve` returned.
    static func path(ofResolved family: String) -> String? {
        loadedPaths[family]
    }

    /// The face behind a name `resolve` returned.
    static func typeface(ofResolved family: String) -> SkTypeface? {
        loadedTypefaces[family]
    }

    private static func search(_ key: ResolutionKey) -> String? {
        let candidates = key.family.map { [$0] }
            ?? builtinFaces[key.design]
            ?? builtinFaces[.default]!

        for family in candidates {
            for name in faceNames(family: family, bold: key.isBold, italic: key.isItalic) {
                if ensureLoaded(name) { return name }
            }
            #if canImport(CoreText)
            // Nothing under a macOS-style file name; let CoreText name the
            // file, most specific style first, like `faceNames`.
            for (bold, italic) in styleFallbacks(bold: key.isBold, italic: key.isItalic) {
                let name = faceNames(family: family, bold: bold, italic: italic)[0]
                if ensureLoaded(name, coreTextFamily: family, bold: bold, italic: italic) { return name }
            }
            #endif
        }
        return nil
    }

    /// The style combinations to try for a requested weight/slant, most
    /// specific first, ending in the regular face.
    private static func styleFallbacks(bold: Bool, italic: Bool) -> [(Bool, Bool)] {
        var styles: [(Bool, Bool)] = []
        if bold && italic { styles.append((true, true)) }
        if bold           { styles.append((true, false)) }
        if italic         { styles.append((false, true)) }
        styles.append((false, false))
        return styles
    }

    /// The file-name variants a family/weight/italic combination might be
    /// stored under, most specific first — macOS ships these as separate
    /// `Family Bold.ttf` / `Family Italic.ttf` files rather than one variable
    /// font, so the style is part of the name.
    private static func faceNames(family: String, bold: Bool, italic: Bool) -> [String] {
        var names: [String] = []
        if bold && italic { names.append("\(family) Bold Italic") }
        if bold           { names.append("\(family) Bold") }
        if italic         { names.append("\(family) Italic") }
        names.append(family)
        return names
    }

    /// Read the face `name` if it isn't already read. The name doubles as the
    /// file's basename when it wasn't explicitly registered.
    private static func ensureLoaded(_ name: String) -> Bool {
        if loaded.contains(name) { return true }
        if failed.contains(name) { return false }

        let path = registeredPaths[name] ?? locate(name)
        guard let path, load(family: name, from: path) else {
            failed.insert(name)
            return false
        }
        return true
    }

    #if canImport(CoreText)
    /// `ensureLoaded(_:)` with CoreText locating the file. Keyed apart from
    /// the file-name lookup so a miss there doesn't poison this one.
    private static func ensureLoaded(_ name: String, coreTextFamily family: String, bold: Bool, italic: Bool) -> Bool {
        if loaded.contains(name) { return true }
        let key = "coretext:" + name
        if failed.contains(key) { return false }

        guard let path = locateWithCoreText(family: family, bold: bold, italic: italic),
              load(family: name, from: path) else {
            failed.insert(key)
            return false
        }
        return true
    }

    /// The font file CoreText would use for `family` in the given style, if it
    /// is a single-face file. Family and traits are both
    /// mandatory in the match, so a family without a bold face yields nil
    /// here rather than a silently regular one — the caller then falls back
    /// to the next style itself.
    private static func locateWithCoreText(family: String, bold: Bool, italic: Bool) -> String? {
        var traits = CTFontSymbolicTraits()
        if bold   { traits.insert(.boldTrait) }
        if italic { traits.insert(.italicTrait) }
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontTraitsAttribute: [kCTFontSymbolicTrait: traits.rawValue],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let mandatory: Set<CFString> = [kCTFontFamilyNameAttribute, kCTFontTraitsAttribute]
        guard let match = CTFontDescriptorCreateMatchingFontDescriptor(descriptor, mandatory as CFSet),
              let url = CTFontDescriptorCopyAttribute(match, kCTFontURLAttribute) as? URL else {
            return nil
        }
        let path = url.path
        guard fontExtensions.contains(where: { path.lowercased().hasSuffix($0) }),
              FileManager.default.isReadableFile(atPath: path) else {
            return nil
        }
        return path
    }
    #endif

    private static func locate(_ name: String) -> String? {
        if let file = bundledFaces[name] {
            #if os(Android) || os(WASI)
            // Not `Bundle.module`: its generated accessor resolves against the
            // executable's directory, which for an Android app is the zygote's
            // (/system/bin), and it `fatalError`s rather than returning nil —
            // so it cannot even be tried and allowed to fail. The Activity
            // unpacks the package's resource bundles next to the app's files
            // and exports that directory here. In the browser the accessor
            // names directories on the machine that built the module; the
            // page mounts the bundles in the module's file system instead and
            // exports that directory the same way (NucleantApplication's
            // Web/nucleant-app.js).
            if let root = ProcessInfo.processInfo.environment["NUCLEANT_APP_PATH"] {
                let path = "\(root)/NucleantUI_NucleantUI.resources/Fonts/\(file).ttf"
                if FileManager.default.isReadableFile(atPath: path) { return path }
            }
            #else
            if let url = Bundle.module.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts") {
                return url.path
            }
            #endif
        }
        let manager = FileManager.default
        for directory in searchDirectories {
            for suffix in fontExtensions {
                let path = "\(directory)/\(name)\(suffix)"
                if manager.isReadableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    private static func load(family: String, from path: String) -> Bool {
        guard let typeface = SkFontMgr.makeFromFile(path) else { return false }
        loaded.insert(family)
        loadedPaths[family] = path
        loadedTypefaces[family] = typeface
        return true
    }
}
