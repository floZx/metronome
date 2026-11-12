// Renders the app icon (1024×1024 PNG). Usage: swift scripts/make_icon.swift <out.png>
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

// Background
let bg = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.13, green: 0.12, blue: 0.18, alpha: 1),
    CGColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
let glow = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 0.35),
    CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 560), endRadius: 470, options: [])

let center = CGPoint(x: 512, y: 512)
// Track ring
ctx.setLineWidth(46)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08))
ctx.addArc(center: center, radius: 330, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()

// Gradient arc
ctx.saveGState()
ctx.setLineWidth(46)
ctx.setLineCap(.round)
ctx.addArc(center: center, radius: 330, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 1.25, clockwise: true)
ctx.replacePathWithStrokedPath()
ctx.clip()
let arc = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 0.72, blue: 0.25, alpha: 1),
    CGColor(red: 1, green: 0.38, blue: 0.14, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(arc, start: CGPoint(x: 200, y: 900), end: CGPoint(x: 850, y: 150), options: [])
ctx.restoreGState()

// Ticks
for i in 0..<60 {
    let a = Double(i) / 60 * 2 * .pi
    let major = i % 5 == 0
    let r1 = 430.0, r2 = major ? 395.0 : 412.0
    ctx.setLineWidth(major ? 9 : 5)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: major ? 0.38 : 0.16))
    ctx.move(to: CGPoint(x: 512 + cos(a) * r1, y: 512 + sin(a) * r1))
    ctx.addLine(to: CGPoint(x: 512 + cos(a) * r2, y: 512 + sin(a) * r2))
    ctx.strokePath()
}

// Pendulum
ctx.saveGState()
ctx.translateBy(x: 512, y: 300)
ctx.rotate(by: -0.32)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.move(to: .zero)
ctx.addLine(to: CGPoint(x: 0, y: 420))
ctx.strokePath()
ctx.setFillColor(CGColor(red: 1, green: 0.62, blue: 0.2, alpha: 1))
let weight = CGRect(x: -52, y: 230, width: 104, height: 72)
ctx.addPath(CGPath(roundedRect: weight, cornerWidth: 22, cornerHeight: 22, transform: nil))
ctx.fillPath()
ctx.restoreGState()
// Pivot
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fillEllipse(in: CGRect(x: 512 - 34, y: 300 - 34, width: 68, height: 68))

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
