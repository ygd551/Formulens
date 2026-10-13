// 生成 1024×1024 应用图标：swift make_icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS 图标网格：内容区约 824px，圆角约 185px
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.40, green: 0.36, blue: 0.98, alpha: 1),
           ending: NSColor(red: 0.20, green: 0.16, blue: 0.62, alpha: 1))!.draw(in: path, angle: -90)

// ∑ 用线条自行绘制，不使用系统字体字形（字体许可不覆盖图标用途，也便于以后用于其他平台）
NSColor.white.setStroke()
let sigma = NSBezierPath()
sigma.lineWidth = 46
sigma.lineJoinStyle = .miter
sigma.lineCapStyle = .butt
sigma.move(to: NSPoint(x: 676, y: 664))   // 上横右端（向下的小折角）
sigma.line(to: NSPoint(x: 676, y: 700))
sigma.line(to: NSPoint(x: 356, y: 700))   // 上横
sigma.line(to: NSPoint(x: 540, y: 512))   // 斜向中点
sigma.line(to: NSPoint(x: 356, y: 324))   // 斜回
sigma.line(to: NSPoint(x: 676, y: 324))   // 下横
sigma.line(to: NSPoint(x: 676, y: 360))   // 下横右端（向上的小折角）
sigma.stroke()

// 右下角的截图框标记
NSColor.white.withAlphaComponent(0.85).setStroke()
let corner = NSBezierPath()
corner.lineWidth = 34
corner.lineCapStyle = .round
corner.move(to: NSPoint(x: 700, y: 210)); corner.line(to: NSPoint(x: 800, y: 210)); corner.line(to: NSPoint(x: 800, y: 310))
corner.move(to: NSPoint(x: 224, y: 714)); corner.line(to: NSPoint(x: 224, y: 814)); corner.line(to: NSPoint(x: 324, y: 814))
corner.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
