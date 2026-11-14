//
//  ColorView.swift
//  NucleantUI
//
//  `Color` doubles as a view that fills whatever it is given — `Color.red` as a
//  background, `Color.clear` as a spacer that still takes space.
//

extension Color: View {
    public var body: Never {
        preconditionFailure("Color is a primitive view — its body is never evaluated.")
    }
}

extension Color: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        let color = self
        return ContentNode(content: ShapeContent(
            shape: Rectangle(),
            drawn: nil,
            fill: .color(color),
            stroke: nil,
            strokeStyle: StrokeStyle(),
            idealSize: nil,
            animatedFill: context.animatedPaint(.fill, .color(color))
        ))
    }
}
