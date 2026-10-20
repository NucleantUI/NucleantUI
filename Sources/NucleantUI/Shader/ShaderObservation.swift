//
//  ShaderObservation.swift
//  NucleantUI
//
import Dispatch
import Observation

/// A shader being watched for changes to its input — what
/// `ShaderProtocol.observe` returns.
///
/// Watching lasts as long as this is held: `cancel()` it, or let it go. It
/// is this object that holds the shader and the handler, never the input
/// being watched, so a model that drops it leaves nothing behind.
@MainActor
public final class ShaderObservation {
    private var pack: (@MainActor () -> Void)?
    private var changed: (@MainActor () -> Void)?

    init(pack: @escaping @MainActor () -> Void, changed: @escaping @MainActor () -> Void) {
        self.pack = pack
        self.changed = changed
        track()
    }

    /// Stop: the handler is not called again.
    public func cancel() {
        pack = nil
        changed = nil
    }

    /// Pack under observation; the first change to anything packed calls the
    /// handler, on the main actor, and watches again.
    private func track() {
        guard let pack else { return }
        withObservationTracking(pack) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.fire() }
            }
        }
    }

    private func fire() {
        guard let changed else { return }
        changed()
        track()
    }
}

extension ShaderProtocol {

    /// Call `onChange` with the shader each time anything its input packs
    /// changes — to `render(into:)` a texture a model holds, say. Not called
    /// for the values as they are now, only for changes to them.
    ///
    /// Hold the result for as long as it should run.
    @MainActor
    public func observe(_ onChange: @escaping @MainActor (Self) -> Void) -> ShaderObservation {
        let shader = self
        return ShaderObservation(
            pack: {
                var bytes: [UInt8] = []
                shader.input.pack(into: &bytes)
            },
            changed: { onChange(shader) }
        )
    }
}
