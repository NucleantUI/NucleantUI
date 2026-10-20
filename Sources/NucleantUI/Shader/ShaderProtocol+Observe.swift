//
//  ShaderProtocol+Observe.swift
//  NucleantUI
//
import Dispatch
import Observation

extension ShaderProtocol {

    /// Call `onChange` with the shader each time anything its input packs
    /// changes — to `render(into:)` a texture a model holds, say. Not called
    /// for the values as they are now, only for changes to them.
    ///
    /// `onChange` says whether to keep watching: `false` stops it.
    ///
    /// ```swift
    /// shader.observe { [weak self] shader in
    ///     guard let self else { return false }
    ///     shader.render(into: self.thumbnail)
    ///     return true
    /// }
    /// ```
    @MainActor
    public func observe(_ onChange: @escaping @MainActor (Self) -> Bool) {
        // Only ever used on the main actor, after the hop below.
        nonisolated(unsafe) let shader = self
        withObservationTracking {
            var bytes: [UInt8] = []
            input.pack(into: &bytes)
        } onChange: {
            // On whichever thread wrote; the shader is the main actor's.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if onChange(shader) { shader.observe(onChange) }
                }
            }
        }
    }
}
