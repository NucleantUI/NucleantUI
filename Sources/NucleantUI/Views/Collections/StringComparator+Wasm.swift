//
//  StringComparator+Wasm.swift
//  NucleantUI
//
//  `String.StandardComparator.localizedStandard` — the order a `TableColumn`
//  sorts its text in by default, Finder's — for the browser. WASI's
//  Foundation carries no locale data to sort by and leaves it out; there the
//  name stands for the lexical order, so the columns (and an app naming it)
//  sort the same way on every platform's API, by the best order the platform
//  has.
//
#if os(WASI)
import Foundation

extension String.StandardComparator {
    public static let localizedStandard = String.StandardComparator.lexical
}
#endif
