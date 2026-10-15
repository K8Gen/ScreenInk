// Draws the app icon and writes Resources/AppIcon.icns. Run with `make icon`.
// Every size is drawn natively (no resampling); geometry is on Apple's 1024-pt icon grid.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func mix(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> CGColor {
    func channel(_ shift: UInt32) -> CGFloat {
        let x = CGFloat(a >> shift & 0xFF), y = CGFloat(b >> shift & 0xFF)
        return (x + (y - x) * t) / 255
    }
    return CGColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: 1)
}

/// Point on a cubic Bézier.
func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}

let inkStart: UInt32 = 0xFF4D5E
let inkEnd: UInt32 = 0xFFB020

/// Draws the icon into `context`, in 1024-pt top-left coordinates.
func drawIcon(_ context: CGContext) {
    // Squircle-ish tile with a soft drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x000000, 0.35))
    context.addPath(tilePath)
    context.setFillColor(color(0x2B3FB0))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x5C7CFA), color(0x1C2775)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(
        background, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

    // The display being drawn on.
    let screen = CGRect(x: 196, y: 262, width: 632, height: 410)
    let screenPath = CGPath(roundedRect: screen, cornerWidth: 40, cornerHeight: 40, transform: nil)
    context.addPath(screenPath)
    context.setFillColor(color(0xFFFFFF, 0.12))
    context.fillPath()
    context.addPath(screenPath)
    context.setStrokeColor(color(0xFFFFFF, 0.55))
    context.setLineWidth(14)
    context.strokePath()
    // Stand.
    let stand = CGMutablePath()
    stand.addRect(CGRect(x: 482, y: 679, width: 60, height: 66))
    stand.addRoundedRect(in: CGRect(x: 392, y: 742, width: 240, height: 22), cornerWidth: 11, cornerHeight: 11)
    context.addPath(stand)
    context.setFillColor(color(0xFFFFFF, 0.55))
    context.fillPath()  // one fill, so the overlap doesn't double up

    // Ink stroke: tapered, warm gradient along its length.
    let p0 = CGPoint(x: 262, y: 560), p1 = CGPoint(x: 380, y: 380)
    let p2 = CGPoint(x: 470, y: 640), p3 = CGPoint(x: 660, y: 392)
    let steps = 400
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let point = bezier(p0, p1, p2, p3, t)
        let radius = 12 + 24 * sin(t * .pi)  // tapers to the nib's width at both ends
        context.setFillColor(mix(inkStart, inkEnd, t))
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }
    context.restoreGState()

    // Pen, its tip at the end of the stroke, body up and to the right.
    context.saveGState()
    context.translateBy(x: p3.x, y: p3.y)
    context.rotate(by: -.pi / 4)
    context.setShadow(offset: CGSize(width: 0, height: 8), blur: 16, color: color(0x000000, 0.3))
    let body = CGMutablePath()
    body.move(to: .zero)
    body.addLine(to: CGPoint(x: 78, y: -40))
    body.addLine(to: CGPoint(x: 230, y: -40))
    body.addArc(center: CGPoint(x: 230, y: 0), radius: 40, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    body.addLine(to: CGPoint(x: 78, y: 40))
    body.closeSubpath()
    context.addPath(body)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)
    // Ferrule band and the inked nib.
    context.setFillColor(color(0xD5DAE8))
    context.fill(CGRect(x: 78, y: -40, width: 34, height: 80))
    let nib = CGMutablePath()
    nib.move(to: .zero)
    nib.addLine(to: CGPoint(x: 30, y: -15.4))
    nib.addLine(to: CGPoint(x: 30, y: 15.4))
    nib.closeSubpath()
    context.addPath(nib)
    context.setFillColor(color(inkEnd))
    context.fillPath()
    context.restoreGState()
}

func render(pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: scale, y: -scale)
    drawIcon(context)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("couldn't write \(url.path)") }
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    writePNG(render(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    writePNG(render(pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
writePNG(render(pixels: 1024), to: root.appendingPathComponent("docs/images/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Resources/AppIcon.icns and docs/images/icon.png")
