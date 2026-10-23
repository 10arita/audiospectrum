import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (fileName, dimension) in variants {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: dimension, pixelsHigh: dimension,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: dimension * 4, bitsPerPixel: 32
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Unable to allocate icon bitmap.")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(dimension) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()

    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202)
    let backgroundGradient = NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.23, alpha: 1), ending: NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.09, alpha: 1))!
    backgroundGradient.draw(in: background, angle: -90)

    let heights: [CGFloat] = [126, 234, 356, 490, 624, 464, 336, 220, 116]
    for (index, height) in heights.enumerated() {
        let fraction = CGFloat(index) / CGFloat(heights.count - 1)
        let color = NSColor(calibratedHue: 0.48 + fraction * 0.25, saturation: 0.68, brightness: 1, alpha: 1)
        color.setFill()
        let bar = NSBezierPath(roundedRect: NSRect(x: 209 + CGFloat(index) * 70, y: 512 - height / 2, width: 46, height: height), xRadius: 23, yRadius: 23)
        bar.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode icon PNG.")
    }
    try png.write(to: outputDirectory.appendingPathComponent(fileName))
}
