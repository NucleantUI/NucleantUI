//
//  ViewTexture+Wasm.swift
//  NucleantUI
//
//  The page's name for a texture's window, for content the browser shows
//  over the view rather than through its texture — a web page in an
//  <iframe> (Platform_Wasm's `BrowserFrame`), placed at `frame` and cut to
//  `visibleFrame`.
//

#if os(WASI)
import Platform_Wasm

extension ViewTexture {
    /// The id the page knows the view's window by (`PlatformWindow.windowID`)
    /// — `nil` while the view is in no window on the page.
    public var browserWindowID: UInt32? {
        window?.platformWindow?.windowID
    }
}
#endif
