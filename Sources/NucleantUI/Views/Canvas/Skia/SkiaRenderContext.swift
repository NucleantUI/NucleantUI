//
//  SkiaRenderContext.swift
//  NucleantUI
//
import NucleantSkia

/// The drawing and the two callbacks of a `SkiaCanvasView`, on an object the
/// author owns.
///
/// A class, so it can hold what it draws with — `SkPaint`s, `SkPath`s,
/// shaders — and change them in place on `update`, and so the view compares
/// it by identity: the same object is the same input. Make it `@Observable`
/// and read its properties in `update` for a change to them to run `update`
/// again. Both callbacks run on the main actor, when the canvas the view is
/// on is drawn.
///
/// `context` is the Skia canvas the views around it are drawn on, at the
/// view's origin and cut to its frame; sizes and coordinates are points.
public protocol SkiaRenderContext: AnyObject {
    /// Once per view, in its first draw, before `update`: set up what the
    /// drawing keeps.
    func onAppear(context: borrowing SkCanvas, size: SIMD2<Float>)
    /// After `onAppear`, and again whenever something it read changed or the
    /// size did — and whenever the canvas it is on is drawn again.
    func update(context: borrowing SkCanvas, size: SIMD2<Float>)
}
