//
//  Formatter+Linux.swift
//  NucleantUI
//
//  `Formatter.getObjectValue(_:for:errorDescription:)` — how a
//  `TextField(value:formatter:)` turns its text back into a value — for
//  Linux. Its Foundation (swift-corelibs-foundation) has the method but
//  keeps it internal, so this one, visible in its place, parses through the
//  concrete formatters' own methods: numbers and dates. Any other formatter
//  parses nothing, leaving the field's value as it was.
//
#if os(Linux)
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
#endif
