import SwiftUI

/// La curva negra del header de auth — un "swoosh" diagonal inspirado en
/// headers curvos de apps fintech/e-commerce, con la marca de Amadai encima.
struct AuthHeaderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.58))
        path.addCurve(
            to: CGPoint(x: 0, y: rect.height * 0.82),
            control1: CGPoint(x: rect.width * 0.62, y: rect.height * 1.22),
            control2: CGPoint(x: rect.width * 0.30, y: rect.height * 0.48)
        )
        path.closeSubpath()
        return path
    }
}
