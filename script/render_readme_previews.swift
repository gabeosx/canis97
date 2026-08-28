#!/usr/bin/env swift

import AppKit
import Foundation

private struct PreviewTheme {
    let source: String
    let destination: String
    let logicalSize: CGSize
    let foreground: NSColor
    let panel: NSColor
    let accent: NSColor
    let artworkColors: (NSColor, NSColor)
}

private let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let outputDirectory = repositoryRoot.appending(path: "docs/screenshots", directoryHint: .isDirectory)

private let themes = [
    PreviewTheme(
        source: "SiriusMac/Skins/Bundled/Assets/PocketDiscFaceplate@2x.png",
        destination: "pocket-disc.png",
        logicalSize: CGSize(width: 384, height: 320),
        foreground: NSColor(calibratedRed: 0.82, green: 0.91, blue: 0.70, alpha: 1),
        panel: NSColor(calibratedWhite: 0.06, alpha: 0.70),
        accent: NSColor(calibratedRed: 0.72, green: 0.94, blue: 0.36, alpha: 1),
        artworkColors: (
            NSColor(calibratedRed: 0.20, green: 0.09, blue: 0.36, alpha: 1),
            NSColor(calibratedRed: 0.98, green: 0.34, blue: 0.25, alpha: 1)
        )
    ),
    PreviewTheme(
        source: "SiriusMac/Skins/Bundled/Assets/AquaVistaFaceplate@2x.png",
        destination: "aqua-vista.png",
        logicalSize: CGSize(width: 448, height: 304),
        foreground: NSColor(calibratedRed: 0.03, green: 0.20, blue: 0.23, alpha: 1),
        panel: NSColor(calibratedRed: 0.75, green: 0.96, blue: 0.95, alpha: 0.48),
        accent: NSColor(calibratedRed: 0.04, green: 0.45, blue: 0.37, alpha: 1),
        artworkColors: (
            NSColor(calibratedRed: 0.05, green: 0.31, blue: 0.46, alpha: 1),
            NSColor(calibratedRed: 0.26, green: 0.89, blue: 0.69, alpha: 1)
        )
    ),
]

private func topRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, canvasHeight: CGFloat) -> NSRect {
    NSRect(x: x, y: canvasHeight - y - height, width: width, height: height)
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    (text as NSString).draw(
        in: rect,
        withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    )
}

