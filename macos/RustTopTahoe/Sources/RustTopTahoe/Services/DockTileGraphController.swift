import AppKit
import Foundation

@MainActor
final class DockTileGraphController {
    static let shared = DockTileGraphController()

    private var hasCustomTile = false

    private init() {}

    func update(
        samples: [MetricSample],
        isEnabled: Bool,
        isLive: Bool,
        activeAlertCount: Int
    ) {
        guard isEnabled else {
            clear()
            return
        }

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: DockTileGraphRenderer.tileSize))
        imageView.image = DockTileGraphRenderer.image(
            samples: samples,
            isLive: isLive,
            activeAlertCount: activeAlertCount
        )
        imageView.imageScaling = .scaleAxesIndependently

        NSApplication.shared.dockTile.contentView = imageView
        NSApplication.shared.dockTile.badgeLabel = activeAlertCount > 0 ? String(min(activeAlertCount, 99)) : nil
        NSApplication.shared.dockTile.display()
        hasCustomTile = true
    }

    func clear() {
        guard hasCustomTile || NSApplication.shared.dockTile.badgeLabel != nil else { return }

        NSApplication.shared.dockTile.contentView = nil
        NSApplication.shared.dockTile.badgeLabel = nil
        NSApplication.shared.dockTile.display()
        hasCustomTile = false
    }
}

struct DockTileGraphRenderer {
    static let tileSize = NSSize(width: 128, height: 128)

    static func image(
        samples: [MetricSample],
        isLive: Bool,
        activeAlertCount: Int
    ) -> NSImage {
        let latest = samples.last
        let cpu = clampedPercent(latest?.cpu ?? 0)
        let memory = clampedPercent(latest?.memory ?? 0)

        return NSImage(size: tileSize, flipped: false) { rect in
            drawBackground(in: rect, activeAlertCount: activeAlertCount)
            drawHeader(in: rect, isLive: isLive)
            drawValue(cpu, in: rect)
            drawSparkline(
                samples.map { clampedPercent($0.cpu) },
                in: NSRect(x: 14, y: 18, width: 100, height: 42),
                color: NSColor(red: 0.30, green: 0.62, blue: 1.00, alpha: 0.92)
            )
            drawSparkline(
                samples.map { clampedPercent($0.memory) },
                in: NSRect(x: 14, y: 18, width: 100, height: 42),
                color: NSColor(red: 0.62, green: 0.48, blue: 1.00, alpha: 0.82)
            )
            drawFooter(memory, in: rect)
            return true
        }
    }

    private static func drawBackground(in rect: NSRect, activeAlertCount: Int) {
        let outerRect = rect.insetBy(dx: 5, dy: 5)
        let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: 26, yRadius: 26)
        let gradient = NSGradient(
            starting: NSColor(red: 0.08, green: 0.11, blue: 0.16, alpha: 1),
            ending: NSColor(red: 0.19, green: 0.22, blue: 0.32, alpha: 1)
        )
        gradient?.draw(in: outerPath, angle: -34)

        NSColor.white.withAlphaComponent(0.12).setStroke()
        outerPath.lineWidth = 1.5
        outerPath.stroke()

        let glassRect = NSRect(x: 14, y: 64, width: 100, height: 42)
        let glassPath = NSBezierPath(roundedRect: glassRect, xRadius: 18, yRadius: 18)
        NSColor.white.withAlphaComponent(0.12).setFill()
        glassPath.fill()

        if activeAlertCount > 0 {
            NSColor(red: 1.00, green: 0.36, blue: 0.47, alpha: 0.78).setStroke()
            outerPath.lineWidth = 4
            outerPath.stroke()
        }
    }

    private static func drawHeader(in rect: NSRect, isLive: Bool) {
        drawText(
            "RT",
            in: NSRect(x: 18, y: rect.maxY - 36, width: 42, height: 18),
            font: .systemFont(ofSize: 14, weight: .bold),
            color: .white.withAlphaComponent(0.92),
            alignment: .left
        )

        let dotRect = NSRect(x: rect.maxX - 32, y: rect.maxY - 30, width: 10, height: 10)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        (isLive
            ? NSColor(red: 0.21, green: 0.86, blue: 0.62, alpha: 0.95)
            : NSColor(red: 1.00, green: 0.72, blue: 0.27, alpha: 0.95)
        ).setFill()
        dotPath.fill()
    }

    private static func drawValue(_ cpu: Double, in rect: NSRect) {
        drawText(
            "\(Int(cpu.rounded()))%",
            in: NSRect(x: 15, y: 68, width: 98, height: 32),
            font: .monospacedDigitSystemFont(ofSize: 30, weight: .bold),
            color: .white,
            alignment: .center
        )
    }

    private static func drawFooter(_ memory: Double, in rect: NSRect) {
        drawText(
            "MEM \(Int(memory.rounded()))%",
            in: NSRect(x: 16, y: 8, width: 96, height: 14),
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            color: .white.withAlphaComponent(0.72),
            alignment: .center
        )
    }

    private static func drawSparkline(_ values: [Double], in rect: NSRect, color: NSColor) {
        let normalizedValues = values.isEmpty ? [0] : values
        let path = NSBezierPath()

        for (index, value) in normalizedValues.enumerated() {
            let divisor = max(normalizedValues.count - 1, 1)
            let x = rect.minX + (CGFloat(index) / CGFloat(divisor)) * rect.width
            let y = rect.minY + CGFloat(clampedPercent(value) / 100) * rect.height
            let point = NSPoint(x: x, y: y)

            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }

        color.setStroke()
        path.lineWidth = 2.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping

        NSString(string: text).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func clampedPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }
}
