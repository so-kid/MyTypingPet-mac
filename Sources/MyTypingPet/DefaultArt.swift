import AppKit

enum Pose { case idle, left, right }

/// 画像未設定のときに使う、キーボードを叩くネコの絵 (800x500)。Windows 版と同じ絵。
enum DefaultArt {
    static let size = NSSize(width: 800, height: 500)

    private static let fur = rgb(0xF4, 0xA2, 0x61)
    private static let ink = rgb(0x3D, 0x2C, 0x2E)
    private static let cheek = rgb(0xF2, 0x84, 0x82)
    private static let board = rgb(0x8D, 0x99, 0xAE)
    private static let key = rgb(0xED, 0xF2, 0xF4)
    private static let outline: CGFloat = 8

    static func render(_ pose: Pose) -> NSImage {
        // flipped にして Windows 版と同じ座標 (左上原点) で描く。解像度に合わせて描き直される
        NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)

            // 耳
            fillStroke(ctx, triangle(CGPoint(x: 255, y: 175), CGPoint(x: 275, y: 60), CGPoint(x: 355, y: 130)), fill: fur)
            fillStroke(ctx, triangle(CGPoint(x: 545, y: 175), CGPoint(x: 525, y: 60), CGPoint(x: 445, y: 130)), fill: fur)

            // 体
            fillStroke(ctx, ellipse(400, 275, 195, 165), fill: fur)

            // 顔。叩いているときは目を閉じる
            if pose == .idle {
                fill(ctx, ellipse(330, 245, 16, 18), ink)
                fill(ctx, ellipse(470, 245, 16, 18), ink)
            } else {
                stroke(ctx, quads([(312, 250), (330, 232), (348, 250)]), width: 8)
                stroke(ctx, quads([(452, 250), (470, 232), (488, 250)]), width: 8)
            }
            fill(ctx, ellipse(300, 290, 22, 13), cheek)
            fill(ctx, ellipse(500, 290, 22, 13), cheek)
            stroke(ctx, quads([(375, 280), (387, 298), (400, 282), (413, 298), (425, 280)]), width: 6)

            // キーボード
            fillStroke(ctx, CGPath(roundedRect: CGRect(x: 140, y: 385, width: 520, height: 90),
                                   cornerWidth: 18, cornerHeight: 18, transform: nil), fill: board)
            for row in 0..<2 {
                for col in 0..<10 {
                    let rect = CGRect(x: 168 + col * 47, y: 400 + row * 33, width: 38, height: 25)
                    fill(ctx, CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil), key)
                }
            }

            // 手 (画面の左右で判定)
            drawPaw(ctx, shoulder: CGPoint(x: 285, y: 340),
                    paw: pose == .left ? CGPoint(x: 215, y: 235) : CGPoint(x: 275, y: 405))
            drawPaw(ctx, shoulder: CGPoint(x: 515, y: 340),
                    paw: pose == .right ? CGPoint(x: 585, y: 235) : CGPoint(x: 525, y: 405))
            return true
        }
    }

    private static func drawPaw(_ ctx: CGContext, shoulder: CGPoint, paw: CGPoint) {
        // 輪郭 → 毛色の順に太線を重ねて腕にする
        let arm = CGMutablePath()
        arm.move(to: shoulder)
        arm.addLine(to: paw)
        stroke(ctx, arm, width: 62)
        stroke(ctx, arm, width: 46, color: fur)
        fillStroke(ctx, ellipse(paw.x, paw.y, 36, 30), fill: fur)
        fill(ctx, ellipse(paw.x, paw.y + 4, 11, 9), cheek)
    }

    private static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    private static func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [a, b, c])
        path.closeSubpath()
        return path
    }

    /// 始点に続けて (制御点, 終点) を並べた 2 次ベジェ曲線。
    private static func quads(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: points[0].0, y: points[0].1))
        for i in stride(from: 1, to: points.count - 1, by: 2) {
            path.addQuadCurve(to: CGPoint(x: points[i + 1].0, y: points[i + 1].1),
                              control: CGPoint(x: points[i].0, y: points[i].1))
        }
        return path
    }

    private static func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    private static func stroke(_ ctx: CGContext, _ path: CGPath, width: CGFloat, color: CGColor = ink) {
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    private static func fillStroke(_ ctx: CGContext, _ path: CGPath, fill color: CGColor) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(outline)
        ctx.drawPath(using: .fillStroke)
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}