private func drawRoundedPanel(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

private func render(_ theme: PreviewTheme) throws {
    let sourceURL = repositoryRoot.appending(path: theme.source)
    guard let faceplate = NSImage(contentsOf: sourceURL) else {
        throw CocoaError(.fileReadCorruptFile)
    }

    let scale: CGFloat = 2
    let canvas = CGSize(width: theme.logicalSize.width * scale, height: theme.logicalSize.height * scale)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width),
        pixelsHigh: Int(canvas.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    faceplate.draw(in: NSRect(origin: .zero, size: canvas))

    let isPocket = theme.destination == "pocket-disc.png"
    let artwork = isPocket
        ? topRect(32, 28, 88, 88, canvasHeight: theme.logicalSize.height)
        : topRect(32, 40, 112, 104, canvasHeight: theme.logicalSize.height)
    let channel = isPocket
        ? topRect(140, 32, 160, 24, canvasHeight: theme.logicalSize.height)
        : topRect(156, 44, 208, 32, canvasHeight: theme.logicalSize.height)
    let metadata = isPocket
        ? topRect(136, 56, 168, 48, canvasHeight: theme.logicalSize.height)
        : topRect(156, 80, 208, 56, canvasHeight: theme.logicalSize.height)
    let favorite = isPocket
        ? topRect(312, 28, 40, 40, canvasHeight: theme.logicalSize.height)
        : topRect(376, 36, 48, 48, canvasHeight: theme.logicalSize.height)
    let status = isPocket
        ? topRect(32, 116, 88, 32, canvasHeight: theme.logicalSize.height)
        : topRect(28, 156, 152, 36, canvasHeight: theme.logicalSize.height)
    let transport = isPocket
        ? topRect(200, 112, 136, 56, canvasHeight: theme.logicalSize.height)
        : topRect(188, 216, 176, 56, canvasHeight: theme.logicalSize.height)
    let library = isPocket
        ? topRect(28, 252, 88, 40, canvasHeight: theme.logicalSize.height)
        : topRect(28, 244, 112, 40, canvasHeight: theme.logicalSize.height)
    let overflow = isPocket
        ? topRect(308, 252, 40, 40, canvasHeight: theme.logicalSize.height)
        : topRect(376, 228, 48, 52, canvasHeight: theme.logicalSize.height)
    let controlForeground = isPocket ? theme.foreground : NSColor(calibratedWhite: 0.94, alpha: 0.92)

    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)

    drawRoundedPanel(artwork, radius: 12, color: theme.artworkColors.0)
    NSGradient(starting: theme.artworkColors.0, ending: theme.artworkColors.1)?.draw(in: artwork, angle: 42)
    theme.accent.withAlphaComponent(0.82).setStroke()
    let orbit = NSBezierPath(ovalIn: artwork.insetBy(dx: artwork.width * 0.18, dy: artwork.height * 0.18))
    orbit.lineWidth = 3
    orbit.stroke()
    theme.foreground.setFill()
    NSBezierPath(ovalIn: NSRect(x: artwork.midX - 5, y: artwork.midY - 5, width: 10, height: 10)).fill()

    drawRoundedPanel(channel, radius: 5, color: theme.panel)
    drawText("42 · Demo Channel", in: channel.insetBy(dx: 7, dy: 5), size: isPocket ? 10 : 12, weight: .semibold, color: theme.foreground)

    drawRoundedPanel(metadata, radius: 6, color: theme.panel)
    let metadataInset = metadata.insetBy(dx: 8, dy: 6)
    drawText("Midnight Signal", in: NSRect(x: metadataInset.minX, y: metadataInset.midY, width: metadataInset.width, height: metadataInset.height / 2), size: isPocket ? 10 : 12, weight: .semibold, color: theme.foreground)
    drawText("Synthetic preview", in: NSRect(x: metadataInset.minX, y: metadataInset.minY, width: metadataInset.width, height: metadataInset.height / 2), size: isPocket ? 8 : 10, weight: .regular, color: theme.foreground.withAlphaComponent(0.78))

    drawText("★", in: favorite.insetBy(dx: 4, dy: isPocket ? 9 : 11), size: isPocket ? 18 : 22, weight: .bold, color: theme.accent, alignment: .center)

    drawRoundedPanel(status, radius: status.height / 2, color: theme.panel)
    drawText("PLAYING", in: status.insetBy(dx: 7, dy: isPocket ? 9 : 10), size: isPocket ? 8 : 10, weight: .bold, color: theme.accent, alignment: .center)

    let buttonWidth = transport.width / 3
    for (index, symbol) in ["◀", "Ⅱ", "▶"].enumerated() {
        let button = NSRect(x: transport.minX + CGFloat(index) * buttonWidth, y: transport.minY, width: buttonWidth, height: transport.height)
        drawText(symbol, in: button.insetBy(dx: 3, dy: isPocket ? 17 : 18), size: isPocket ? 13 : 16, weight: .bold, color: controlForeground, alignment: .center)
    }

    drawText("LIBRARY", in: library.insetBy(dx: 6, dy: 13), size: isPocket ? 8 : 10, weight: .bold, color: controlForeground, alignment: .center)
    drawText("•••", in: overflow.insetBy(dx: 4, dy: 12), size: isPocket ? 13 : 16, weight: .bold, color: controlForeground, alignment: .center)

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: outputDirectory.appending(path: theme.destination), options: .atomic)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for theme in themes {
    try render(theme)
}
