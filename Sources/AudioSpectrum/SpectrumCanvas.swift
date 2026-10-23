import SwiftUI

struct SpectrumCanvas: View {
    let bands: [Float]
    let style: SpectrumStyle
    let palette: SpectrumPalette
    let sensitivity: Double
    var showsGuides = true

    var body: some View {
        Canvas { context, size in
            guard !bands.isEmpty, size.width > 0, size.height > 0 else { return }
            let values = bands.map { min(1.0, max(0.0, Double($0) * sensitivity)) }
            if showsGuides { drawGuides(context: &context, size: size) }
            let gradient = GraphicsContext.Shading.linearGradient(
                Gradient(colors: palette.colors), startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            )
            switch style {
            case .circular:
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let shortest = min(size.width, size.height)
                let radius = shortest * 0.25
                let reach = shortest * 0.19
                let thickness = max(2, min(7, 2 * .pi * radius / Double(values.count) * 0.53))
                for (index, value) in values.enumerated() {
                    let angle = Double(index) / Double(values.count) * 2 * .pi - .pi / 2
                    let start = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    let end = CGPoint(x: center.x + cos(angle) * (radius + max(1.5, value * reach)),
                                      y: center.y + sin(angle) * (radius + max(1.5, value * reach)))
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    context.stroke(path, with: gradient, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                }
            case .mirrored, .bottom:
                let margin: CGFloat = 16
                let width = max(1, size.width - margin * 2)
                let step = width / Double(values.count)
                let barWidth = max(1, step * 0.65)
                let maximum = style == .mirrored ? size.height * 0.40 : size.height * 0.80
                for (index, value) in values.enumerated() {
                    let extent = max(2, value * maximum)
                    let height = style == .mirrored ? extent * 2 : extent
                    let y = style == .mirrored ? size.height / 2 - extent : size.height * 0.91 - extent
                    let rect = CGRect(x: margin + Double(index) * step + (step - barWidth) / 2,
                                      y: y, width: barWidth, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: min(barWidth / 2, 3)), with: gradient)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.title)のオーディオスペクトラム")
        .accessibilityValue("低音から高音まで、\(bands.count)帯域")
    }

    private func drawGuides(context: inout GraphicsContext, size: CGSize) {
        let line = Color.white.opacity(0.065)
        if style == .circular {
            let radius = min(size.width, size.height) * 0.25
            for multiplier in [1.0, 1.38, 1.76] {
                let r = radius * multiplier
                context.stroke(Path(ellipseIn: CGRect(x: size.width / 2 - r, y: size.height / 2 - r,
                                                       width: r * 2, height: r * 2)), with: .color(line), lineWidth: 1)
            }
        } else {
            for fraction in [0.1, 0.3, 0.5, 0.7, 0.9] {
                var path = Path()
                path.move(to: CGPoint(x: 16, y: size.height * fraction))
                path.addLine(to: CGPoint(x: size.width - 16, y: size.height * fraction))
                context.stroke(path, with: .color(line), lineWidth: 1)
            }
        }
    }
}
