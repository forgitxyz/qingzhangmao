import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// 纯 CoreGraphics 绘制，无需 WindowServer，可在无界面环境生成
let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

// 透明背景
ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

// macOS 图标留白 + 圆角方形
let inset: CGFloat = 84
let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let radius: CGFloat = 190
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(path)
ctx.clip()

// 品牌渐变（青 → 蓝）
let colors = [
    CGColor(srgbRed: 0.176, green: 0.831, blue: 0.749, alpha: 1),
    CGColor(srgbRed: 0.306, green: 0.631, blue: 1.000, alpha: 1)
] as CFArray
let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY),
                       options: [])

// 右上角柔光
let glow = CGGradient(colorsSpace: cs,
                      colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28),
                               CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow,
                       startCenter: CGPoint(x: rect.maxX - 150, y: rect.maxY - 160), startRadius: 0,
                       endCenter: CGPoint(x: rect.maxX - 150, y: rect.maxY - 160), endRadius: 460,
                       options: [])
ctx.restoreGState()

// 中央 ¥ 符号
let font = CTFontCreateUIFontForLanguage(.system, 470, nil)!
let attrs: [CFString: Any] = [
    kCTFontAttributeName: font,
    kCTForegroundColorAttributeName: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
]
let attrStr = CFAttributedStringCreate(nil, "¥" as CFString, attrs as CFDictionary)!
let line = CTLineCreateWithAttributedString(attrStr)
let bounds = CTLineGetImageBounds(line, ctx)
let tx = (S - bounds.width) / 2 - bounds.minX
let ty = (S - bounds.height) / 2 - bounds.minY + 18
ctx.textPosition = CGPoint(x: tx, y: ty)
CTLineDraw(line, ctx)

guard let image = ctx.makeImage() else { exit(1) }
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon1024.png")
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("icon written: \(out.path)")
