// Фон окна Pipa.dmg: голубой градиент в цвет иконки и стеклянная стрелка
// от Pipa к «Программам». Окно 640×400 pt (видно ~372 под заголовком),
// значки по центрам (170, 175) и (470, 175) — те же числа в make_dmg.command.
// swift draw_dmg_background.swift out.png 2  → картинка для Retina (×2).
//
// Подписи под значками Finder рисует сам: тёмные в светлой теме и белые в
// тёмной, поэтому фон в их полосе — средней яркости, читаются оба цвета.
import AppKit

let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let W: CGFloat = 640, H: CGFloat = 400
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8,
                    bytesPerRow: 0, space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: scale, y: scale)
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)   // дальше y сверху вниз

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

// Фон: сверху светлее, снизу глубже — как у иконки.
ctx.drawLinearGradient(CGGradient(colorsSpace: rgb, colors: [color(0.43, 0.62, 1.00), color(0.20, 0.38, 0.90)] as CFArray, locations: nil)!,
                       start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
// Мягкие блики, чтобы фон не был плоским.
for (x, y, r, a) in [(120.0, 40.0, 260.0, 0.22), (560.0, 360.0, 240.0, 0.14)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    ctx.drawRadialGradient(CGGradient(colorsSpace: rgb, colors: [color(1, 1, 1, a), color(1, 1, 1, 0)] as CFArray, locations: nil)!,
                           startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}

// Стрелка: контур толстой линии, залитый как стекло иконки.
let line = CGMutablePath()
line.move(to: CGPoint(x: 268, y: 175)); line.addLine(to: CGPoint(x: 372, y: 175))
line.move(to: CGPoint(x: 340, y: 147)); line.addLine(to: CGPoint(x: 372, y: 175)); line.addLine(to: CGPoint(x: 340, y: 203))
let arrow = line.copy(strokingWithWidth: 16, lineCap: .round, lineJoin: .round, miterLimit: 10).normalized(using: .winding)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: color(0.05, 0.12, 0.50, 0.35))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.addPath(arrow); ctx.clip()
ctx.drawLinearGradient(CGGradient(colorsSpace: rgb, colors: [color(0.92, 0.98, 1.00, 0.95), color(0.72, 0.84, 1.00, 0.85)] as CFArray, locations: nil)!,
                       start: CGPoint(x: 268, y: 147), end: CGPoint(x: 372, y: 203), options: [])
ctx.endTransparencyLayer()
ctx.restoreGState()
ctx.addPath(arrow); ctx.setStrokeColor(color(0.18, 0.32, 0.88, 0.55)); ctx.setLineWidth(1); ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: W, height: H)   // 72 dpi для ×1, 144 для ×2
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
