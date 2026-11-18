// Genera Resources/AppIcon.icns: una barra de disco con un margen libre punteado a la derecha.
// Uso: swift scripts/make-icon.swift   (solo hace falta al cambiar el diseño; el .icns se versiona)
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // Fondo: cuadrado redondeado con el margen estándar de los iconos de macOS (~10 %).
    let inset = s * 0.1
    let box = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = box.width * 0.225
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(NSColor(red: 0.12, green: 0.58, blue: 0.48, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(red: 0.20, green: 0.70, blue: 0.58, alpha: 1).cgColor, NSColor(red: 0.07, green: 0.42, blue: 0.35, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), options: [])
    ctx.restoreGState()
    // Barra: dos tramos ocupados (blanco y blanco translúcido) y el margen libre, punteado.
    let barH = box.height * 0.2
    let y = box.midY - barH / 2
    let x0 = box.minX + box.width * 0.14
    let total = box.width * 0.72
    let gap = box.width * 0.035
    let r = barH * 0.22
    let a = total * 0.38, b = total * 0.2, c = total - a - b - gap * 2
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: x0, y: y, width: a, height: barH), cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: x0 + a + gap, y: y, width: b, height: barH), cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.fillPath()
    let lw = max(1, box.width * 0.022)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(lw)
    ctx.setLineDash(phase: 0, lengths: [lw * 1.6, lw * 1.2])
    ctx.addPath(CGPath(roundedRect: CGRect(x: x0 + a + b + gap * 2 + lw / 2, y: y + lw / 2, width: c - lw, height: barH - lw), cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try process.run()
process.waitUntilExit()
try render(1024).write(to: root.appendingPathComponent("Resources/AppIcon-1024.png"))
print(process.terminationStatus == 0 ? "Icono: \(out.path)" : "iconutil falló")
