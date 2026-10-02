// Resources/AppIcon.icns を作る。scripts/make-icon.sh から DefaultArt.swift と一緒にコンパイルして使う。
// Windows 版のトレイアイコンと同じ既定の絵 (待機) を、キーボードまで収まるように下地の中央に置く。
import AppKit

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let art = DefaultArt.render(.idle)
// 絵の中で線まで含めて描かれている範囲 (左上原点): 横はキーボード 136〜664、縦は耳の先 56〜キーボードの下 479
let contentWidth: CGFloat = 528
let contentCenter = NSPoint(x: 400, y: 500 - (56 + 479) / 2) // 左下原点に直した中心

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // macOS のアイコンの枠 (1024 中 824 の角丸四角) に合わせた下地
    let s = CGFloat(pixels) / 1024
    let plate = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: plate, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(srgbRed: 1, green: 0.98, blue: 0.94, alpha: 1),
               ending: NSColor(srgbRed: 1, green: 0.91, blue: 0.80, alpha: 1))!.draw(in: path, angle: -90)

    let k = (plate.width - 80 * s) / contentWidth
    let dest = NSRect(x: plate.midX - contentCenter.x * k, y: plate.midY - contentCenter.y * k,
                      width: DefaultArt.size.width * k, height: DefaultArt.size.height * k)
    art.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
