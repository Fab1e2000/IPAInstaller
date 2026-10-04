// 绘制 App 图标（1024×1024）：蓝色圆角底板上一台手机，屏幕里是向下的安装箭头，右下角是签名印章。
// 用法：swift scripts/draw-icon.swift <输出.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func withShadow(_ blur: CGFloat, _ offsetY: CGFloat, _ shadowColor: NSColor, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: -offsetY)
    shadow.shadowColor = shadowColor
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 底板：macOS 图标网格，824 见方，圆角 185。
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = roundedRect(plate, 185)
withShadow(28, 12, color(0x000000, 0.3)) {
    color(0x3A3FD8).setFill()
    platePath.fill()
}
NSGradient(colors: [color(0x6E8BFF), color(0x4A4FE4), color(0x3B2FB8)], atLocations: [0, 0.55, 1],
           colorSpace: .sRGB)!.draw(in: platePath, angle: -90)
// 顶部一层柔光
NSGraphicsContext.saveGraphicsState()
platePath.addClip()
NSGradient(colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)])!
    .draw(in: CGRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// 手机
let phone = CGRect(x: 322, y: 210, width: 360, height: 604)
withShadow(36, 18, color(0x10104A, 0.45)) {
    color(0xFFFFFF).setFill()
    roundedRect(phone, 78).fill()
}
NSGradient(colors: [color(0xFFFFFF), color(0xE9ECFB)])!.draw(in: roundedRect(phone, 78), angle: -90)
// 屏幕
let screen = phone.insetBy(dx: 22, dy: 22)
NSGradient(colors: [color(0xEEF1FF), color(0xD9DFFF)])!.draw(in: roundedRect(screen, 58), angle: -90)
// 灵动岛
color(0x1C1C3A).setFill()
roundedRect(CGRect(x: 462, y: 742, width: 80, height: 24), 12).fill()

// 安装箭头：竖杆 + 箭头 + 底部托盘
let arrowColor = NSGradient(colors: [color(0x6E8BFF), color(0x3B2FB8)])!
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 472, y: 660))
arrow.line(to: CGPoint(x: 532, y: 660))
arrow.line(to: CGPoint(x: 532, y: 500))
arrow.line(to: CGPoint(x: 590, y: 500))
arrow.line(to: CGPoint(x: 502, y: 400))
arrow.line(to: CGPoint(x: 414, y: 500))
arrow.line(to: CGPoint(x: 472, y: 500))
arrow.close()
arrow.lineJoinStyle = .round
arrowColor.draw(in: arrow, angle: -90)
let tray = roundedRect(CGRect(x: 412, y: 330, width: 180, height: 30), 15)
arrowColor.draw(in: tray, angle: -90)

// 签名印章
let sealCenter = CGPoint(x: 700, y: 300)
let sealRadius: CGFloat = 118
let seal = NSBezierPath(ovalIn: CGRect(x: sealCenter.x - sealRadius, y: sealCenter.y - sealRadius,
                                       width: sealRadius * 2, height: sealRadius * 2))
withShadow(24, 10, color(0x10104A, 0.4)) {
    color(0xFFFFFF).setFill()
    seal.fill()
}
let inner = NSBezierPath(ovalIn: CGRect(x: sealCenter.x - sealRadius + 14, y: sealCenter.y - sealRadius + 14,
                                        width: (sealRadius - 14) * 2, height: (sealRadius - 14) * 2))
NSGradient(colors: [color(0xFFC94A), color(0xFF8A00)])!.draw(in: inner, angle: -90)
let check = NSBezierPath()
check.move(to: CGPoint(x: sealCenter.x - 50, y: sealCenter.y + 2))
check.line(to: CGPoint(x: sealCenter.x - 14, y: sealCenter.y - 36))
check.line(to: CGPoint(x: sealCenter.x + 52, y: sealCenter.y + 40))
check.lineWidth = 30
check.lineCapStyle = .round
check.lineJoinStyle = .round
color(0xFFFFFF).setStroke()
check.stroke()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("已生成 \(output)")
