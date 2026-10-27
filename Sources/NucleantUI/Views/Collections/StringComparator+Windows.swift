//
//  StringComparator+Windows.swift
//  NucleantUI
//
//  `String.StandardComparator.localizedStandard` — the order a `TableColumn`
//  sorts its text in by default, Finder's — for Windows. Its Foundation
//  (swift-corelibs-foundation) leaves the localized comparators out, so
//  there the name stands for the lexical order, as in the browser: the
//  columns (and an app naming it) sort the same way on every platform's API,
//  by the best order the platform has.
//
#if os(Windows)
import Foundation

extension String.StandardComparator {
    public static let localizedStandard = String.StandardComparator.lexical
}
#endif
