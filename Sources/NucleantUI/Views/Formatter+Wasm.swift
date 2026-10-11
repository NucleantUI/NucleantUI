//
//  Formatter+Wasm.swift
//  NucleantUI
//
//  `Formatter.getObjectValue(_:for:errorDescription:)` — how a
//  `TextField(value:formatter:)` turns its text back into a value — for the
//  browser. WASI's Foundation has the method but keeps it internal, so this
//  one, visible in its place, parses through the concrete formatters' own
//  methods: numbers and dates. Any other formatter parses nothing, leaving
//  the field's value as it was.
//
//  WASI's Foundation has an ICU bug this works around: a NumberFormatter
//  whose parse failed (or stopped short of the end) crashes inside ICU when
//  it is deallocated, if any other ICU work — a calendar, a date or another
//  number formatter — happened since. Such a formatter is kept for the rest
//  of the run instead; a field's formatter usually lives that long anyway.
//
#if os(WASI)
import Foundation

extension Formatter {
    func getObjectValue(
        _ object: UnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription: UnsafeMutablePointer<NSString?>?
    ) -> Bool {
        let parsed: AnyObject?
        switch self {
        case let formatter as NumberFormatter:
            parsed = formatter.number(from: string)
            if parsed == nil {
                FailedNumberParses.keep(formatter)
            }
        case let formatter as DateFormatter:
            parsed = formatter.date(from: string).map { $0 as NSDate }
        default:
            parsed = nil
        }
        guard let parsed else { return false }
        object?.pointee = parsed
        return true
    }
}

/// Number formatters whose parse failed, kept alive (see the top of the file).
private enum FailedNumberParses {
    nonisolated(unsafe) private static var kept: [ObjectIdentifier: NumberFormatter] = [:]

    static func keep(_ formatter: NumberFormatter) {
        kept[ObjectIdentifier(formatter)] = formatter
    }
}
#endif
