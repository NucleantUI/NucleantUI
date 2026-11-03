//
//  BundleModule.swift
//  Examples (Xcode)
//
//  SwiftPM gives a package target with resources a `Bundle.module`; an app
//  target in an Xcode project has none, and its resources are in the app's
//  own bundle. This is that accessor for an example that reads its
//  resources through `Bundle.module`, so its sources build here unchanged.
//

import Foundation

extension Bundle {
    static var module: Bundle { .main }
}
