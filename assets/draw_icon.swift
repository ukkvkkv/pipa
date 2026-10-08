// Иконка приложения в стиле «Видеоповтора iPhone»: голубой squircle
// и одна большая стеклянная стрелка загрузки.
// Чистый вектор (CoreGraphics), так края чёткие на любом размере.
import AppKit

let S: CGFloat = 1024, content: CGFloat = 824
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: Int(S) * 4,
                    space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Дальше координаты сверху вниз, как в макете.
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func gradient(_ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: nil)!,
                           start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
func stroke(_ path: CGPath, _ c: CGColor, _ w: CGFloat) {
    ctx.addPath(path); ctx.setStrokeColor(c); ctx.setLineWidth(w); ctx.strokePath()
}
func shadow(_ path: CGPath, _ c: CGColor, blur: CGFloat, dy: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -dy), blur: blur, color: c)  // смещение тени — в системе CG (y вверх)
    ctx.addPath(path); ctx.setFillColor(color(0, 0, 0, 1)); ctx.fillPath()
    ctx.restoreGState()
}

// Фон.
let bg = CGRect(x: (S - content) / 2, y: (S - content) / 2, width: content, height: content)
let squircle = CGPath(roundedRect: bg, cornerWidth: content * 0.225, cornerHeight: content * 0.225, transform: nil)
gradient(squircle, [color(0.45, 0.66, 1.00), color(0.27, 0.50, 0.98)], from: CGPoint(x: 0, y: bg.minY), to: CGPoint(x: 0, y: bg.maxY))
ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
stroke(squircle, color(0.80, 0.95, 1.00, 0.35), 7)   // светлая кромка внутри
ctx.restoreGState()

// Стрелка: контур толстой линии, залитый как стекло.
let cx: CGFloat = 512
let line = CGMutablePath()
line.move(to: CGPoint(x: cx, y: 268)); line.addLine(to: CGPoint(x: cx, y: 724))
line.move(to: CGPoint(x: cx - 196, y: 528)); line.addLine(to: CGPoint(x: cx, y: 724)); line.addLine(to: CGPoint(x: cx + 196, y: 528))
let arrow = line.copy(strokingWithWidth: 112, lineCap: .round, lineJoin: .round, miterLimit: 10)
    .normalized(using: .winding)

ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 50, color: color(0.05, 0.12, 0.50, 0.40))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
gradient(arrow, [color(0.90, 0.98, 1.00, 0.92), color(0.66, 0.80, 1.00, 0.80)],
         from: CGPoint(x: cx + 200, y: 260), to: CGPoint(x: cx - 200, y: 760))
ctx.endTransparencyLayer()
ctx.restoreGState()
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(arrow); ctx.clip()
stroke(arrow, color(1, 1, 1, 0.75), 10)               // блик по внутренней кромке
ctx.restoreGState()
stroke(arrow, color(0.18, 0.32, 0.88, 0.70), 3)        // тонкий тёмный контур

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
