import AppKit
import QuartzCore
import LoopsCore

/// CALayer subclass that renders ruler bar numbers and section labels
/// using CoreGraphics text drawing. Positioned above the Metal layer.
///
/// Sized to the visible viewport. All drawing uses LOCAL coordinates
/// (0,0 at top-left of viewport), converting world X to local X by
/// subtracting viewportOrigin.x. The ruler is always pinned to the
/// top of the viewport.
final class TimelineTextOverlayLayer: CALayer {

    // MARK: - Data

    var pixelsPerBar: CGFloat = 120
    var totalBars: Int = 32
    var timeSignature: TimeSignature = TimeSignature()
    var sections: [TimelineCanvasView.SectionLayout] = []
    var selectedRange: ClosedRange<Int>?
    var showRulerAndSections: Bool = true

    /// The origin of the visible viewport in world coordinates.
    var viewportOrigin: CGPoint = .zero

    // MARK: - Cached State for Change Detection

    private var lastPixelsPerBar: CGFloat = 0
    private var lastTotalBars: Int = 0
    private var lastTimeSignature: TimeSignature = TimeSignature()
    private var lastSectionsFingerprint: Int = 0
    private var lastSelectedRange: ClosedRange<Int>?
    private var lastViewportOrigin: CGPoint = CGPoint(x: -1, y: -1)
    private var lastShowRulerAndSections: Bool = true

    // MARK: - Init

