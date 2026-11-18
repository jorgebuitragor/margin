// Icono de ejemplo para las apps de scripts/demo-home.sh: cuadrado redondeado con degradado y un símbolo SF.
// Uso: demo-icon <símbolo> <rojo> <verde> <azul> <salida.png>   (componentes de 0 a 1)
import AppKit

let args = CommandLine.arguments
guard args.count == 6, let r = Double(args[2]), let g = Double(args[3]), let b = Double(args[4]) else {
    FileHandle.standardError.write("Uso: demo-icon <símbolo> <r> <g> <b> <salida.png>\n".data(using: .utf8)!)
    exit(1)
}
let px = 1024
let s = CGFloat(px)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// A sangre, sin margen ni esquinas: macOS 26 recorta el icono con su forma; con margen propio lo encoge dentro de
// una placa blanca.
let box = CGRect(x: 0, y: 0, width: s, height: s)
let path = CGPath(rect: box, transform: nil)
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let light = NSColor(red: min(1, r + 0.18), green: min(1, g + 0.18), blue: min(1, b + 0.18), alpha: 1)
let dark = NSColor(red: r * 0.7, green: g * 0.7, blue: b * 0.7, alpha: 1)
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [light.cgColor, dark.cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), options: [])
ctx.restoreGState()
let config = NSImage.SymbolConfiguration(pointSize: s * 0.34, weight: .semibold).applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: args[1], accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let size = symbol.size
    symbol.draw(in: CGRect(x: (s - size.width) / 2, y: (s - size.height) / 2, width: size.width, height: size.height))
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[5]))
