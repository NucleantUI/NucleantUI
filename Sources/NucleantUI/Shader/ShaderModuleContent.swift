//
//  ShaderModuleContent.swift
//  NucleantUI
//

/// What a `Shader` over a `ShaderProtocol` lays out as: a GPU slot for the
/// module, at its rect. Emits no draw commands of its own — its pixels arrive
/// through the engine, not the canvas.
struct ShaderModuleContent<Input: ShaderInput>: NodeContent {
    let path: [Int]
    let words: [UInt32]
    let input: Input
    let isAnimated: Bool
    let draw: ShaderDraw
    let textures: ShaderTextures

    func sizeThatFits(_ proposal: ProposedSize, node: ViewNode) -> Size {
        proposal.replacingUnspecifiedDimensions()
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard rect.width > 0, rect.height > 0, let host = ShaderHost.current else { return }
        host.useModule(
            path: path,
            words: words,
            input: input,
            isAnimated: isAnimated,
            draw: draw,
            textures: textures,
            rect: rect,
            clip: context.compositeClip
        )
        host.boundaries.noteNested(at: list.commands.count, rect: context.compositeClip.map { rect.intersection($0) } ?? rect)
    }
}