    override init() {
        super.init()
        isOpaque = false
        isGeometryFlipped = true
        needsDisplayOnBoundsChange = true
        contentsScale = 2.0
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? TimelineTextOverlayLayer {
            pixelsPerBar = other.pixelsPerBar
            totalBars = other.totalBars
            timeSignature = other.timeSignature
            sections = other.sections
            selectedRange = other.selectedRange
            showRulerAndSections = other.showRulerAndSections
            viewportOrigin = other.viewportOrigin
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Update

    /// Returns true if the layer needs redraw based on changed data.
    func updateIfNeeded() -> Bool {
        let sectionsFingerprint = Self.fingerprint(sections: sections)
        let changed = pixelsPerBar != lastPixelsPerBar
            || totalBars != lastTotalBars
            || timeSignature != lastTimeSignature
            || sectionsFingerprint != lastSectionsFingerprint
            || selectedRange != lastSelectedRange
            || viewportOrigin != lastViewportOrigin
            || showRulerAndSections != lastShowRulerAndSections

        if changed {
            lastPixelsPerBar = pixelsPerBar
            lastTotalBars = totalBars
            lastTimeSignature = timeSignature
            lastSectionsFingerprint = sectionsFingerprint
            lastSelectedRange = selectedRange
            lastViewportOrigin = viewportOrigin
            lastShowRulerAndSections = showRulerAndSections
            setNeedsDisplay()
        }
        return changed
    }

    // MARK: - Drawing

    override func draw(in ctx: CGContext) {
        guard showRulerAndSections else { return }

        let rulerHeight = TimelineCanvasView.rulerHeight
        let sectionLaneHeight = TimelineCanvasView.sectionLaneHeight

        // Layer geometry is flipped (origin top-left, +Y down), matching AppKit.
        // Draw ruler at y=0 and section lane directly below it.

        let vpMinX = viewportOrigin.x
        let vpMaxX = viewportOrigin.x + bounds.width

        // ── Bar number labels ──
        let step = rulerLabelStep

        let firstVisibleBar = max(1, Int(floor(vpMinX / pixelsPerBar)) + 1)
        let lastVisibleBar = min(totalBars + 1, Int(ceil(vpMaxX / pixelsPerBar)) + 2)

        guard firstVisibleBar <= lastVisibleBar else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let tickPath = CGMutablePath()

        // Ruler bottom edge (boundary between ruler and section lane)
        let rulerBottomY = rulerHeight

        for bar in firstVisibleBar...lastVisibleBar {
            let worldX = CGFloat(bar - 1) * pixelsPerBar
            let localX = worldX - vpMinX

            // Tick marks at the bottom of the ruler, extending upward
            if pixelsPerBar >= 4 {
                tickPath.move(to: CGPoint(x: localX, y: rulerBottomY))
                tickPath.addLine(to: CGPoint(x: localX, y: rulerBottomY - 6))
            }

            // Bar number label (positioned near top of ruler)
            if bar % step == 0 {
                let label = "\(bar)" as NSString
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                label.draw(at: NSPoint(x: localX + 3, y: 2), withAttributes: attrs)
                NSGraphicsContext.restoreGraphicsState()
            }

            // Beat ticks within bar
            if pixelsPerBar > 50 {
                let ppBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
                for beat in 1..<timeSignature.beatsPerBar {
                    let beatLocalX = localX + CGFloat(beat) * ppBeat
                    tickPath.move(to: CGPoint(x: beatLocalX, y: rulerBottomY))
                    tickPath.addLine(to: CGPoint(x: beatLocalX, y: rulerBottomY - 3))
                }
            }
        }

        ctx.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(tickPath)
        ctx.strokePath()

        // ── Section bands (below ruler, pinned to viewport top) ──
        let sectionTopY = rulerHeight
        for sl in sections {
            guard sl.rect.maxX >= vpMinX && sl.rect.minX <= vpMaxX else { continue }

            let localBandX = sl.rect.minX - vpMinX
            let bandRect = CGRect(
                x: localBandX, y: sectionTopY + 1,
                width: sl.rect.width, height: sectionLaneHeight - 2
            )
            let bandPath = CGPath(roundedRect: bandRect, cornerWidth: 3, cornerHeight: 3, transform: nil)

            let sectionColor = nsColorFromHex(sl.section.color)

            // Band fill
            ctx.addPath(bandPath)
            ctx.setFillColor(sectionColor.withAlphaComponent(0.4).cgColor)
            ctx.fillPath()

            // Band border
            ctx.addPath(bandPath)
            if sl.isSelected {
                ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
                ctx.setLineWidth(1.5)
            } else {
                ctx.setStrokeColor(sectionColor.withAlphaComponent(0.7).cgColor)
                ctx.setLineWidth(0.5)
            }
            ctx.strokePath()

            // Section name
            let sAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: sectionColor
            ]
            let label = sl.section.name as NSString
            let labelSize = label.size(withAttributes: sAttrs)
            let labelX = bandRect.minX + 6
            let labelY = bandRect.midY - labelSize.height / 2

            if labelX + labelSize.width <= bandRect.maxX - 4 {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                label.draw(at: NSPoint(x: labelX, y: labelY), withAttributes: sAttrs)
                NSGraphicsContext.restoreGraphicsState()
            } else if bandRect.width > 20 {
                ctx.saveGState()
                ctx.clip(to: CGRect(x: bandRect.minX + 4, y: bandRect.minY, width: bandRect.width - 8, height: bandRect.height))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                label.draw(at: NSPoint(x: labelX, y: labelY), withAttributes: sAttrs)
                NSGraphicsContext.restoreGraphicsState()
                ctx.restoreGState()
            }
        }
    }

    // MARK: - Helpers

    private var rulerLabelStep: Int {
        let minLabelWidth: CGFloat = 30
        let niceSteps = [1, 2, 4, 5, 8, 10, 16, 20, 25, 32, 50, 64, 100, 200, 500, 1000]
        for step in niceSteps {
            if CGFloat(step) * pixelsPerBar >= minLabelWidth {
                return step
            }
        }
        return 1000
    }

    private func nsColorFromHex(_ hex: String) -> NSColor {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let rgb = Int(trimmed, radix: 16) else { return .gray }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    private static func fingerprint(sections: [TimelineCanvasView.SectionLayout]) -> Int {
        var hasher = Hasher()
        hasher.combine(sections.count)
        for section in sections {
            hasher.combine(section.section.id.rawValue)
            hasher.combine(section.section.name)
            hasher.combine(section.section.startBar)
            hasher.combine(section.section.lengthBars)
            hasher.combine(section.section.color)
            hasher.combine(Int(section.rect.minX.rounded()))
            hasher.combine(Int(section.rect.width.rounded()))
            hasher.combine(section.isSelected)
        }
        return hasher.finalize()
    }
}
