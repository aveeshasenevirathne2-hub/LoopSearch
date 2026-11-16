import AppKit
import CoreGraphics
import CoreImage
import QuartzCore
import WebKit

@MainActor
final class OverlayWindowController {
    private var window: OverlayNSWindow?
    private var rootView: OverlayCanvasView?
    private var onClose: (() -> Void)?
    private var isClosing = false

    var isOpen: Bool { window != nil }

    func show(
        screenshot: CGImage,
        screen: NSScreen,
        selectionMode: SelectionMode,
        initialSelection: (image: CGImage, rect: CGRect)? = nil,
        onShowToast: @escaping (String) -> Void,
        onOpenSettings: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        immediateClose()
        self.onClose = onClose
        self.isClosing = false

        let window = OverlayNSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.onEscape = { [weak self] in
            self?.close()
        }
        window.onSettings = { [weak self] in
            self?.close()
            onOpenSettings()
        }

        let topSafe = max(38, screen.frame.maxY - screen.visibleFrame.maxY + 12)
        let bottomSafe = max(24, screen.visibleFrame.minY - screen.frame.minY + 16)
        let leftSafe = max(22, screen.visibleFrame.minX - screen.frame.minX + 18)
        let rightSafe = max(22, screen.frame.maxX - screen.visibleFrame.maxX + 18)
        let safeInsets = NSEdgeInsets(top: topSafe, left: leftSafe, bottom: bottomSafe, right: rightSafe)

        let canvas = OverlayCanvasView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screenshot: screenshot,
            safeInsets: safeInsets,
            selectionMode: selectionMode,
            initialSelection: initialSelection,
            onShowToast: onShowToast,
            onOpenSettings: { [weak self] in
                self?.close()
                onOpenSettings()
            },
            onDismiss: { [weak self] in
                self?.close()
            }
        )
        window.onModeShortcut = { [weak canvas] mode in
            canvas?.handleKeyboardModeSwitch(mode)
        }
        window.onCopyShortcut = { [weak canvas] in
            canvas?.handleKeyboardCopy()
        }
        window.onPinShortcut = { [weak canvas] in
            canvas?.handleKeyboardPin()
        }
        window.contentView = canvas
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        self.rootView = canvas
    }

    func close() {
        guard !isClosing, let window else { return }
        isClosing = true

        rootView?.playExitAnimation { [weak self] in
            window.orderOut(nil)
            self?.window = nil
            self?.rootView = nil
            self?.isClosing = false
            self?.onClose?()
            self?.onClose = nil
        }
    }

    private func immediateClose() {
        rootView?.stopDisplayLink()
        window?.orderOut(nil)
        window = nil
        rootView = nil
        isClosing = false
        onClose?()
        onClose = nil
    }
}

private final class OverlayNSWindow: NSWindow {
    var onEscape: (() -> Void)?
    var onSettings: (() -> Void)?
    var onModeShortcut: ((SelectionMode) -> Void)?
    var onCopyShortcut: (() -> Void)?
    var onPinShortcut: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 {
                onEscape?()
                return
            }
            if event.keyCode == 43 && event.modifierFlags.contains(.command) {
                onSettings?()
                return
            }
            let isEditingText = (firstResponder is NSTextView)
            if !isEditingText {
                if event.keyCode == 8 && event.modifierFlags.contains(.command) { // Cmd + C
                    onCopyShortcut?()
                    return
                }
                if event.keyCode == 35 && event.modifierFlags.contains(.command) { // Cmd + P
                    onPinShortcut?()
                    return
                }
                if !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
                    switch event.keyCode {
                    case 18:
                        onModeShortcut?(.rectangle)
                        return
                    case 19:
                        onModeShortcut?(.circle)
                        return
                    case 20:
                        onModeShortcut?(.tap)
                        return
                    case 21:
                        onModeShortcut?(.textOnly)
                        return
                    default:
                        break
                    }
                }
            }
        }
        super.sendEvent(event)
    }
}

// MARK: - Continuous Live Color Palette (Signature Loop Aura + Full Spectrum)

private enum LuminousPalette {
    static let signatureStops: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.06, 0.30, 0.92), // Deep Cobalt Blue
        (0.10, 0.56, 1.00), // Horizon Electric Blue
        (0.18, 0.78, 1.00), // Sky Azure
        (0.56, 0.92, 1.00), // Luminous Ice Cyan
        (0.14, 0.42, 0.98)  // Sapphire Indigo
    ]

    static let spectrumStops: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.26, 0.55, 1.00), // Cobalt Blue
        (0.58, 0.40, 0.98), // Iris Violet
        (0.95, 0.34, 0.54), // Coral Rose
        (0.98, 0.72, 0.22), // Warm Amber
        (0.20, 0.82, 0.62)  // Aqua Mint
    ]

    static var isSignaturePalette: Bool {
        AppSettings.cachedIsSignaturePalette
    }

    static var activeStops: [(r: CGFloat, g: CGFloat, b: CGFloat)] {
        isSignaturePalette ? signatureStops : spectrumStops
    }

    static func gradientColors(phase: Double, alpha: CGFloat = 1.0) -> [CGColor] {
        let stops = activeStops
        func sample(_ offset: Double) -> CGColor {
            let count = Double(stops.count)
            let wrapped = (phase + offset).truncatingRemainder(dividingBy: count)
            let pos = wrapped < 0 ? wrapped + count : wrapped
            let i0 = Int(pos) % stops.count
            let i1 = (i0 + 1) % stops.count
            let frac = CGFloat(pos - floor(pos))
            let s = frac * frac * (3 - 2 * frac)
            let c0 = stops[i0]
            let c1 = stops[i1]
            let r = c0.r + (c1.r - c0.r) * s
            let g = c0.g + (c1.g - c0.g) * s
            let b = c0.b + (c1.b - c0.b) * s
            return NSColor(red: r, green: g, blue: b, alpha: alpha).cgColor
        }
        return [sample(0.0), sample(1.3), sample(2.6)]
    }

    static let signatureLoopStops: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.06, 0.30, 0.92), // Deep Cobalt Blue
        (0.10, 0.56, 1.00), // Horizon Electric Blue
        (0.20, 0.80, 1.00), // Sky Azure
        (0.76, 0.96, 1.00), // Incandescent Ice-White Peak
        (0.30, 0.86, 1.00), // Luminous Cyan
        (0.12, 0.44, 0.98)  // Sapphire Indigo
    ]

    static let fullRGBStops: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (1.00, 0.24, 0.42), // Crimson Rose
        (1.00, 0.68, 0.14), // Vivid Amber Gold
        (0.18, 0.94, 0.58), // Emerald Mint
        (0.16, 0.78, 1.00), // Electric Cyan-Azure
        (0.56, 0.36, 1.00), // Iris Violet
        (1.00, 0.28, 0.78)  // Neon Magenta
    ]

    static func fullSpectrumLoopColors(phase: Double, alpha: CGFloat = 1.0) -> [CGColor] {
        let stops = isSignaturePalette ? signatureLoopStops : fullRGBStops
        func sampleRGB(_ offset: Double) -> CGColor {
            let count = Double(stops.count)
            let wrapped = (phase + offset).truncatingRemainder(dividingBy: count)
            let pos = wrapped < 0 ? wrapped + count : wrapped
            let i0 = Int(pos) % stops.count
            let i1 = (i0 + 1) % stops.count
            let frac = CGFloat(pos - floor(pos))
            let s = frac * frac * (3 - 2 * frac)
            let c0 = stops[i0]
            let c1 = stops[i1]
            return NSColor(
                red: c0.r + (c1.r - c0.r) * s,
                green: c0.g + (c1.g - c0.g) * s,
                blue: c0.b + (c1.b - c0.b) * s,
                alpha: alpha
            ).cgColor
        }
        let ring = (0..<6).map { sampleRGB(Double($0)) }
        return ring + [ring[0]]
    }
}

// MARK: - Optical Retina Gaussian-Bloom & Edge Glow Helpers

private func applyContentsScaleRecursive(_ scale: CGFloat, to layer: CALayer) {
    layer.contentsScale = scale
    if let mask = layer.mask {
        applyContentsScaleRecursive(scale, to: mask)
    }
    layer.sublayers?.forEach { applyContentsScaleRecursive(scale, to: $0) }
}

/// Non-interactive Retina GPU host for 12-ring Gaussian-falloff optical bloom layers.
@MainActor
private final class LuminousGlowHostView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerUsesCoreImageFilters = false
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class GlowingRoundedBorderLayer: CALayer {
    private struct Ring {
        let blurContainer: CALayer?
        let gradient: CAGradientLayer
        let mask: CAShapeLayer
    }

    private var rings: [Ring] = []
    private var innerEdgeClipLayer: CALayer?
    private var innerEdgeClipMask: CAShapeLayer?
    private var innerEdgeFillLayer: CAGradientLayer?
    private var innerEdgeBlurContainer: CALayer?
    private var innerEdgeStrokeGradient: CAGradientLayer?
    private var innerEdgeStrokeMask: CAShapeLayer?

    private let fullSpectrumConic: Bool
    private let useCoreImageBlur: Bool
    private var currentGlowPadding: CGFloat = 0

    convenience init(
        wideLine: CGFloat,
        midLine: CGFloat,
        coreLine: CGFloat,
        coreOpacity: Float = 0.56,
        fullSpectrumConic: Bool = false,
        interiorAmbientOpacity: Float = 0.0,
        useCoreImageBlur: Bool = false
    ) {
        // 12-Ring Ultra-Dense Continuous Gaussian-Falloff Stack:
        // Radial spacing between consecutive rings is < 1.7pt on Retina displays for 100% band-free optical bloom,
        // while preserving full neon vibrancy over bright images and running at 120Hz with zero offscreen CIFilter passes.
        let steps = fullSpectrumConic ? 12 : 9
        var specs: [(CGFloat, CGFloat, Float)] = []
        let safeWide = max(wideLine, coreLine + 0.5)
        let ratio = coreLine / safeWide
        let curveTightness: CGFloat = fullSpectrumConic ? 2.35 : 2.85
        for i in 0..<steps {
            let p = CGFloat(i) / CGFloat(steps - 1)
            let width = safeWide * pow(ratio, p)
            let falloff = exp(-pow(1.0 - p, 2.0) * curveTightness)
            specs.append((width, 0.0, Float(falloff) * coreOpacity))
        }
        self.init(
            opticalSpecs: specs,
            fullSpectrumConic: fullSpectrumConic,
            interiorAmbientOpacity: interiorAmbientOpacity,
            useCoreImageBlur: false
        )
    }

    init(
        opticalSpecs: [(stroke: CGFloat, blur: CGFloat, opacity: Float)],
        fullSpectrumConic: Bool = false,
        interiorAmbientOpacity: Float = 0.0,
        useCoreImageBlur: Bool = false
    ) {
        self.fullSpectrumConic = fullSpectrumConic
        self.useCoreImageBlur = useCoreImageBlur
        super.init()

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        contentsScale = scale
        masksToBounds = false

        if interiorAmbientOpacity > 0 {
            let clip = CALayer()
            clip.masksToBounds = false
            clip.isHidden = true
            let clipMask = CAShapeLayer()
            clipMask.fillColor = NSColor.white.cgColor
            clipMask.strokeColor = nil
            clip.mask = clipMask

            // Subtle translucent atmospheric interior tint (keeps center crisp)
            let fill = Self.makeGradient(fullSpectrum: fullSpectrumConic)
            fill.opacity = interiorAmbientOpacity * 0.30
            clip.addSublayer(fill)

            // Soft blurred inner-edge perimeter glow bleeding gently inward from all sides
            let edgeBlur = CALayer()
            edgeBlur.masksToBounds = false
            if useCoreImageBlur, let blurFilter = Self.makeGaussianBlur(radius: 15.0) {
                edgeBlur.filters = [blurFilter]
            }
            let edgeGrad = Self.makeGradient(fullSpectrum: fullSpectrumConic)
            edgeGrad.opacity = interiorAmbientOpacity * 2.2
            let edgeMask = CAShapeLayer()
            edgeMask.fillColor = nil
            edgeMask.strokeColor = NSColor.white.cgColor
            edgeMask.lineWidth = 14.0
            edgeMask.lineJoin = .round
            edgeMask.lineCap = .round
            edgeGrad.mask = edgeMask
            edgeBlur.addSublayer(edgeGrad)
            clip.addSublayer(edgeBlur)

            addSublayer(clip)
            innerEdgeClipLayer = clip
            innerEdgeClipMask = clipMask
            innerEdgeFillLayer = fill
            innerEdgeBlurContainer = edgeBlur
            innerEdgeStrokeGradient = edgeGrad
            innerEdgeStrokeMask = edgeMask
        }

        for (lw, blurRadius, op) in opticalSpecs {
            let gradient = Self.makeGradient(fullSpectrum: fullSpectrumConic)
            gradient.opacity = op

            let mask = CAShapeLayer()
            mask.fillColor = nil
            mask.strokeColor = NSColor.white.cgColor
            mask.lineWidth = lw
            mask.lineJoin = .round
            mask.lineCap = .round
            gradient.mask = mask

            let blurContainer: CALayer?
            if useCoreImageBlur, blurRadius > 0, let filter = Self.makeGaussianBlur(radius: blurRadius) {
                let container = CALayer()
                container.masksToBounds = false
                container.filters = [filter]
                container.addSublayer(gradient)
                addSublayer(container)
                blurContainer = container
            } else {
                addSublayer(gradient)
                blurContainer = nil
            }

            rings.append(Ring(blurContainer: blurContainer, gradient: gradient, mask: mask))
        }

        applyContentsScaleRecursive(scale, to: self)
    }

    override init(layer: Any) {
        self.fullSpectrumConic = false
        self.useCoreImageBlur = false
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let conicLocations: [NSNumber] = [0.0, 0.167, 0.333, 0.5, 0.667, 0.833, 1.0]

    private static func makeGradient(fullSpectrum: Bool) -> CAGradientLayer {
        let grad = CAGradientLayer()
        grad.type = fullSpectrum ? .conic : .axial
        grad.colors = fullSpectrum
            ? LuminousPalette.fullSpectrumLoopColors(phase: 0)
            : LuminousPalette.gradientColors(phase: 0)
        if fullSpectrum {
            grad.locations = conicLocations
        }
        grad.startPoint = fullSpectrum ? CGPoint(x: 0.5, y: 0.5) : CGPoint(x: 0.0, y: 0.0)
        grad.endPoint = fullSpectrum ? CGPoint(x: 1.0, y: 0.5) : CGPoint(x: 1.0, y: 1.0)
        return grad
    }

    private static func makeGaussianBlur(radius: CGFloat) -> CIFilter? {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setDefaults()
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.name = "gaussianBlur_\(Int(radius))"
        return filter
    }

    func updatePath(roundedRect rect: CGRect, cornerRadius: CGFloat, glowPadding: CGFloat = 84) {
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        updatePath(
            path,
            tightBounds: rect,
            glowPadding: glowPadding,
            showInteriorAmbient: innerEdgeClipLayer != nil
        )
    }

    func updatePath(
        _ path: CGPath,
        tightBounds: CGRect,
        glowPadding: CGFloat = 84,
        showInteriorAmbient: Bool = false
    ) {
        currentGlowPadding = glowPadding
        let validBounds = (tightBounds.isNull || tightBounds.isEmpty) ? bounds : tightBounds
        let localFrame = fullSpectrumConic
            ? validBounds.insetBy(dx: -glowPadding, dy: -glowPadding)
            : bounds

        let localPath: CGPath
        if fullSpectrumConic {
            var tx = CGAffineTransform(translationX: -localFrame.origin.x, y: -localFrame.origin.y)
            localPath = path.copy(using: &tx) ?? path
        } else {
            localPath = path
        }

        let localBounds = CGRect(origin: .zero, size: localFrame.size)
        let activeScale = max(1.0, contentsScale)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for ring in rings {
            if let blurContainer = ring.blurContainer {
                blurContainer.frame = localFrame
                ring.gradient.frame = localBounds
            } else {
                ring.gradient.frame = localFrame
            }
            ring.mask.frame = localBounds
            ring.mask.path = localPath
            ring.mask.contentsScale = activeScale
        }
        if let clip = innerEdgeClipLayer,
           let clipMask = innerEdgeClipMask,
           let fill = innerEdgeFillLayer,
           let edgeBlur = innerEdgeBlurContainer,
           let edgeGrad = innerEdgeStrokeGradient,
           let edgeMask = innerEdgeStrokeMask {
            clip.frame = localFrame
            clip.isHidden = !showInteriorAmbient
            clipMask.frame = localBounds
            clipMask.path = showInteriorAmbient ? localPath : nil
            clipMask.contentsScale = activeScale
            fill.frame = localBounds
            edgeBlur.frame = localBounds
            edgeGrad.frame = localBounds
            edgeMask.frame = localBounds
            edgeMask.path = showInteriorAmbient ? localPath : nil
            edgeMask.contentsScale = activeScale
        }
        CATransaction.commit()
    }

    func updateAnimation(time t: Double, speed: Double = 1.15) {
        // Gentle harmonic modulation avoids robotic linear rotation around rounded corners
        let angle = t * speed + 0.38 * sin(t * 0.85)
        if fullSpectrumConic {
            let start = CGPoint(x: 0.5, y: 0.5)
            let end = CGPoint(x: 0.5 + 0.5 * cos(angle), y: 0.5 + 0.5 * sin(angle))
            let colors = LuminousPalette.fullSpectrumLoopColors(phase: t * 0.85)
            for ring in rings {
                ring.gradient.startPoint = start
                ring.gradient.endPoint = end
                ring.gradient.colors = colors
            }
            if let fill = innerEdgeFillLayer, let edgeGrad = innerEdgeStrokeGradient {
                fill.startPoint = start
                fill.endPoint = end
                fill.colors = colors
                edgeGrad.startPoint = start
                edgeGrad.endPoint = end
                edgeGrad.colors = colors
            }
            return
        }

        let dx = 0.5 * cos(angle)
        let dy = 0.5 * sin(angle)
        let start = CGPoint(x: 0.5 + dx, y: 0.5 + dy)
        let end = CGPoint(x: 0.5 - dx, y: 0.5 - dy)
        let colors = LuminousPalette.gradientColors(phase: t * 0.52)

        for ring in rings {
            ring.gradient.startPoint = start
            ring.gradient.endPoint = end
            ring.gradient.colors = colors
        }
    }
}

// MARK: - Custom Glowing Crosshair / Dot Selection Cursor

@MainActor
private enum CustomSelectionCursor {
    static let shared: NSCursor = {
        let size = NSSize(width: 28, height: 28)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)

            // Soft luminous halo
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                NSColor(red: 0.38, green: 0.68, blue: 1.0, alpha: 0.42).cgColor,
                NSColor(red: 0.62, green: 0.44, blue: 1.0, alpha: 0.16).cgColor,
                NSColor.clear.cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.55, 1]) {
                ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: 12, options: [])
            }

            // Crisp dark contrast shadow + luminous white crosshair ticks
            let armInner: CGFloat = 4.5
            let armOuter: CGFloat = 10.5
            for pass in 0..<2 {
                ctx.saveGState()
                if pass == 0 {
                    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
                    ctx.setLineWidth(2.6)
                } else {
                    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
                    ctx.setLineWidth(1.4)
                }
                ctx.setLineCap(.round)
                // Left, Right, Top, Bottom ticks
                ctx.move(to: CGPoint(x: center.x - armOuter, y: center.y))
                ctx.addLine(to: CGPoint(x: center.x - armInner, y: center.y))
                ctx.move(to: CGPoint(x: center.x + armInner, y: center.y))
                ctx.addLine(to: CGPoint(x: center.x + armOuter, y: center.y))
                ctx.move(to: CGPoint(x: center.x, y: center.y - armOuter))
                ctx.addLine(to: CGPoint(x: center.x, y: center.y - armInner))
                ctx.move(to: CGPoint(x: center.x, y: center.y + armInner))
                ctx.addLine(to: CGPoint(x: center.x, y: center.y + armOuter))
                ctx.strokePath()
                ctx.restoreGState()
            }

            // Glowing center dot
            ctx.setFillColor(NSColor(red: 0.36, green: 0.68, blue: 1.0, alpha: 0.95).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - 2.3, y: center.y - 2.3, width: 4.6, height: 4.6))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - 1.3, y: center.y - 1.3, width: 2.6, height: 2.6))
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 14, y: 14))
    }()
}

// MARK: - In-Place Translation Overlay (Google Lens Style Over-Image Text)

@MainActor
private final class InPlaceTranslationOverlayView: NSView {
    private var translatedBlocks: [(rect: CGRect, translated: String)] = []

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func updateBlocks(_ blocks: [(rect: CGRect, translated: String)], cornerRadius: CGFloat) {
        layer?.cornerRadius = cornerRadius
        translatedBlocks = blocks
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !translatedBlocks.isEmpty else { return }
        for item in translatedBlocks {
            let r = CGRect(
                x: item.rect.origin.x * bounds.width,
                y: item.rect.origin.y * bounds.height,
                width: item.rect.width * bounds.width,
                height: item.rect.height * bounds.height
            ).insetBy(dx: -3, dy: -2)
            guard r.width > 8, r.height > 6 else { continue }

            let pillRadius = min(6, r.height * 0.32)
            let pillPath = NSBezierPath(roundedRect: r, xRadius: pillRadius, yRadius: pillRadius)
            NSColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 0.88).setFill()
            pillPath.fill()
            NSColor.white.withAlphaComponent(0.24).setStroke()
            pillPath.lineWidth = 0.75
            pillPath.stroke()

            let fontSize = max(9.5, min(18.0, r.height * 0.64))
            let style = NSMutableParagraphStyle()
            style.alignment = .left
            style.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: style
            ]
            let textRect = r.insetBy(dx: 4, dy: max(0, (r.height - fontSize * 1.25) / 2))
            NSString(string: item.translated).draw(in: textRect, withAttributes: attrs)
        }
    }
}

// MARK: - Main Overlay Canvas (120fps CADisplayLink Engine)

@MainActor
private final class OverlayCanvasView: NSView {
    private let screenshot: CGImage
    private let safeInsets: NSEdgeInsets
    private var currentMode: SelectionMode
    private let onShowToast: (String) -> Void
    private let onOpenSettings: () -> Void
    private let onDismiss: () -> Void
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?
    private var canvasTrackingArea: NSTrackingArea?

    private var glowMultiplier: Float {
        let base = Float(AppSettings.shared.glowIntensity.opacityMultiplier)
        return AppSettings.shared.effectiveReduceMotion ? min(0.50, base * 0.58) : base
    }

    func handleKeyboardModeSwitch(_ mode: SelectionMode) {
        currentMode = mode
        AppSettings.shared.selectionMode = mode
        bottomSearchBar.syncMode(mode)
        onShowToast("Mode: \(mode.title) (\(mode.shortcutBadge))")
    }

    func handleKeyboardCopy() {
        if let sheet = resultsSheet {
            sheet.triggerKeyboardCopy()
        } else if let cropped = croppedImage {
            copyImageToClipboard(cropped)
            onShowToast("Selected image copied to clipboard")
        }
    }

    func handleKeyboardPin() {
        guard let cropped = croppedImage, let rect = selectionRect else { return }
        let screenRect = window?.convertToScreen(rect) ?? rect
        PinnedCaptureManager.shared.pin(image: cropped, initialRect: screenRect, onToast: onShowToast)
        onShowToast("Pinned capture to screen")
    }

    private let screenFrameLayer = CALayer()
    private let bgLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let auroraContainer = CALayer()
    private var auroraBlobs: [(layer: CAGradientLayer, base: CGPoint, rx: CGFloat, ry: CGFloat, speed: Double, phase: Double)] = []
    private let bottomEdgeGlowPrimary = CAGradientLayer()
    private let bottomEdgeGlowSecondary = CAGradientLayer()
    private let ambientSparkleEmitter = CAEmitterLayer()
    private let twinkleContainer = CALayer()
    private var twinkleStars: [(layer: CALayer, base: CGPoint, size: CGFloat, speed: Double, phase: Double, spinSpeed: Double, maxAlpha: Double)] = []
    private let entryWaveLayer = CAGradientLayer()

    private let glowHostView = LuminousGlowHostView(frame: .zero)
    private let screenPerimeterGlow = GlowingRoundedBorderLayer(
        wideLine: 14,
        midLine: 5,
        coreLine: 1.0,
        coreOpacity: 0.24,
        useCoreImageBlur: false
    )

    private let selectionCropGroupLayer = CALayer()
    private let selectionGlowGroupLayer = CALayer()
    private let selectionPopLayer = CALayer()
    private let selectionRippleLayer = CAShapeLayer()
    private let selectionGlowLayer = GlowingRoundedBorderLayer(
        wideLine: 20,
        midLine: 6.5,
        coreLine: 1.25,
        coreOpacity: 0.48,
        fullSpectrumConic: true,
        interiorAmbientOpacity: 0.0,
        useCoreImageBlur: false
    )
    private let selectionFrameLayer = CAShapeLayer()
    private let lassoGlowLayer = GlowingRoundedBorderLayer(
        wideLine: 18,
        midLine: 6.0,
        coreLine: 1.4,
        coreOpacity: 0.54,
        fullSpectrumConic: true,
        interiorAmbientOpacity: 0.0,
        useCoreImageBlur: false
    )
    private let lassoCoreLayer = CAShapeLayer()
    private var activeSelectionPath: CGPath?
    private var activeFreehandPath: CGPath?
    private var activeSelectionCornerR: CGFloat = 18
    private let cursorOrbLayer = CALayer()
    private let trailSparkleEmitter = CAEmitterLayer()
    private let selectionSparkleEmitter = CAEmitterLayer()

    private let bracketsLayer = CAShapeLayer()
    private let scanBeamContainer = CALayer()
    private let scanBeamGradient = CAGradientLayer()
    private let inPlaceTranslationView = InPlaceTranslationOverlayView(frame: .zero)

    private var dragPoints: [CGPoint] = []
    private var isDragging = false
    private var selectionRect: CGRect?
    private var croppedImage: CGImage?
    private var searchTask: Task<Void, Never>?

    private var bottomSearchBar: GooglePromptCapsuleView!
    private var bottomBarCenterXConstraint: NSLayoutConstraint!
    private var bottomBarBottomConstraint: NSLayoutConstraint!
    private var resultsSheet: GoogleResultsSheetView?

    private var displayLink: CADisplayLink?
    private var isHighRateActive: Bool = true
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var lastTickTime: CFTimeInterval = CACurrentMediaTime()

    init(
        frame: NSRect,
        screenshot: CGImage,
        safeInsets: NSEdgeInsets,
        selectionMode: SelectionMode,
        initialSelection: (image: CGImage, rect: CGRect)? = nil,
        onShowToast: @escaping (String) -> Void,
        onOpenSettings: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.screenshot = screenshot
        self.safeInsets = safeInsets
        self.currentMode = selectionMode
        self.onShowToast = onShowToast
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
        super.init(frame: frame)

        wantsLayer = true
        setupLayers()
        inPlaceTranslationView.isHidden = true
        addSubview(inPlaceTranslationView)
        setupBottomPromptCapsule()
        playEntryAnimations()
        startDisplayLink()

        if let initial = initialSelection {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.presentPreselectedRegion(rect: initial.rect, cropped: initial.image)
            }
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .circleToSearchSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyLiveSettings()
            }
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let canvasTrackingArea {
            removeTrackingArea(canvasTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        canvasTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let sheet = resultsSheet, sheet.frame.contains(pt) {
            return
        }
        if bottomSearchBar.alphaValue > 0.1,
           bottomSearchBar.frame.insetBy(dx: 24, dy: 24).contains(pt) {
            return
        }
        CustomSelectionCursor.shared.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: CustomSelectionCursor.shared)
    }

    private func applyLiveSettings() {
        let settings = AppSettings.shared
        currentMode = settings.selectionMode
        bottomSearchBar.syncMode(settings.selectionMode)

        let starAlpha: Float = settings.showAmbientStars ? 0.92 : 0.0
        let ambientAlpha: Float = settings.showAmbientStars ? 0.85 : 0.0
        CATransaction.begin()
        CATransaction.setAnimationDuration(AppleMotion.duration(0.24))
        CATransaction.setAnimationTimingFunction(AppleMotion.easeOut)
        twinkleContainer.opacity = selectionRect == nil ? starAlpha : (settings.showAmbientStars ? 0.55 : 0.0)
        ambientSparkleEmitter.opacity = selectionRect == nil ? ambientAlpha : (settings.showAmbientStars ? 0.55 : 0.0)
        CATransaction.commit()
        resultsSheet?.syncWebViewAppearance()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncRetinaContentsScale()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncRetinaContentsScale()
    }

    private func syncRetinaContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        if let root = layer {
            applyContentsScaleRecursive(scale, to: root)
        }
        if let glowRoot = glowHostView.layer {
            applyContentsScaleRecursive(scale, to: glowRoot)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    private func startDisplayLink() {
        let now = CACurrentMediaTime()
        startTime = now
        lastTickTime = now
        let link = displayLink(target: self, selector: #selector(handleDisplayTick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        isHighRateActive = true
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    private func updateDisplayLinkRateIfNeeded(elapsed t: CFTimeInterval) {
        // Keep full 60-120Hz ProMotion active throughout the overlay session for butter-smooth springs & dragging
        guard !isHighRateActive, let link = displayLink else { return }
        isHighRateActive = true
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleDisplayTick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let t = now - startTime
        let dt = min(1.0 / 30.0, max(0.0, now - lastTickTime))
        lastTickTime = now
        updateDisplayLinkRateIfNeeded(elapsed: t)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // 1. Soft flowing rounded perimeter glow (gentle & non-distracting)
        let gMult = glowMultiplier
        let breathe = 0.78 + 0.14 * sin(t * 1.7)
        screenPerimeterGlow.opacity = min(1.0, Float(breathe * 0.48) * gMult)
        screenPerimeterGlow.updateAnimation(time: t, speed: 1.05)

        // 2. Smoothly drifting ambient aurora clouds & soft bottom glowing bar
        for item in auroraBlobs {
            let x = item.base.x + item.rx * CGFloat(sin(t * item.speed + item.phase))
            let y = item.base.y + item.ry * CGFloat(cos(t * item.speed * 0.8 + item.phase))
            item.layer.position = CGPoint(x: x, y: y)
        }

        let barShift1 = bounds.width * 0.13 * CGFloat(sin(t * 0.48))
        let barShift2 = bounds.width * 0.15 * CGFloat(cos(t * 0.56 + 1.1))
        bottomEdgeGlowPrimary.position = CGPoint(x: bounds.midX + barShift1, y: bounds.height - 14)
        bottomEdgeGlowSecondary.position = CGPoint(x: bounds.midX + barShift2, y: bounds.height - 10)

        let c1 = LuminousPalette.gradientColors(phase: t * 0.50, alpha: 0.40)
        let c1Mid = LuminousPalette.gradientColors(phase: t * 0.50 + 0.9, alpha: 0.17)
        bottomEdgeGlowPrimary.colors = [c1[0], c1Mid[1], c1[2].copy(alpha: 0.05) ?? NSColor.clear.cgColor, NSColor.clear.cgColor]

        let c2 = LuminousPalette.gradientColors(phase: t * 0.65 + 2.1, alpha: 0.44)
        let c2Mid = LuminousPalette.gradientColors(phase: t * 0.65 + 3.0, alpha: 0.16)
        bottomEdgeGlowSecondary.colors = [c2[0], c2Mid[1], NSColor.clear.cgColor]

        // 3. Smoothly twinkling 4-point little stars
        for star in twinkleStars {
            let wave = max(0.0, sin(t * star.speed + star.phase))
            let glow = pow(wave, 2.3)
            star.layer.opacity = Float(glow * star.maxAlpha)
            let s = CGFloat(0.55 + 0.58 * glow)
            let rot = CGFloat(t * star.spinSpeed)
            let xf = CATransform3DMakeRotation(rot, 0, 0, 1)
            star.layer.transform = CATransform3DScale(xf, s, s, 1)
            let driftY = CGFloat(sin(t * 0.7 + star.phase)) * 6.0
            star.layer.position = CGPoint(x: star.base.x, y: star.base.y - driftY)
        }

        // 4. Selection & active box/circle full-RGB ambient glow
        if !selectionGlowLayer.isHidden {
            let selBreathe = 0.86 + 0.14 * sin(t * 2.4)
            selectionGlowLayer.opacity = min(1.0, Float(selBreathe) * gMult)
            selectionGlowLayer.updateAnimation(time: t, speed: 1.65)
        }
        if !lassoGlowLayer.isHidden {
            lassoGlowLayer.opacity = min(1.0, gMult)
            lassoGlowLayer.updateAnimation(time: t, speed: 1.95)
        }

        // 5. Cursor orb breathing while drawing
        if !cursorOrbLayer.isHidden {
            let s = 1.0 + 0.16 * sin(t * 10.0)
            cursorOrbLayer.transform = CATransform3DMakeScale(CGFloat(s), CGFloat(s), 1)
            cursorOrbLayer.shadowColor = LuminousPalette.fullSpectrumLoopColors(phase: t * 0.85)[0]
        }

        // 6. Bottom prompt capsule & sheet flowing soft border glow + drag inertia physics
        bottomSearchBar.updatePhysics(dt: dt)
        if bottomSearchBar.alphaValue > 0.02 {
            bottomSearchBar.updateGlow(time: t)
        }
        resultsSheet?.updatePhysics(dt: dt)
        if let sheet = resultsSheet, sheet.alphaValue > 0.02 {
            sheet.updateGlow(time: t)
        }

        CATransaction.commit()
    }

    private func setupLayers() {
        guard let root = layer else { return }

        root.backgroundColor = NSColor.black.cgColor

        // 1. Screen frame container (settles inward with rounded corners on entry)
        screenFrameLayer.frame = bounds
        screenFrameLayer.masksToBounds = true
        screenFrameLayer.cornerRadius = 0

        bgLayer.frame = bounds
        bgLayer.contents = screenshot
        bgLayer.contentsGravity = .resizeAspectFill
        screenFrameLayer.addSublayer(bgLayer)

        // 2. Smooth dim cutout layer
        dimLayer.frame = bounds
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.0).cgColor
        dimLayer.path = CGPath(rect: bounds, transform: nil)
        screenFrameLayer.addSublayer(dimLayer)

        // 3. Ambient aurora clouds & soft bottom edge glowing bar
        setupAuroraAndGlowBars(in: screenFrameLayer)

        // 4. Floating micro-stars & twinkling 4-point starlight
        setupStarEffects(in: screenFrameLayer, glowLayer: glowHostView.layer ?? root)

        // 5. Entry Light Wave Sweep (sweeps smoothly up across screen on launch)
        entryWaveLayer.frame = CGRect(x: 0, y: bounds.height, width: bounds.width, height: bounds.height * 0.65)
        entryWaveLayer.colors = [
            NSColor.clear.cgColor,
            NSColor(red: 0.06, green: 0.36, blue: 0.96, alpha: 0.28).cgColor,
            NSColor(red: 0.14, green: 0.66, blue: 1.00, alpha: 0.30).cgColor,
            NSColor(red: 0.48, green: 0.90, blue: 1.00, alpha: 0.22).cgColor,
            NSColor.clear.cgColor
        ]
        entryWaveLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        entryWaveLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        entryWaveLayer.isHidden = true
        screenFrameLayer.addSublayer(entryWaveLayer)

        root.addSublayer(screenFrameLayer)

        selectionCropGroupLayer.frame = bounds
        selectionCropGroupLayer.masksToBounds = false
        root.addSublayer(selectionCropGroupLayer)

        // 7. Tactile Spotlight Pop Layer
        selectionPopLayer.masksToBounds = true
        selectionPopLayer.cornerRadius = 18
        selectionPopLayer.isHidden = true
        selectionPopLayer.shadowColor = NSColor.black.cgColor
        selectionPopLayer.shadowOpacity = 0.40
        selectionPopLayer.shadowRadius = 22
        selectionPopLayer.shadowOffset = CGSize(width: 0, height: 6)
        selectionCropGroupLayer.addSublayer(selectionPopLayer)

        // 9. Soft Luminous Blue Scan Sweep Inside Selection
        scanBeamContainer.masksToBounds = true
        scanBeamContainer.isHidden = true
        scanBeamContainer.cornerRadius = 18

        scanBeamGradient.colors = [
            NSColor.clear.cgColor,
            NSColor(red: 0.06, green: 0.42, blue: 0.96, alpha: 0.05).cgColor,
            NSColor(red: 0.12, green: 0.62, blue: 1.00, alpha: 0.15).cgColor,
            NSColor(red: 0.72, green: 0.94, blue: 1.00, alpha: 0.24).cgColor,
            NSColor(red: 0.14, green: 0.68, blue: 1.00, alpha: 0.14).cgColor,
            NSColor(red: 0.06, green: 0.42, blue: 0.96, alpha: 0.05).cgColor,
            NSColor.clear.cgColor
        ]
        scanBeamGradient.locations = [0.0, 0.18, 0.38, 0.50, 0.62, 0.82, 1.0]
        scanBeamGradient.startPoint = CGPoint(x: 0, y: 0.28)
        scanBeamGradient.endPoint = CGPoint(x: 1, y: 0.72)
        scanBeamContainer.addSublayer(scanBeamGradient)
        selectionCropGroupLayer.addSublayer(scanBeamContainer)

        // Core Image Optical Glow Overlay Host (Retina GPU Gaussian Bloom above dim/cutout, below UI cards)
        glowHostView.frame = bounds
        glowHostView.autoresizingMask = [.width, .height]
        addSubview(glowHostView)
        if let glowRoot = glowHostView.layer {
            // 6. Soft Feathered Rounded Screen-Edge Glow
            screenPerimeterGlow.frame = bounds
            screenPerimeterGlow.opacity = 0.0
            screenPerimeterGlow.updatePath(roundedRect: bounds.insetBy(dx: 5, dy: 5), cornerRadius: 24)
            glowRoot.addSublayer(screenPerimeterGlow)

            selectionGlowGroupLayer.frame = bounds
            selectionGlowGroupLayer.masksToBounds = false
            glowRoot.addSublayer(selectionGlowGroupLayer)

            // 8. Crisp Exterior-Only Glowing Blue Halo around Selection
            selectionGlowLayer.frame = bounds
            selectionGlowLayer.isHidden = true
            selectionGlowGroupLayer.addSublayer(selectionGlowLayer)

            // Crisp 1.25pt hairline border hugging the selection edge cleanly
            selectionFrameLayer.frame = bounds
            selectionFrameLayer.fillColor = nil
            selectionFrameLayer.strokeColor = NSColor(red: 0.44, green: 0.86, blue: 1.0, alpha: 0.72).cgColor
            selectionFrameLayer.lineWidth = 1.25
            selectionFrameLayer.lineCap = .round
            selectionFrameLayer.lineJoin = .round
            selectionFrameLayer.isHidden = true
            selectionGlowGroupLayer.addSublayer(selectionFrameLayer)

            // 11. Ambient Circling/Box Bloom + Delicate Core Edge
            lassoGlowLayer.frame = bounds
            lassoGlowLayer.isHidden = true
            glowRoot.addSublayer(lassoGlowLayer)

            // 10. Crisp Rounded Corner Viewfinder Brackets [ ] & Glowing Shockwave Ripple
            selectionRippleLayer.frame = bounds
            selectionRippleLayer.fillColor = nil
            selectionRippleLayer.strokeColor = NSColor(red: 0.45, green: 0.86, blue: 1.0, alpha: 0.90).cgColor
            selectionRippleLayer.lineWidth = 2.2
            selectionRippleLayer.lineCap = .round
            selectionRippleLayer.lineJoin = .round
            selectionRippleLayer.shadowColor = NSColor(red: 0.22, green: 0.74, blue: 1.0, alpha: 1.0).cgColor
            selectionRippleLayer.shadowRadius = 8
            selectionRippleLayer.shadowOpacity = 0.75
            selectionRippleLayer.shadowOffset = .zero
            selectionRippleLayer.isHidden = true
            selectionGlowGroupLayer.addSublayer(selectionRippleLayer)

            bracketsLayer.frame = bounds
            bracketsLayer.fillColor = nil
            bracketsLayer.strokeColor = NSColor(red: 0.90, green: 0.97, blue: 1.0, alpha: 0.96).cgColor
            bracketsLayer.lineWidth = 2.6
            bracketsLayer.lineCap = .round
            bracketsLayer.lineJoin = .round
            bracketsLayer.shadowColor = NSColor(red: 0.14, green: 0.68, blue: 1.0, alpha: 0.85).cgColor
            bracketsLayer.shadowRadius = 5.5
            bracketsLayer.shadowOpacity = 0.90
            bracketsLayer.shadowOffset = .zero
            bracketsLayer.isHidden = true
            selectionGlowGroupLayer.addSublayer(bracketsLayer)

            lassoCoreLayer.frame = bounds
            lassoCoreLayer.fillColor = nil
            lassoCoreLayer.strokeColor = NSColor(red: 0.84, green: 0.96, blue: 1.0, alpha: 0.86).cgColor
            lassoCoreLayer.lineWidth = 1.4
            lassoCoreLayer.lineCap = .round
            lassoCoreLayer.lineJoin = .round
            lassoCoreLayer.isHidden = true
            glowRoot.addSublayer(lassoCoreLayer)

            // 12. Soft Glowing Light-Flare Cursor Orb (Retina 2x)
            cursorOrbLayer.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
            cursorOrbLayer.contents = SparkleFactory.makeOrbFlareCGImage()
            cursorOrbLayer.contentsGravity = .resizeAspect
            cursorOrbLayer.shadowColor = NSColor(red: 0.35, green: 0.82, blue: 1.0, alpha: 1.0).cgColor
            cursorOrbLayer.shadowRadius = 11
            cursorOrbLayer.shadowOpacity = 0.90
            cursorOrbLayer.shadowOffset = .zero
            cursorOrbLayer.isHidden = true
            glowRoot.addSublayer(cursorOrbLayer)
        }

        syncRetinaContentsScale()
    }

    private func setupAuroraAndGlowBars(in parent: CALayer) {
        auroraContainer.frame = bounds
        auroraContainer.opacity = 0.0
        auroraContainer.masksToBounds = true

        let maxDim = max(bounds.width, bounds.height)
        let blobConfigs: [(CGPoint, CGFloat, CGFloat, CGFloat, Double, Double, [CGColor])] = [
            (
                CGPoint(x: bounds.width * 0.25, y: bounds.height * 0.82),
                maxDim * 0.52, 130, 75, 0.55, 0.0,
                [
                    NSColor(red: 0.08, green: 0.44, blue: 0.98, alpha: 0.26).cgColor,
                    NSColor(red: 0.08, green: 0.44, blue: 0.98, alpha: 0.0).cgColor
                ]
            ),
            (
                CGPoint(x: bounds.width * 0.76, y: bounds.height * 0.76),
                maxDim * 0.48, 140, 85, 0.48, 1.8,
                [
                    NSColor(red: 0.14, green: 0.68, blue: 1.00, alpha: 0.22).cgColor,
                    NSColor(red: 0.14, green: 0.68, blue: 1.00, alpha: 0.0).cgColor
                ]
            ),
            (
                CGPoint(x: bounds.width * 0.50, y: bounds.height * 0.92),
                maxDim * 0.46, 110, 90, 0.62, 3.3,
                [
                    NSColor(red: 0.36, green: 0.88, blue: 1.00, alpha: 0.18).cgColor,
                    NSColor.clear.cgColor
                ]
            )
        ]

        for cfg in blobConfigs {
            let blob = CAGradientLayer()
            blob.type = .radial
            let r = cfg.1
            blob.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
            blob.position = cfg.0
            blob.colors = cfg.6
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1.0, y: 1.0)
            auroraContainer.addSublayer(blob)
            auroraBlobs.append((blob, cfg.0, cfg.2, cfg.3, cfg.4, cfg.5))
        }

        // Wide, ultra-soft glowing blue bar rising gently along the bottom edge
        bottomEdgeGlowPrimary.type = .radial
        bottomEdgeGlowPrimary.bounds = CGRect(x: 0, y: 0, width: bounds.width * 1.10, height: 240)
        bottomEdgeGlowPrimary.position = CGPoint(x: bounds.midX, y: bounds.height - 14)
        bottomEdgeGlowPrimary.startPoint = CGPoint(x: 0.5, y: 0.5)
        bottomEdgeGlowPrimary.endPoint = CGPoint(x: 1.0, y: 1.0)
        bottomEdgeGlowPrimary.locations = [0.0, 0.42, 0.75, 1.0]
        bottomEdgeGlowPrimary.colors = [
            NSColor(red: 0.08, green: 0.52, blue: 1.00, alpha: 0.30).cgColor,
            NSColor(red: 0.16, green: 0.72, blue: 1.00, alpha: 0.14).cgColor,
            NSColor(red: 0.42, green: 0.88, blue: 1.00, alpha: 0.04).cgColor,
            NSColor.clear.cgColor
        ]
        auroraContainer.addSublayer(bottomEdgeGlowPrimary)

        bottomEdgeGlowSecondary.type = .radial
        bottomEdgeGlowSecondary.bounds = CGRect(x: 0, y: 0, width: bounds.width * 0.74, height: 165)
        bottomEdgeGlowSecondary.position = CGPoint(x: bounds.midX, y: bounds.height - 10)
        bottomEdgeGlowSecondary.startPoint = CGPoint(x: 0.5, y: 0.5)
        bottomEdgeGlowSecondary.endPoint = CGPoint(x: 1.0, y: 1.0)
        bottomEdgeGlowSecondary.locations = [0.0, 0.48, 1.0]
        bottomEdgeGlowSecondary.colors = [
            NSColor(red: 0.32, green: 0.84, blue: 1.00, alpha: 0.28).cgColor,
            NSColor(red: 0.08, green: 0.44, blue: 0.96, alpha: 0.12).cgColor,
            NSColor.clear.cgColor
        ]
        auroraContainer.addSublayer(bottomEdgeGlowSecondary)

        parent.addSublayer(auroraContainer)
    }

    private func setupStarEffects(in frameLayer: CALayer, glowLayer: CALayer) {
        let sparkleImg = SparkleFactory.makeSparkleCGImage()

        // 1. Pre-warmed Ambient Floating Micro-Stars (adds instant stardust depth)
        ambientSparkleEmitter.frame = bounds
        ambientSparkleEmitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        ambientSparkleEmitter.emitterSize = bounds.size
        ambientSparkleEmitter.emitterShape = .rectangle
        ambientSparkleEmitter.renderMode = .additive
        ambientSparkleEmitter.beginTime = CACurrentMediaTime() - 2.0
        ambientSparkleEmitter.opacity = 0.0

        let whiteStar = CAEmitterCell()
        whiteStar.contents = sparkleImg
        whiteStar.birthRate = 14
        whiteStar.lifetime = 3.0
        whiteStar.lifetimeRange = 1.1
        whiteStar.velocity = 11
        whiteStar.velocityRange = 8
        whiteStar.emissionRange = .pi * 2
        whiteStar.scale = 0.11
        whiteStar.scaleRange = 0.08
        whiteStar.alphaSpeed = -0.26
        whiteStar.spin = 0.6
        whiteStar.spinRange = 1.2
        whiteStar.color = NSColor(red: 0.90, green: 0.96, blue: 1.0, alpha: 0.72).cgColor

        let tintedStar = CAEmitterCell()
        tintedStar.contents = sparkleImg
        tintedStar.birthRate = 6
        tintedStar.lifetime = 3.4
        tintedStar.lifetimeRange = 1.0
        tintedStar.velocity = 8
        tintedStar.velocityRange = 6
        tintedStar.emissionRange = .pi * 2
        tintedStar.scale = 0.14
        tintedStar.scaleRange = 0.08
        tintedStar.alphaSpeed = -0.24
        tintedStar.spin = -0.5
        tintedStar.spinRange = 1.0
        tintedStar.color = NSColor(red: 0.70, green: 0.86, blue: 1.0, alpha: 0.62).cgColor

        ambientSparkleEmitter.emitterCells = [whiteStar, tintedStar]
        frameLayer.addSublayer(ambientSparkleEmitter)

        // 2. Smoothly sinusoidal twinkling 4-point stars (no abrupt popping)
        twinkleContainer.frame = bounds
        twinkleContainer.opacity = 0.0
        let count = 26
        for i in 0..<count {
            let nx = CGFloat((Double(i) * 0.61803398875 + 0.13).truncatingRemainder(dividingBy: 1.0))
            let ny = CGFloat((Double(i) * 0.38196601125 + 0.08).truncatingRemainder(dividingBy: 1.0))
            let pos = CGPoint(
                x: 36 + nx * max(40, bounds.width - 72),
                y: 36 + ny * max(40, bounds.height - 96)
            )
            let size = CGFloat(14 + (i % 5) * 3)
            let star = CALayer()
            star.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            star.position = pos
            star.contents = sparkleImg
            star.contentsGravity = .resizeAspect
            star.opacity = 0
            twinkleContainer.addSublayer(star)
            twinkleStars.append((
                layer: star,
                base: pos,
                size: size,
                speed: 1.15 + Double(i % 6) * 0.28,
                phase: Double(i) * 1.17,
                spinSpeed: (i % 2 == 0 ? 0.35 : -0.30) * (1.0 + Double(i % 3) * 0.25),
                maxAlpha: 0.42 + Double(i % 4) * 0.11
            ))
        }
        frameLayer.addSublayer(twinkleContainer)

        // 3. Circling Lasso Trail Sparkles
        trailSparkleEmitter.frame = bounds
        trailSparkleEmitter.emitterShape = .point
        trailSparkleEmitter.renderMode = .additive
        trailSparkleEmitter.birthRate = 0

        let trailCell = CAEmitterCell()
        trailCell.contents = sparkleImg
        trailCell.birthRate = 48
        trailCell.lifetime = 0.55
        trailCell.lifetimeRange = 0.22
        trailCell.velocity = 34
        trailCell.velocityRange = 20
        trailCell.emissionRange = .pi * 2
        trailCell.scale = 0.16
        trailCell.scaleSpeed = -0.18
        trailCell.alphaSpeed = -1.6
        trailCell.spin = 1.8
        trailCell.color = NSColor(red: 0.92, green: 0.97, blue: 1.0, alpha: 0.95).cgColor
        trailSparkleEmitter.emitterCells = [trailCell]
        glowLayer.addSublayer(trailSparkleEmitter)

        // 4. Selection Sparkle Shimmer Burst
        selectionSparkleEmitter.frame = bounds
        selectionSparkleEmitter.emitterShape = .rectangle
        selectionSparkleEmitter.renderMode = .additive
        selectionSparkleEmitter.birthRate = 0

        let burstCell = CAEmitterCell()
        burstCell.contents = sparkleImg
        burstCell.birthRate = 90
        burstCell.lifetime = 0.85
        burstCell.lifetimeRange = 0.30
        burstCell.velocity = 24
        burstCell.velocityRange = 18
        burstCell.emissionRange = .pi * 2
        burstCell.scale = 0.18
        burstCell.scaleRange = 0.08
        burstCell.scaleSpeed = -0.14
        burstCell.alphaSpeed = -1.05
        burstCell.spin = 1.2
        burstCell.color = NSColor.white.cgColor
        selectionSparkleEmitter.emitterCells = [burstCell]
        glowLayer.addSublayer(selectionSparkleEmitter)
    }

    private func setupBottomPromptCapsule() {
        let defaultBottomOffset = -(safeInsets.bottom + 18 - 24)
        bottomSearchBar = GooglePromptCapsuleView(
            mode: currentMode,
            defaultOffset: CGPoint(x: 0, y: defaultBottomOffset),
            currentOffset: { [weak self] in
                guard let self else { return .zero }
                return CGPoint(
                    x: self.bottomBarCenterXConstraint.constant,
                    y: self.bottomBarBottomConstraint.constant
                )
            },
            setOffset: { [weak self] next in
                guard let self else { return }
                self.bottomBarCenterXConstraint.constant = next.x
                self.bottomBarBottomConstraint.constant = next.y
            },
            animateToOffset: { [weak self] target in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = AppleMotion.duration(0.36)
                    ctx.timingFunction = AppleMotion.easeInOut
                    self.bottomBarCenterXConstraint.animator().constant = target.x
                    self.bottomBarBottomConstraint.animator().constant = target.y
                }
            },
            allowedOffsets: { [weak self] in
                guard let self else { return .zero }
                let pillPad: CGFloat = 24
                let visualHalfW = max(80, (self.bottomSearchBar.bounds.width - pillPad * 2) / 2)
                let minX = self.safeInsets.left + visualHalfW - self.bounds.width / 2
                let maxX = max(minX, self.bounds.width - self.safeInsets.right - visualHalfW - self.bounds.width / 2)
                let minY = self.safeInsets.top + self.bottomSearchBar.bounds.height - pillPad - self.bounds.height
                let maxY = max(minY, -self.safeInsets.bottom + pillPad)
                return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
            },
            onToggleMode: { [weak self] newMode in
                self?.currentMode = newMode
                AppSettings.shared.selectionMode = newMode
            },
            onOpenSettings: { [weak self] in
                self?.onOpenSettings()
            },
            onClose: { [weak self] in
                self?.onDismiss()
            }
        )
        bottomSearchBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomSearchBar)
        // Offset by outer glowPadding (24pt) so the visual glass pill sits cleanly above the Dock
        bottomBarCenterXConstraint = bottomSearchBar.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 0)
        bottomBarBottomConstraint = bottomSearchBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: defaultBottomOffset)
        NSLayoutConstraint.activate([
            bottomBarCenterXConstraint,
            bottomBarBottomConstraint
        ])
    }

    private func playEntryAnimations() {
        layoutSubtreeIfNeeded()
        let showStars = AppSettings.shared.showAmbientStars

        // 1. Desktop focus settle (physics spring + ease-out rounded corners)
        let cornerAnim = CABasicAnimation(keyPath: "cornerRadius")
        cornerAnim.fromValue = 0.0
        cornerAnim.toValue = 24.0
        cornerAnim.duration = AppleMotion.duration(0.46)
        cornerAnim.timingFunction = AppleMotion.easeOut
        screenFrameLayer.cornerRadius = 24.0
        screenFrameLayer.add(cornerAnim, forKey: "frameCorners")

        let frameScale = AppleMotion.spring(
            keyPath: "transform.scale",
            from: 1.012,
            to: 1.0,
            dampingRatio: 0.90,
            response: 0.46
        )
        screenFrameLayer.transform = CATransform3DIdentity
        screenFrameLayer.add(frameScale, forKey: "frameSettle")

        // 2. Smooth dim & aurora ease-out reveal
        let dimAnim = CABasicAnimation(keyPath: "fillColor")
        dimAnim.fromValue = NSColor.black.withAlphaComponent(0.0).cgColor
        dimAnim.toValue = NSColor.black.withAlphaComponent(0.22).cgColor
        dimAnim.duration = AppleMotion.duration(0.40)
        dimAnim.timingFunction = AppleMotion.easeOut
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.22).cgColor
        dimLayer.add(dimAnim, forKey: "entryDim")

        let auroraAnim = CABasicAnimation(keyPath: "opacity")
        auroraAnim.fromValue = 0.0
        auroraAnim.toValue = 0.78
        auroraAnim.duration = AppleMotion.duration(0.56)
        auroraAnim.timingFunction = AppleMotion.easeOut
        auroraContainer.opacity = 0.78
        auroraContainer.add(auroraAnim, forKey: "entryAurora")

        let targetStarOpacity: Float = showStars ? 0.92 : 0.0
        let starsAnim = CABasicAnimation(keyPath: "opacity")
        starsAnim.fromValue = 0.0
        starsAnim.toValue = targetStarOpacity
        starsAnim.duration = AppleMotion.duration(0.60)
        starsAnim.timingFunction = AppleMotion.easeOut
        twinkleContainer.opacity = targetStarOpacity
        twinkleContainer.add(starsAnim, forKey: "entryTwinkles")

        let targetAmbientOpacity: Float = showStars ? 0.85 : 0.0
        let ambientStarsAnim = CABasicAnimation(keyPath: "opacity")
        ambientStarsAnim.fromValue = 0.0
        ambientStarsAnim.toValue = targetAmbientOpacity
        ambientStarsAnim.duration = AppleMotion.duration(0.60)
        ambientStarsAnim.timingFunction = AppleMotion.easeOut
        ambientSparkleEmitter.opacity = targetAmbientOpacity
        ambientSparkleEmitter.add(ambientStarsAnim, forKey: "entryAmbientStars")

        // 3. Upward light wave sweep across screen (smooth ease-in-out momentum)
        entryWaveLayer.isHidden = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.entryWaveLayer.isHidden = true
        }
        let waveMove = CABasicAnimation(keyPath: "position.y")
        waveMove.fromValue = bounds.height + entryWaveLayer.bounds.height * 0.4
        waveMove.toValue = -entryWaveLayer.bounds.height * 0.6
        waveMove.duration = AppleMotion.duration(0.68)
        waveMove.timingFunction = AppleMotion.easeInOut
        entryWaveLayer.add(waveMove, forKey: "waveSweep")
        CATransaction.commit()

        // 4. Bottom Liquid Glass capsule center-anchored physics spring + ease-out fade
        bottomSearchBar.wantsLayer = true
        bottomSearchBar.alphaValue = 0
        if let pillLayer = bottomSearchBar.layer {
            let startTransform = AppleMotion.centeredTransform(
                bounds: bottomSearchBar.bounds,
                scale: 0.90,
                translation: CGPoint(x: 0, y: 42)
            )
            let spring = AppleMotion.spring(
                keyPath: "transform",
                from: startTransform,
                to: CATransform3DIdentity,
                dampingRatio: 0.80,
                response: 0.46
            )
            pillLayer.transform = CATransform3DIdentity
            pillLayer.add(spring, forKey: "pillSpring")
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.30)
            ctx.timingFunction = AppleMotion.easeOut
            bottomSearchBar.animator().alphaValue = 1.0
        }
    }

    func playExitAnimation(completion: @escaping () -> Void) {
        searchTask?.cancel()
        stopDisplayLink()

        // Smooth ease-in release back to desktop
        let exitDuration = AppleMotion.duration(0.24)
        let expand = CABasicAnimation(keyPath: "transform.scale")
        expand.fromValue = screenFrameLayer.presentation()?.value(forKeyPath: "transform.scale") ?? 1.0
        expand.toValue = 1.008
        expand.duration = exitDuration
        expand.timingFunction = AppleMotion.easeIn
        screenFrameLayer.transform = CATransform3DMakeScale(1.008, 1.008, 1)
        screenFrameLayer.add(expand, forKey: "exitExpand")

        let cornerOut = CABasicAnimation(keyPath: "cornerRadius")
        cornerOut.fromValue = screenFrameLayer.cornerRadius
        cornerOut.toValue = 0.0
        cornerOut.duration = exitDuration
        cornerOut.timingFunction = AppleMotion.easeIn
        screenFrameLayer.cornerRadius = 0.0
        screenFrameLayer.add(cornerOut, forKey: "exitCorners")

        if let pillLayer = bottomSearchBar.layer, bottomSearchBar.alphaValue > 0.05 {
            let endPill = AppleMotion.centeredTransform(
                bounds: bottomSearchBar.bounds,
                scale: 0.92,
                translation: CGPoint(x: 0, y: 24)
            )
            let drop = CABasicAnimation(keyPath: "transform")
            drop.fromValue = pillLayer.presentation()?.transform ?? pillLayer.transform
            drop.toValue = endPill
            drop.duration = AppleMotion.duration(0.20)
            drop.timingFunction = AppleMotion.easeIn
            pillLayer.transform = endPill
            pillLayer.add(drop, forKey: "exitPill")
        }

        if let sheet = resultsSheet, let sheetLayer = sheet.layer {
            let shrink = AppleMotion.centeredTransform(bounds: sheet.bounds, scale: 0.94)
            let sheetOut = CABasicAnimation(keyPath: "transform")
            sheetOut.fromValue = sheetLayer.presentation()?.transform ?? sheetLayer.transform
            sheetOut.toValue = shrink
            sheetOut.duration = AppleMotion.duration(0.21)
            sheetOut.timingFunction = AppleMotion.easeIn
            sheetLayer.transform = shrink
            sheetLayer.add(sheetOut, forKey: "exitSheet")
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = exitDuration
            ctx.timingFunction = AppleMotion.easeIn
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.resultsSheet?.prepareForClose()
                self?.bgLayer.contents = nil
                self?.selectionPopLayer.contents = nil
                completion()
            }
        })
    }

    // MARK: - Mouse Circling Events

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let sheet = resultsSheet, sheet.frame.contains(pt) {
            return
        }
        if bottomSearchBar.alphaValue > 0.1 && bottomSearchBar.frame.insetBy(dx: 24, dy: 24).contains(pt) {
            return
        }

        isDragging = true
        selectionRect = nil
        croppedImage = nil
        activeSelectionPath = nil
        activeFreehandPath = nil
        searchTask?.cancel()
        dismissResultsSheet()
        inPlaceTranslationView.isHidden = true
        inPlaceTranslationView.updateBlocks([], cornerRadius: 18)

        selectionCropGroupLayer.mask = nil
        selectionGlowGroupLayer.mask = nil
        bracketsLayer.removeAllAnimations()
        bracketsLayer.isHidden = true
        selectionFrameLayer.removeAllAnimations()
        selectionFrameLayer.isHidden = true
        selectionPopLayer.mask = nil
        selectionPopLayer.isHidden = true
        selectionGlowLayer.mask = nil
        selectionGlowLayer.isHidden = true
        scanBeamGradient.removeAllAnimations()
        scanBeamContainer.mask = nil
        scanBeamContainer.isHidden = true

        let dimAnim = CABasicAnimation(keyPath: "fillColor")
        dimAnim.fromValue = dimLayer.fillColor
        dimAnim.toValue = NSColor.black.withAlphaComponent(0.22).cgColor
        dimAnim.duration = AppleMotion.duration(0.24)
        dimAnim.timingFunction = AppleMotion.easeOut
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.22).cgColor
        dimLayer.path = CGPath(rect: bounds, transform: nil)
        dimLayer.add(dimAnim, forKey: "resetDim")

        let showStars = AppSettings.shared.showAmbientStars
        twinkleContainer.opacity = showStars ? 0.92 : 0.0
        ambientSparkleEmitter.opacity = showStars ? 0.85 : 0.0

        if let pillLayer = bottomSearchBar.layer, bottomSearchBar.alphaValue > 0.05 {
            let hideTransform = AppleMotion.centeredTransform(
                bounds: bottomSearchBar.bounds,
                scale: 0.92,
                translation: CGPoint(x: 0, y: 20)
            )
            let hideAnim = CABasicAnimation(keyPath: "transform")
            hideAnim.fromValue = pillLayer.presentation()?.transform ?? pillLayer.transform
            hideAnim.toValue = hideTransform
            hideAnim.duration = AppleMotion.duration(0.20)
            hideAnim.timingFunction = AppleMotion.easeIn
            pillLayer.transform = hideTransform
            pillLayer.add(hideAnim, forKey: "pillHide")
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.20)
            ctx.timingFunction = AppleMotion.easeIn
            bottomSearchBar.animator().alphaValue = 0.0
        }

        dragPoints = [pt]
        lassoGlowLayer.removeAllAnimations()
        lassoCoreLayer.removeAllAnimations()
        lassoGlowLayer.opacity = min(1.0, glowMultiplier)
        lassoCoreLayer.opacity = 1.0
        lassoGlowLayer.isHidden = true
        lassoCoreLayer.isHidden = true
        lassoGlowLayer.updateAnimation(time: CACurrentMediaTime() - startTime, speed: 1.95)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorOrbLayer.position = pt
        cursorOrbLayer.isHidden = false
        trailSparkleEmitter.emitterPosition = pt
        trailSparkleEmitter.birthRate = AppSettings.shared.effectiveReduceMotion ? 0 : 1.0
        CATransaction.commit()

        updateLassoPath()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let pt = convert(event.locationInWindow, from: nil)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorOrbLayer.position = pt
        trailSparkleEmitter.emitterPosition = pt
        CATransaction.commit()

        let isRect = currentMode == .rectangle || currentMode == .textOnly || NSEvent.modifierFlags.contains(.option)
        if isRect {
            if dragPoints.count >= 2 {
                dragPoints[dragPoints.count - 1] = pt
            } else {
                dragPoints.append(pt)
            }
        } else if let last = dragPoints.last {
            if hypot(pt.x - last.x, pt.y - last.y) >= 2.2 {
                dragPoints.append(pt)
            } else {
                return
            }
        } else {
            dragPoints.append(pt)
        }

        updateLassoPath()
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        let pt = convert(event.locationInWindow, from: nil)
        if let last = dragPoints.last, hypot(pt.x - last.x, pt.y - last.y) > 0.5 {
            dragPoints.append(pt)
        }
        isDragging = false
        trailSparkleEmitter.birthRate = 0
        cursorOrbLayer.isHidden = true
        finalizeSelection()
    }

    private func buildSmoothClosedPath(from points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
            path.addQuadCurve(to: mid, control: prev)
        }
        if let last = points.last {
            let closingMid = CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2)
            path.addQuadCurve(to: closingMid, control: last)
            path.addQuadCurve(to: first, control: closingMid)
        }
        path.closeSubpath()
        return path
    }

    private func updateLassoPath() {
        guard dragPoints.count >= 2 else {
            lassoGlowLayer.isHidden = true
            lassoCoreLayer.isHidden = true
            lassoCoreLayer.path = nil
            return
        }

        lassoGlowLayer.isHidden = false
        lassoCoreLayer.isHidden = false

        let isRect = currentMode == .rectangle || currentMode == .textOnly || NSEvent.modifierFlags.contains(.option)
        let path = CGMutablePath()
        var tightBounds = CGRect.null

        if isRect, let first = dragPoints.first, let last = dragPoints.last {
            let rect = CGRect(
                x: min(first.x, last.x),
                y: min(first.y, last.y),
                width: abs(last.x - first.x),
                height: abs(last.y - first.y)
            )
            let cornerR = min(18, min(rect.width, rect.height) * 0.42)
            path.addRoundedRect(in: rect, cornerWidth: cornerR, cornerHeight: cornerR)
            tightBounds = rect

            // Live spotlight cutout inside the active selecting box so its content stays razor sharp
            if rect.width >= 6, rect.height >= 6 {
                let dimCutout = CGMutablePath()
                dimCutout.addRect(bounds)
                dimCutout.addRoundedRect(in: rect, cornerWidth: cornerR, cornerHeight: cornerR)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                dimLayer.fillColor = NSColor.black.withAlphaComponent(0.34).cgColor
                dimLayer.path = dimCutout
                CATransaction.commit()
            }
        } else {
            path.move(to: dragPoints[0])
            for i in 1..<dragPoints.count {
                let prev = dragPoints[i - 1]
                let curr = dragPoints[i]
                let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                path.addQuadCurve(to: mid, control: prev)
            }
            if let last = dragPoints.last {
                path.addLine(to: last)
            }
            tightBounds = path.boundingBoxOfPath

            if dragPoints.count >= 6, tightBounds.width >= 16, tightBounds.height >= 16 {
                let closedPreview = buildSmoothClosedPath(from: dragPoints)
                let dimCutout = CGMutablePath()
                dimCutout.addRect(bounds)
                dimCutout.addPath(closedPreview)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                dimLayer.fillColor = NSColor.black.withAlphaComponent(0.34).cgColor
                dimLayer.path = dimCutout
                CATransaction.commit()
            }
        }

        lassoGlowLayer.updatePath(
            path,
            tightBounds: tightBounds,
            glowPadding: 34,
            showInteriorAmbient: false
        )
        lassoCoreLayer.path = path
    }

    private func finalizeSelection() {
        let recordedPoints = dragPoints
        let firstPoint = recordedPoints.first
        let minX = recordedPoints.map(\.x).min() ?? 0
        let maxX = recordedPoints.map(\.x).max() ?? 0
        let minY = recordedPoints.map(\.y).min() ?? 0
        let maxY = recordedPoints.map(\.y).max() ?? 0
        let spanW = maxX - minX
        let spanH = maxY - minY
        dragPoints = []

        let isRectMode = currentMode == .rectangle || currentMode == .textOnly || NSEvent.modifierFlags.contains(.option)
        var freehandClosedPath: CGPath?

        let resolvedRect: CGRect
        if (spanW < 24 || spanH < 24), let tapPt = firstPoint, currentMode == .tap {
            let smart = VisionAnalyzer.detectSmartTapRect(in: screenshot, at: tapPt, canvasSize: bounds.size)
            let x = max(safeInsets.left, smart.minX)
            let y = max(safeInsets.top, smart.minY)
            let maxCX = min(bounds.width - safeInsets.right, smart.maxX)
            let maxCY = min(bounds.height - safeInsets.bottom, smart.maxY)
            resolvedRect = CGRect(x: x, y: y, width: max(48, maxCX - x), height: max(48, maxCY - y))
        } else if spanW >= 24 && spanH >= 24 {
            let pad: CGFloat = isRectMode ? 0 : 8
            let x = max(safeInsets.left, minX - pad)
            let y = max(safeInsets.top, minY - pad)
            let maxCX = min(bounds.width - safeInsets.right, maxX + pad)
            let maxCY = min(bounds.height - safeInsets.bottom, maxY + pad)
            resolvedRect = CGRect(
                x: x,
                y: y,
                width: max(24, maxCX - x),
                height: max(24, maxCY - y)
            )
            if currentMode == .circle && !isRectMode && recordedPoints.count >= 5 {
                freehandClosedPath = buildSmoothClosedPath(from: recordedPoints)
            }
        } else {
            lassoGlowLayer.isHidden = true
            lassoCoreLayer.isHidden = true
            dimLayer.path = CGPath(rect: bounds, transform: nil)
            dimLayer.fillColor = NSColor.black.withAlphaComponent(0.22).cgColor
            restorePromptBar()
            return
        }

        // Smoothly fade out the lightning/lasso trail as the panel opens
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.lassoGlowLayer.isHidden = true
            self?.lassoCoreLayer.isHidden = true
        }
        let strokeFade = CABasicAnimation(keyPath: "opacity")
        strokeFade.fromValue = lassoGlowLayer.opacity
        strokeFade.toValue = 0.0
        strokeFade.duration = AppleMotion.duration(0.42)
        strokeFade.timingFunction = AppleMotion.easeOut
        lassoGlowLayer.opacity = 0.0
        lassoGlowLayer.add(strokeFade, forKey: "fadeStroke")

        let coreFade = CABasicAnimation(keyPath: "opacity")
        coreFade.fromValue = lassoCoreLayer.opacity
        coreFade.toValue = 0.0
        coreFade.duration = AppleMotion.duration(0.42)
        coreFade.timingFunction = AppleMotion.easeOut
        lassoCoreLayer.opacity = 0.0
        lassoCoreLayer.add(coreFade, forKey: "fadeStroke")
        CATransaction.commit()

        let scaleX = CGFloat(screenshot.width) / bounds.width
        let scaleY = CGFloat(screenshot.height) / bounds.height
        let cropRect = CGRect(
            x: resolvedRect.origin.x * scaleX,
            y: resolvedRect.origin.y * scaleY,
            width: resolvedRect.width * scaleX,
            height: resolvedRect.height * scaleY
        ).integral

        guard let rawCropped = screenshot.cropping(to: cropRect) else { return }
        let finalCropped: CGImage
        if let freehandClosedPath {
            finalCropped = VisionAnalyzer.maskImage(rawCropped, withCanvasPath: freehandClosedPath, selectionRect: resolvedRect)
        } else {
            finalCropped = rawCropped
        }

        if !AppSettings.shared.hasShownFirstToolbarHint {
            AppSettings.shared.hasShownFirstToolbarHint = true
        }
        presentPreselectedRegion(rect: resolvedRect, cropped: finalCropped, freehandPath: freehandClosedPath)
    }

    private func presentPreselectedRegion(rect: CGRect, cropped: CGImage, freehandPath: CGPath? = nil) {
        selectionRect = rect
        croppedImage = cropped
        inPlaceTranslationView.isHidden = true

        // Hide bottom prompt capsule if visible
        if bottomSearchBar.alphaValue > 0.05 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = AppleMotion.duration(0.18)
                ctx.timingFunction = AppleMotion.easeIn
                bottomSearchBar.animator().alphaValue = 0.0
            }
        }

        // Dim cutout outside rounded or freehand spotlight
        let cornerR: CGFloat = min(18, min(rect.width, rect.height) * 0.32)
        activeSelectionCornerR = cornerR
        activeFreehandPath = freehandPath
        let selPath = freehandPath ?? CGPath(roundedRect: rect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
        activeSelectionPath = selPath

        let combined = CGMutablePath()
        combined.addRect(bounds)
        combined.addPath(selPath)
        dimLayer.path = combined
        let dimAnim = CABasicAnimation(keyPath: "fillColor")
        dimAnim.fromValue = dimLayer.presentation()?.value(forKey: "fillColor") ?? dimLayer.fillColor
        dimAnim.toValue = NSColor.black.withAlphaComponent(0.46).cgColor
        dimAnim.duration = AppleMotion.duration(0.36)
        dimAnim.timingFunction = AppleMotion.easeOut
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.46).cgColor
        dimLayer.add(dimAnim, forKey: "spotlightDim")

        // Tactile Spring Pop on selection (masked to exact freehand path if freehand)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionCropGroupLayer.mask = nil
        selectionGlowGroupLayer.mask = nil
        selectionPopLayer.frame = rect
        selectionPopLayer.contents = cropped
        selectionPopLayer.contentsGravity = .resizeAspectFill
        if let freehandPath {
            selectionPopLayer.cornerRadius = 0
            var translate = CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y)
            let shapeMask = CAShapeLayer()
            shapeMask.frame = CGRect(origin: .zero, size: rect.size)
            shapeMask.path = freehandPath.copy(using: &translate)
            shapeMask.fillColor = NSColor.white.cgColor
            selectionPopLayer.mask = shapeMask
        } else {
            selectionPopLayer.mask = nil
            selectionPopLayer.cornerRadius = cornerR
        }
        selectionPopLayer.isHidden = false
        CATransaction.commit()

        let pop = AppleMotion.spring(
            keyPath: "transform.scale",
            from: 0.96,
            to: 1.0,
            dampingRatio: 0.78,
            response: 0.34
        )
        selectionPopLayer.transform = CATransform3DIdentity
        selectionPopLayer.add(pop, forKey: "tactilePop")

        // Crisp Exterior-Only Glowing Blue Halo (masked strictly outside selection interior so text/subject stays 100% sharp)
        let targetSelOpacity = min(1.0, glowMultiplier)
        let exteriorCutout = CGMutablePath()
        exteriorCutout.addRect(bounds)
        exteriorCutout.addPath(selPath)
        let glowExteriorMask = CAShapeLayer()
        glowExteriorMask.frame = bounds
        glowExteriorMask.fillRule = .evenOdd
        glowExteriorMask.fillColor = NSColor.white.cgColor
        glowExteriorMask.path = exteriorCutout

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionGlowLayer.mask = glowExteriorMask
        if let freehandPath {
            selectionGlowLayer.updatePath(freehandPath, tightBounds: rect, glowPadding: 34, showInteriorAmbient: false)
        } else {
            selectionGlowLayer.updatePath(roundedRect: rect, cornerRadius: cornerR, glowPadding: 34)
        }
        selectionGlowLayer.updateAnimation(time: CACurrentMediaTime() - startTime, speed: 1.65)
        selectionGlowLayer.opacity = targetSelOpacity
        selectionGlowLayer.isHidden = false

        // Razor-sharp 1.25pt sky-blue frame hairline hugging the selection perimeter
        selectionFrameLayer.path = selPath
        selectionFrameLayer.opacity = 1.0
        selectionFrameLayer.isHidden = false
        CATransaction.commit()

        let glowFade = CABasicAnimation(keyPath: "opacity")
        glowFade.fromValue = 0.0
        glowFade.toValue = targetSelOpacity
        glowFade.duration = AppleMotion.duration(0.30)
        glowFade.timingFunction = AppleMotion.easeOut
        selectionGlowLayer.add(glowFade, forKey: "selGlowIn")

        let frameFade = CABasicAnimation(keyPath: "opacity")
        frameFade.fromValue = 0.0
        frameFade.toValue = 1.0
        frameFade.duration = AppleMotion.duration(0.24)
        frameFade.timingFunction = AppleMotion.easeOut
        selectionFrameLayer.add(frameFade, forKey: "selFrameIn")

        playSelectionShockwaveRipple(around: rect, cornerRadius: cornerR, freehandPath: freehandPath)
        animateCornerBrackets(around: rect, cornerRadius: cornerR, freehandPath: freehandPath)
        playScanSweep(inside: rect, cornerRadius: cornerR, freehandPath: freehandPath)

        // Soft sparkle shimmer burst around selection + calmer backdrop stars while reading results
        let showStars = AppSettings.shared.showAmbientStars && !AppSettings.shared.effectiveReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        twinkleContainer.opacity = showStars ? 0.45 : 0.0
        ambientSparkleEmitter.opacity = showStars ? 0.45 : 0.0
        selectionSparkleEmitter.emitterPosition = CGPoint(x: rect.midX, y: rect.midY)
        selectionSparkleEmitter.emitterSize = rect.size
        selectionSparkleEmitter.birthRate = showStars ? 1.0 : 0.0
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.selectionSparkleEmitter.birthRate = 0
        }

        CaptureHistoryStore.shared.record(cgImage: cropped, recognizedText: "", dominantHex: "")
        presentResultsSheet(for: rect, cropped: cropped)
    }

    private func restorePromptBar() {
        bottomSearchBar.wantsLayer = true
        if let pillLayer = bottomSearchBar.layer {
            let fromXform = pillLayer.presentation()?.transform ?? pillLayer.transform
            let spring = AppleMotion.spring(
                keyPath: "transform",
                from: fromXform,
                to: CATransform3DIdentity,
                dampingRatio: 0.80,
                response: 0.40
            )
            pillLayer.transform = CATransform3DIdentity
            pillLayer.add(spring, forKey: "pillRestore")
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.26)
            ctx.timingFunction = AppleMotion.easeOut
            bottomSearchBar.animator().alphaValue = 1.0
        }
    }

    private func playSelectionShockwaveRipple(around rect: CGRect, cornerRadius: CGFloat, freehandPath: CGPath?) {
        guard !AppSettings.shared.effectiveReduceMotion else { return }
        let ripplePath = freehandPath ?? CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionRippleLayer.bounds = bounds
        selectionRippleLayer.anchorPoint = CGPoint(x: rect.midX / max(1, bounds.width), y: rect.midY / max(1, bounds.height))
        selectionRippleLayer.position = CGPoint(x: rect.midX, y: rect.midY)
        selectionRippleLayer.path = ripplePath
        selectionRippleLayer.strokeColor = LuminousPalette.fullSpectrumLoopColors(phase: CACurrentMediaTime() - startTime)[1]
        selectionRippleLayer.opacity = 0.0
        selectionRippleLayer.isHidden = false
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.selectionRippleLayer.isHidden = true
        }
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.98
        scaleAnim.toValue = 1.09
        scaleAnim.duration = AppleMotion.duration(0.52)
        scaleAnim.timingFunction = AppleMotion.easeOut

        let fadeAnim = CAKeyframeAnimation(keyPath: "opacity")
        fadeAnim.values = [0.0, 0.78, 0.0]
        fadeAnim.keyTimes = [0.0, 0.18, 1.0]
        fadeAnim.duration = AppleMotion.duration(0.52)
        fadeAnim.timingFunctions = [AppleMotion.easeOut, AppleMotion.easeOut]

        let widthAnim = CABasicAnimation(keyPath: "lineWidth")
        widthAnim.fromValue = 3.2
        widthAnim.toValue = 0.8
        widthAnim.duration = AppleMotion.duration(0.52)
        widthAnim.timingFunction = AppleMotion.easeOut

        selectionRippleLayer.add(scaleAnim, forKey: "rippleScale")
        selectionRippleLayer.add(fadeAnim, forKey: "rippleFade")
        selectionRippleLayer.add(widthAnim, forKey: "rippleWidth")
        CATransaction.commit()
    }

    private func animateCornerBrackets(around rect: CGRect, cornerRadius: CGFloat, freehandPath: CGPath? = nil) {
        if freehandPath != nil {
            bracketsLayer.isHidden = true
            bracketsLayer.path = nil
            return
        }

        bracketsLayer.lineWidth = 2.6
        let arm = min(24.0, min(rect.width, rect.height) * 0.30)
        let r = min(cornerRadius, arm * 0.72)
        let path = CGMutablePath()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bracketsLayer.bounds = bounds
        bracketsLayer.anchorPoint = CGPoint(x: rect.midX / bounds.width, y: rect.midY / bounds.height)
        bracketsLayer.position = CGPoint(x: rect.midX, y: rect.midY)
        bracketsLayer.path = path
        bracketsLayer.opacity = 1.0
        bracketsLayer.isHidden = false
        CATransaction.commit()

        let snap = AppleMotion.spring(
            keyPath: "transform.scale",
            from: 1.11,
            to: 1.0,
            dampingRatio: 0.78,
            response: 0.34
        )
        bracketsLayer.transform = CATransform3DIdentity
        bracketsLayer.add(snap, forKey: "bracketSnap")

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.68
        pulse.duration = 0.90
        pulse.timingFunction = AppleMotion.easeInOut
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        bracketsLayer.add(pulse, forKey: "bracketPulse")
    }

    private func stopBracketPulse() {
        bracketsLayer.removeAnimation(forKey: "bracketPulse")
        selectionFrameLayer.removeAnimation(forKey: "framePulse")
        selectionFrameLayer.opacity = 1.0
        scanBeamGradient.removeAllAnimations()
        if !scanBeamContainer.isHidden {
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                self?.scanBeamContainer.isHidden = true
                self?.scanBeamContainer.opacity = 1.0
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = scanBeamContainer.opacity
            fade.toValue = 0.0
            fade.duration = AppleMotion.duration(0.26)
            fade.timingFunction = AppleMotion.easeOut
            scanBeamContainer.opacity = 0.0
            scanBeamContainer.add(fade, forKey: "scanFadeOut")
            CATransaction.commit()
        }
        guard !AppSettings.shared.effectiveReduceMotion else {
            bracketsLayer.opacity = 1.0
            return
        }
        let calmBreath = CABasicAnimation(keyPath: "opacity")
        calmBreath.fromValue = 0.96
        calmBreath.toValue = 0.78
        calmBreath.duration = 1.85
        calmBreath.timingFunction = AppleMotion.easeInOut
        calmBreath.autoreverses = true
        calmBreath.repeatCount = .infinity
        bracketsLayer.add(calmBreath, forKey: "bracketCalmBreath")
    }

    private func playScanSweep(inside rect: CGRect, cornerRadius: CGFloat, freehandPath: CGPath? = nil) {
        guard !AppSettings.shared.effectiveReduceMotion else { return }
        let beamW = max(72, rect.width * 0.72)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scanBeamContainer.frame = rect
        scanBeamContainer.opacity = 1.0
        if let freehandPath {
            scanBeamContainer.cornerRadius = 0
            var translate = CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y)
            let mask = CAShapeLayer()
            mask.frame = CGRect(origin: .zero, size: rect.size)
            mask.path = freehandPath.copy(using: &translate)
            mask.fillColor = NSColor.white.cgColor
            scanBeamContainer.mask = mask
        } else {
            scanBeamContainer.mask = nil
            scanBeamContainer.cornerRadius = cornerRadius
        }
        scanBeamGradient.frame = CGRect(x: -beamW, y: 0, width: beamW, height: rect.height)
        scanBeamContainer.isHidden = false
        CATransaction.commit()

        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -beamW * 0.55
        sweep.toValue = rect.width + beamW * 0.55
        sweep.duration = 2.15
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0.05, 0.55, 0.95)
        sweep.isRemovedOnCompletion = false
        scanBeamGradient.add(sweep, forKey: "scanSweep")

        if selectionFrameLayer.animation(forKey: "framePulse") == nil {
            let framePulse = CABasicAnimation(keyPath: "opacity")
            framePulse.fromValue = 0.72
            framePulse.toValue = 0.98
            framePulse.duration = 1.25
            framePulse.autoreverses = true
            framePulse.timingFunction = AppleMotion.easeInOut
            framePulse.repeatCount = .infinity
            selectionFrameLayer.add(framePulse, forKey: "framePulse")
        }
    }

    /// Ensures selection glow, hairline border, brackets, and crop never peek out behind an overlapping results sheet.
    private func updateSelectionMask(forSheetFrame sheetFrame: CGRect?) {
        guard let rect = selectionRect,
              let sheetFrame,
              sheetFrame.intersects(rect.insetBy(dx: -42, dy: -42)) else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            selectionCropGroupLayer.mask = nil
            selectionGlowGroupLayer.mask = nil
            CATransaction.commit()
            return
        }

        let paddedSheet = sheetFrame.insetBy(dx: -3, dy: -3)
        let cutout = CGMutablePath()
        cutout.addRect(bounds)
        cutout.addRoundedRect(in: paddedSheet, cornerWidth: 24, cornerHeight: 24)

        let cropMask = CAShapeLayer()
        cropMask.frame = bounds
        cropMask.fillRule = .evenOdd
        cropMask.fillColor = NSColor.white.cgColor
        cropMask.path = cutout

        let glowMask = CAShapeLayer()
        glowMask.frame = bounds
        glowMask.fillRule = .evenOdd
        glowMask.fillColor = NSColor.white.cgColor
        glowMask.path = cutout

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionCropGroupLayer.mask = cropMask
        selectionGlowGroupLayer.mask = glowMask
        CATransaction.commit()
    }

    // MARK: - Results Sheet Presentation & Lens Search

    private func presentResultsSheet(for rect: CGRect, cropped: CGImage) {
        let targetFrame = computeSheetFrame(avoiding: rect)
        let isSideDocked = targetFrame.height > targetFrame.width
        let expandedFrame = computeExpandedSheetFrame(from: targetFrame)

        let thumb = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        let sheet = GoogleResultsSheetView(
            thumbnail: thumb,
            croppedCGImage: cropped,
            isCompactWidth: isSideDocked,
            dockedFrame: targetFrame,
            expandedFrame: expandedFrame,
            allowedOrigins: { [weak self] size in
                guard let self else { return .zero }
                let minX = self.safeInsets.left
                let maxX = max(minX, self.bounds.width - self.safeInsets.right - size.width)
                let minY = self.safeInsets.top
                let maxY = max(minY, self.bounds.height - self.safeInsets.bottom - size.height)
                return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
            },
            onCopyImage: { [weak self] in
                self?.copyImageToClipboard(cropped)
                self?.onShowToast("Selected image copied to clipboard")
            },
            onSaveImage: { [weak self] in
                self?.saveImageToDesktop(cropped)
            },
            onPinImage: { [weak self] in
                guard let self else { return }
                let screenRect = self.window?.convertToScreen(rect) ?? rect
                PinnedCaptureManager.shared.pin(image: cropped, initialRect: screenRect, onToast: self.onShowToast)
                self.onShowToast("Pinned capture to screen")
            },
            onCopySubjectSticker: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.onShowToast("Lifting subject from background…")
                    if let lifted = await VisionAnalyzer.liftSubject(from: cropped) {
                        self.copyImageToClipboard(lifted)
                        self.onShowToast("Background removed — sticker copied!")
                    } else {
                        self.copyImageToClipboard(cropped)
                        self.onShowToast("No isolated foreground found — copied full selection")
                    }
                }
            },
            onTranslateInPlace: { [weak self] blocks in
                guard let self, let selRect = self.selectionRect else { return }
                Task { @MainActor in
                    let translated = await VisionAnalyzer.translateBlocks(blocks)
                    let cornerR = min(22, min(selRect.width, selRect.height) * 0.35)
                    self.inPlaceTranslationView.frame = selRect
                    self.inPlaceTranslationView.updateBlocks(translated, cornerRadius: cornerR)
                    self.inPlaceTranslationView.alphaValue = 0
                    self.inPlaceTranslationView.isHidden = false
                    await NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = AppleMotion.duration(0.24)
                        ctx.timingFunction = AppleMotion.easeOut
                        self.inPlaceTranslationView.animator().alphaValue = 1.0
                    }
                }
            },
            onShowToast: { [weak self] msg in
                self?.onShowToast(msg)
            },
            onOpenExternalURL: { [weak self] url in
                NSWorkspace.shared.open(url)
                self?.onDismiss()
            },
            onResultsReady: { [weak self] in
                self?.stopBracketPulse()
            },
            onFrameChanged: { [weak self] frame in
                self?.updateSelectionMask(forSheetFrame: frame)
            },
            onClose: { [weak self] in
                self?.onDismiss()
            }
        )

        sheet.frame = targetFrame
        sheet.layoutSubtreeIfNeeded()
        addSubview(sheet)
        self.resultsSheet = sheet
        updateSelectionMask(forSheetFrame: targetFrame)

        // Cognitive-mapped Apple spring: emerges spatially out of the circled object toward its dock slot
        sheet.wantsLayer = true
        sheet.alphaValue = 0
        if let sheetLayer = sheet.layer {
            let rawDX = rect.midX - targetFrame.midX
            let rawDY = rect.midY - targetFrame.midY
            let delta = CGPoint(
                x: max(-64, min(64, rawDX * 0.24)),
                y: max(-54, min(54, rawDY * 0.24))
            )
            let startXform = AppleMotion.centeredTransform(
                bounds: sheet.bounds,
                scale: 0.91,
                translation: delta
            )
            let spring = AppleMotion.spring(
                keyPath: "transform",
                from: startXform,
                to: CATransform3DIdentity,
                dampingRatio: 0.84,
                response: 0.48
            )
            sheetLayer.transform = CATransform3DIdentity
            sheetLayer.add(spring, forKey: "sheetSpring")
        }
        sheet.playEntranceCascade()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.28)
            ctx.timingFunction = AppleMotion.easeOut
            sheet.animator().alphaValue = 1.0
        }

        let isTextMode = currentMode == .textOnly
        let optionHeldOnRelease = NSEvent.modifierFlags.contains(.option)
        let afterAction = AppSettings.shared.afterSelectionAction
        let shouldAutoCopyOnly = optionHeldOnRelease || afterAction == .copyText
        let shouldAutoSearch = !shouldAutoCopyOnly && afterAction == .search

        searchTask = Task { [weak self] in
            let analysis = await VisionAnalyzer.analyze(image: cropped)
            guard !Task.isCancelled else { return }
            CaptureHistoryStore.shared.updateLatestText(analysis.cleanPreviewText, dominantHex: analysis.dominantHexColor)
            self?.resultsSheet?.updateVisionAnalysis(analysis)

            if shouldAutoCopyOnly {
                if !analysis.text.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(analysis.text, forType: .string)
                    self?.onShowToast(optionHeldOnRelease ? "Copied text (⌥)" : "Copied text")
                } else {
                    self?.onShowToast("No text found in selection")
                }
                self?.stopBracketPulse()
                if afterAction == .copyText || optionHeldOnRelease {
                    self?.onDismiss()
                }
                return
            }

            if isTextMode, !analysis.text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(analysis.text, forType: .string)
                self?.onShowToast("Copied recognized text to clipboard")
            }

            if analysis.isLowInformation {
                self?.stopBracketPulse()
                return
            }

            // Switch panel tab for Auto mode before uploading
            if let sheet = self?.resultsSheet {
                let targetIdx: Int
                switch AppSettings.shared.panelDefaultTab {
                case .answer: targetIdx = 0
                case .lens: targetIdx = 1
                case .auto: targetIdx = analysis.isMostlyText ? 0 : 1
                }
                sheet.applyInitialTab(targetIdx)
            }

            let needsLensNow = shouldAutoSearch || AppSettings.shared.panelDefaultTab == .lens || (AppSettings.shared.panelDefaultTab == .auto && !analysis.isMostlyText)
            guard needsLensNow else {
                self?.stopBracketPulse()
                return
            }

            let existingCookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            do {
                let upload = try await GoogleLensService.uploadImage(cropped, existingCookies: existingCookies)
                guard !Task.isCancelled else { return }
                self?.resultsSheet?.markLensUploadStarted()
                self?.resultsSheet?.loadLensResults(upload)
            } catch {
                guard !Task.isCancelled else { return }
                self?.resultsSheet?.showLensError(error.localizedDescription)
            }
        }
    }

    private func dismissResultsSheet() {
        guard let oldSheet = resultsSheet else { return }
        resultsSheet = nil
        updateSelectionMask(forSheetFrame: nil)
        oldSheet.wantsLayer = true
        let outDuration = AppleMotion.duration(0.20)
        if let oldLayer = oldSheet.layer {
            let endXform = AppleMotion.centeredTransform(bounds: oldSheet.bounds, scale: 0.94)
            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = oldLayer.presentation()?.transform ?? oldLayer.transform
            anim.toValue = endXform
            anim.duration = outDuration
            anim.timingFunction = AppleMotion.easeIn
            oldLayer.transform = endXform
            oldLayer.add(anim, forKey: "dismissSheet")
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = outDuration
            ctx.timingFunction = AppleMotion.easeIn
            oldSheet.animator().alphaValue = 0.0
        }, completionHandler: {
            Task { @MainActor in
                oldSheet.removeFromSuperview()
            }
        })
    }

    private func computeExpandedSheetFrame(from base: CGRect) -> CGRect {
        let usableLeft = safeInsets.left
        let usableRight = bounds.width - safeInsets.right
        let usableTop = safeInsets.top
        let usableBottom = bounds.height - safeInsets.bottom
        let usableWidth = max(440, usableRight - usableLeft)
        let usableHeight = max(480, usableBottom - usableTop)

        let targetW = min(usableWidth, max(base.width + 140, 680))
        let targetH = min(usableHeight, max(base.height + 240, usableHeight * 0.88))
        let x = max(usableLeft, min(usableRight - targetW, base.midX - targetW / 2))
        let y = max(usableTop, min(usableBottom - targetH, base.midY - targetH / 2))
        return CGRect(x: x, y: y, width: targetW, height: targetH)
    }

    private func computeSheetFrame(avoiding rect: CGRect) -> CGRect {
        let gap: CGFloat = 22
        let usableLeft = safeInsets.left
        let usableRight = bounds.width - safeInsets.right
        let usableTop = safeInsets.top
        let usableBottom = bounds.height - safeInsets.bottom
        let usableWidth = max(420, usableRight - usableLeft)
        let usableHeight = max(420, usableBottom - usableTop)

        let spaceBelow = usableBottom - rect.maxY - gap
        let spaceAbove = rect.minY - usableTop - gap
        let spaceRight = usableRight - rect.maxX - gap
        let spaceLeft = rect.minX - usableLeft - gap

        var candidates: [(rect: CGRect, score: CGFloat)] = []
        let sideHeight = min(620, usableHeight * 0.88)
        let vertWidth = min(760, usableWidth)

        if spaceRight >= 520 {
            let w = min(760, spaceRight)
            let rawY = rect.midY - sideHeight / 2
            let y = max(usableTop, min(usableBottom - sideHeight, rawY))
            let x = min(usableRight - w, rect.maxX + gap)
            let bonus: CGFloat = (w >= 720) ? 1.35 : 1.12
            candidates.append((CGRect(x: x, y: y, width: w, height: sideHeight), w * sideHeight * bonus))
        }

        if spaceLeft >= 520 {
            let w = min(760, spaceLeft)
            let rawY = rect.midY - sideHeight / 2
            let y = max(usableTop, min(usableBottom - sideHeight, rawY))
            let x = max(usableLeft, rect.minX - gap - w)
            let bonus: CGFloat = (w >= 720) ? 1.30 : 1.08
            candidates.append((CGRect(x: x, y: y, width: w, height: sideHeight), w * sideHeight * bonus))
        }

        if spaceBelow >= 360 {
            let h = min(620, spaceBelow)
            let rawX = rect.midX - vertWidth / 2
            let x = max(usableLeft, min(usableRight - vertWidth, rawX))
            let y = min(usableBottom - h, rect.maxY + gap)
            candidates.append((CGRect(x: x, y: y, width: vertWidth, height: h), vertWidth * h * 1.05))
        }

        if spaceAbove >= 360 {
            let h = min(620, spaceAbove)
            let rawX = rect.midX - vertWidth / 2
            let x = max(usableLeft, min(usableRight - vertWidth, rawX))
            let y = max(usableTop, rect.minY - gap - h)
            candidates.append((CGRect(x: x, y: y, width: vertWidth, height: h), vertWidth * h))
        }

        if let best = candidates.max(by: { $0.score < $1.score }) {
            return best.rect
        }

        let w = min(760, max(520, usableWidth * 0.90))
        let h = min(620, usableHeight * 0.88)
        let x = max(usableLeft, usableRight - w)
        let y = max(usableTop, usableBottom - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func copyImageToClipboard(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(pngData, forType: .png)
        if let tiff = nsImage.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    private func saveImageToDesktop(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "CircleSearch_\(formatter.string(from: Date())).png"

        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            let fileURL = desktop.appendingPathComponent(filename)
            do {
                try pngData.write(to: fileURL)
                onShowToast("Saved to Desktop/\(filename)")
            } catch {
                onShowToast("Could not save image: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Liquid Glass Google Prompt Capsule Bar (4-Mode Switcher + Esc Hint)

@MainActor
private final class GooglePromptCapsuleView: NSView, NSGestureRecognizerDelegate {
    private var mode: SelectionMode
    private let defaultOffset: CGPoint
    private let getCurrentOffset: () -> CGPoint
    private let applyOffset: (CGPoint) -> Void
    private let animateToOffset: (CGPoint) -> Void
    private let allowedOffsets: () -> CGRect
    private let onToggleMode: (SelectionMode) -> Void
    private let onOpenSettings: () -> Void
    private let onClose: () -> Void
    private var modeSegment: LiquidGlassSegmentedControl!
    private var promptLabel: NSTextField!

    private let glowPadding: CGFloat = 24
    private let backdropView: LiquidGlassSurfaceView = {
        let view = LiquidGlassSurfaceView(
            cornerRadius: 22,
            style: .regular,
            tintColor: NSColor(red: 0.042, green: 0.052, blue: 0.098, alpha: 0.82),
            lightTintColor: NSColor(white: 0.96, alpha: 0.86),
            interactive: true
        )
        view.horizonGlowIntensity = 0.78
        view.horizonPoolHeightFraction = 0.56
        view.horizonRimStrength = 1.15
        return view
    }()
    private let ambientBarGlowLayer = CAGradientLayer()
    private let glowRimLayer = GlowingRoundedBorderLayer(wideLine: 18, midLine: 6, coreLine: 1.1, coreOpacity: 0.34)

    private var dragEngine = DragInertiaEngine()
    private var pillTrackingArea: NSTrackingArea?

    init(
        mode: SelectionMode,
        defaultOffset: CGPoint,
        currentOffset: @escaping () -> CGPoint,
        setOffset: @escaping (CGPoint) -> Void,
        animateToOffset: @escaping (CGPoint) -> Void,
        allowedOffsets: @escaping () -> CGRect,
        onToggleMode: @escaping (SelectionMode) -> Void,
        onOpenSettings: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.mode = mode
        self.defaultOffset = defaultOffset
        self.getCurrentOffset = currentOffset
        self.applyOffset = setOffset
        self.animateToOffset = animateToOffset
        self.allowedOffsets = allowedOffsets
        self.onToggleMode = onToggleMode
        self.onOpenSettings = onOpenSettings
        self.onClose = onClose
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.32
        layer?.shadowRadius = 20
        layer?.shadowOffset = CGSize(width: 0, height: -6)

        ambientBarGlowLayer.type = .radial
        ambientBarGlowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        ambientBarGlowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        ambientBarGlowLayer.locations = [0.0, 0.42, 0.72, 1.0]
        layer?.addSublayer(ambientBarGlowLayer)
        layer?.addSublayer(glowRimLayer)

        setupUI()
        setupDragGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupDragGestures() {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePillPan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handlePillReset))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delegate = self
        addGestureRecognizer(doubleClick)
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        DragInertiaEngine.shouldAllowDragStart(in: self, event: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pillTrackingArea {
            removeTrackingArea(pillTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pillTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if backdropView.frame.contains(pt) {
            (dragEngine.isDragging ? NSCursor.closedHand : NSCursor.openHand).set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            dragEngine.popCursorIfNeeded()
        }
    }

    @objc private func handlePillPan(_ pan: NSPanGestureRecognizer) {
        dragEngine.handlePan(
            pan,
            in: superview,
            currentOrigin: getCurrentOffset,
            allowedBounds: allowedOffsets,
            applyOrigin: applyOffset,
            onGrabChanged: { [weak self] grabbed in
                self?.setGrabbedAppearance(grabbed)
            }
        )
    }

    @objc private func handlePillReset() {
        dragEngine.popCursorIfNeeded()
        dragEngine = DragInertiaEngine()
        animateToOffset(defaultOffset)
    }

    func updatePhysics(dt: CFTimeInterval) {
        if let next = dragEngine.step(origin: getCurrentOffset(), in: allowedOffsets(), dt: dt) {
            applyOffset(next)
        }
    }

    private func setGrabbedAppearance(_ grabbed: Bool) {
        layoutSubtreeIfNeeded()
        if let layer {
            AppleMotion.springScale(
                layer: layer,
                bounds: bounds,
                scale: grabbed ? 1.025 : 1.0,
                dampingRatio: grabbed ? 0.78 : 0.82,
                response: grabbed ? 0.26 : 0.32,
                key: "pillSpring"
            )
            layer.shadowOpacity = grabbed ? 0.45 : 0.32
            layer.shadowRadius = grabbed ? 26 : 20
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard backdropView.frame.contains(localPoint) else { return nil }
        return super.hitTest(point)
    }

    func updateGlow(time t: Double) {
        let gMult = AppSettings.shared.glowIntensity.opacityMultiplier
        let gFloat = CGFloat(gMult)
        let colors = LuminousPalette.gradientColors(phase: t * 0.62, alpha: 0.34 * gFloat)
        let midColors = LuminousPalette.gradientColors(phase: t * 0.62 + 1.0, alpha: 0.18 * gFloat)
        let outerColors = LuminousPalette.gradientColors(phase: t * 0.62 + 2.0, alpha: 0.05 * gFloat)
        ambientBarGlowLayer.colors = [colors[0], midColors[1], outerColors[2], NSColor.clear.cgColor]

        let dx = 0.14 * cos(t * 0.95)
        let dy = 0.06 * sin(t * 1.15)
        ambientBarGlowLayer.startPoint = CGPoint(x: 0.5 + dx, y: 0.5 + dy)
        let rawRim = (0.78 + 0.12 * sin(t * 2.0)) * Double(gMult)
        glowRimLayer.opacity = min(1.0, Float(rawRim))
        glowRimLayer.updateAnimation(time: t, speed: 1.25)

        backdropView.horizonWellView.wavePhase = t * 0.85
    }

    func syncMode(_ newMode: SelectionMode) {
        guard mode != newMode else { return }
        mode = newMode
        promptLabel?.stringValue = newMode.promptHint
        if let idx = SelectionMode.allCases.firstIndex(of: newMode) {
            modeSegment.setSelectedIndex(idx, animated: true)
        }
    }

    override func layout() {
        super.layout()
        ambientBarGlowLayer.frame = bounds
        glowRimLayer.frame = bounds
        let pillRect = bounds.insetBy(dx: glowPadding - 0.5, dy: glowPadding - 0.5)
        let r = max(12, pillRect.height / 2)
        glowRimLayer.updatePath(roundedRect: pillRect, cornerRadius: r)
    }

    private func setupUI() {
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdropView)

        NSLayoutConstraint.activate([
            backdropView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: glowPadding),
            backdropView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -glowPadding),
            backdropView.topAnchor.constraint(equalTo: topAnchor, constant: glowPadding),
            backdropView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -glowPadding)
        ])

        let brandBadge = LoopBrandLogoView(size: 22)
        brandBadge.translatesAutoresizingMaskIntoConstraints = false

        promptLabel = NSTextField(labelWithString: mode.promptHint)
        promptLabel.font = .systemFont(ofSize: 13.0, weight: .semibold)
        promptLabel.textColor = .labelColor

        let isFirstLaunchHint = !AppSettings.shared.hasShownFirstToolbarHint
        let hintString = isFirstLaunchHint
            ? "First launch: press 1–4 to switch modes, hold ⌥ for Box, Esc to cancel"
            : "Press 1–4 to switch mode • Esc to cancel"
        let escHintLabel = NSTextField(labelWithString: hintString)
        escHintLabel.font = .systemFont(ofSize: 10.5, weight: isFirstLaunchHint ? .semibold : .medium)
        escHintLabel.textColor = isFirstLaunchHint
            ? NSColor(red: 0.45, green: 0.82, blue: 1.0, alpha: 0.95)
            : .secondaryLabelColor

        let textStack = NSStackView(views: [promptLabel, escHintLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let modeOptions = SelectionMode.allCases.map {
            LiquidGlassSegmentedControl.Option(
                title: "\($0.shortcutBadge) \($0.shortTitle)",
                symbol: $0.symbolName
            )
        }
        let initialIdx = SelectionMode.allCases.firstIndex(of: mode) ?? 0
        modeSegment = LiquidGlassSegmentedControl(
            options: modeOptions,
            selectedIndex: initialIdx,
            height: 28,
            compact: true
        ) { [weak self] idx in
            guard let self, SelectionMode.allCases.indices.contains(idx) else { return }
            let chosen = SelectionMode.allCases[idx]
            self.mode = chosen
            self.promptLabel.stringValue = chosen.promptHint
            self.onToggleMode(chosen)
        }

        let settingsBtn = LiquidGlassButton(
            symbol: "gearshape",
            symbolPointSize: 11.5,
            symbolWeight: .medium,
            tooltip: "Settings (⌘,)",
            fixedSize: CGSize(width: 28, height: 28),
            style: .clear,
            foregroundColor: .secondaryLabelColor
        ) { [weak self] in
            self?.onOpenSettings()
        }
        settingsBtn.setAccessibilityLabel("Settings")

        let closeBtn = LiquidGlassButton(
            symbol: "xmark",
            symbolPointSize: 11.0,
            symbolWeight: .semibold,
            tooltip: "Close (Esc)",
            fixedSize: CGSize(width: 28, height: 28),
            style: .clear,
            foregroundColor: .secondaryLabelColor
        ) { [weak self] in
            self?.handleClose()
        }
        closeBtn.setAccessibilityLabel("Close overlay")

        let controlsGroup = LiquidGlassGroupView(spacing: 6)
        controlsGroup.stackView.addArrangedSubview(modeSegment)
        controlsGroup.stackView.addArrangedSubview(settingsBtn)
        controlsGroup.stackView.addArrangedSubview(closeBtn)

        let stack = NSStackView(views: [brandBadge, textStack, controlsGroup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        backdropView.contentContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: backdropView.contentContainer.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: backdropView.contentContainer.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: backdropView.contentContainer.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: backdropView.contentContainer.bottomAnchor, constant: -8)
        ])
    }

    private func handleClose() {
        onClose()
    }
}

// MARK: - Sheet Grab Handle & Bottom-Right Resize Handle

@MainActor
private final class SheetGrabHandleView: NSView {
    private let pillView = NSView()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isGrabbed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        toolTip = "Drag to move (double-click to reset)"

        pillView.wantsLayer = true
        pillView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.28).cgColor
        pillView.layer?.cornerRadius = 2.0
        pillView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillView)

        NSLayoutConstraint.activate([
            pillView.centerXAnchor.constraint(equalTo: centerXAnchor),
            pillView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillView.widthAnchor.constraint(equalToConstant: 42),
            pillView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setGrabbed(_ grabbed: Bool) {
        isGrabbed = grabbed
        updatePillAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updatePillAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updatePillAppearance()
    }

    override func cursorUpdate(with event: NSEvent) {
        (isGrabbed ? NSCursor.closedHand : NSCursor.openHand).set()
    }

    private func updatePillAppearance() {
        layoutSubtreeIfNeeded()
        guard let pillLayer = pillView.layer else { return }
        let targetScaleX: CGFloat = isGrabbed ? 1.32 : (isHovered ? 1.22 : 1.0)
        let targetAlpha: CGFloat = isGrabbed ? 0.78 : (isHovered ? 0.56 : 0.28)
        AppleMotion.springScale(
            layer: pillLayer,
            bounds: pillView.bounds,
            scaleX: targetScaleX,
            scaleY: 1.0,
            dampingRatio: 0.78,
            response: 0.26,
            key: "grabPillStretch"
        )
        pillLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(targetAlpha).cgColor
    }
}

@MainActor
private final class SheetResizeHandleView: NSView {
    var onDragDelta: ((CGSize) -> Void)?
    private var lastScreenPt: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        toolTip = "Drag to resize panel"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        lastScreenPt = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        if let prev = lastScreenPt {
            let dw = now.x - prev.x
            // AppKit screen Y grows upward, so dragging downward reduces Y -> increases height
            let dh = prev.y - now.y
            onDragDelta?(CGSize(width: dw, height: dh))
        }
        lastScreenPt = now
    }

    override func mouseUp(with event: NSEvent) {
        lastScreenPt = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.36).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        let concentricCenter = CGPoint(x: bounds.maxX - 24, y: bounds.minY + 24)
        ctx.addArc(
            center: concentricCenter,
            radius: 19.0,
            startAngle: -.pi * 0.34,
            endAngle: -.pi * 0.16,
            clockwise: false
        )
        ctx.strokePath()
    }
}

// MARK: - Clean Non-Glass Adaptive Surface (Flat Hairline + Appearance-Aware Fill)

@MainActor
private final class AdaptiveSurfaceView: NSView {
    private let darkFill: NSColor
    private let lightFill: NSColor
    private let darkBorder: NSColor
    private let lightBorder: NSColor
    private let strokeWidth: CGFloat
    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false

    var enableHoverHighlight: Bool = false {
        didSet {
            if oldValue != enableHoverHighlight {
                applyAppearance(animated: false)
            }
        }
    }

    var isFocused: Bool = false {
        didSet {
            if oldValue != isFocused {
                applyAppearance(animated: true)
            }
        }
    }

    init(
        cornerRadius: CGFloat,
        darkFill: NSColor,
        lightFill: NSColor,
        darkBorder: NSColor = .clear,
        lightBorder: NSColor = .clear,
        borderWidth: CGFloat = 0.75
    ) {
        self.darkFill = darkFill
        self.lightFill = lightFill
        self.darkBorder = darkBorder
        self.lightBorder = lightBorder
        self.strokeWidth = borderWidth
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = borderWidth
        applyAppearance(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        if enableHoverHighlight {
            applyAppearance(animated: true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        if enableHoverHighlight {
            applyAppearance(animated: true)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance(animated: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance(animated: false)
    }

    private func applyAppearance(animated: Bool = false) {
        let dark = isDarkAppearance
        let hovered = enableHoverHighlight && isHovered
        let targetBG: CGColor = {
            if isFocused {
                return (dark
                    ? NSColor.white.withAlphaComponent(0.085)
                    : NSColor.black.withAlphaComponent(0.065)
                ).cgColor
            } else if hovered {
                return (dark
                    ? NSColor.white.withAlphaComponent(0.095)
                    : NSColor.black.withAlphaComponent(0.068)
                ).cgColor
            } else {
                return (dark ? darkFill : lightFill).cgColor
            }
        }()
        let targetBorder: CGColor = {
            if isFocused {
                return NSColor(red: 0.30, green: 0.78, blue: 1.00, alpha: dark ? 0.56 : 0.68).cgColor
            } else if hovered {
                return NSColor(red: 0.30, green: 0.78, blue: 1.00, alpha: dark ? 0.34 : 0.42).cgColor
            } else {
                return (dark ? darkBorder : lightBorder).cgColor
            }
        }()

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(AppleMotion.duration(0.18))
            CATransaction.setAnimationTimingFunction(AppleMotion.easeOut)
            layer?.backgroundColor = targetBG
            layer?.borderColor = targetBorder
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.backgroundColor = targetBG
            layer?.borderColor = targetBorder
            CATransaction.commit()
        }
    }
}

// MARK: - Minimalist Embedded Results Sheet (Flat SS Hero + Action Row + Padded Web)

@MainActor
private final class GoogleResultsSheetView: NSView, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate, NSGestureRecognizerDelegate {
    private let thumbnail: NSImage
    private let croppedCGImage: CGImage
    private let isCompactWidth: Bool
    private let dockedFrame: CGRect
    private let expandedFrame: CGRect
    private let allowedOrigins: (CGSize) -> CGRect
    private let onCopyImage: () -> Void
    private let onSaveImage: () -> Void
    private let onPinImage: () -> Void
    private let onCopySubjectSticker: () -> Void
    private let onTranslateInPlace: ([RecognizedTextBlock]) -> Void
    private let onShowToast: (String) -> Void
    private let onOpenExternalURL: (URL) -> Void
    private let onResultsReady: () -> Void
    private let onFrameChanged: (CGRect) -> Void
    private let onClose: () -> Void

    private var baseLensURL: URL?
    private var currentText = ""
    private var currentPreviewText = ""
    private var currentBlocks: [RecognizedTextBlock] = []
    private var currentClassificationLabels: [String] = []
    private var currentURL: URL?
    private var currentHexColor = ""
    private var currentMathSolution: (expression: String, result: String)?
    private var currentAIExplanation = ""
    private var aiStreamingTask: Task<Void, Never>?
    private var isLowInfoSelection = false
    private var isExpanded = false

    private let sheetGlowLayer = GlowingRoundedBorderLayer(
        wideLine: 14,
        midLine: 5.0,
        coreLine: 1.0,
        coreOpacity: 0.36,
        fullSpectrumConic: true
    )
    private let backdropView: LiquidGlassSurfaceView = {
        let view = LiquidGlassSurfaceView(
            cornerRadius: 24,
            style: .regular,
            tintColor: NSColor(red: 0.024, green: 0.032, blue: 0.064, alpha: 0.93),
            lightTintColor: NSColor(white: 0.96, alpha: 0.93)
        )
        view.horizonGlowIntensity = 0.44
        view.horizonPoolHeightFraction = 0.26
        view.horizonRimStrength = 0.72
        return view
    }()
    private let grabHandleView = SheetGrabHandleView()
    private let resizeHandleView = SheetResizeHandleView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
    private var dragEngine = DragInertiaEngine()
    private var headerTrackingArea: NSTrackingArea?

    private var engineButton: LiquidGlassButton?
    private var resultsModeSegmented: LiquidGlassSegmentedControl!
    private var backButton: LiquidGlassButton!
    private var hasTriggeredLensUpload = false
    private var currentOcrConfidence: Double = 1.0
    private var aiSourceBadgeLabel: NSTextField!
    private var answerContextCard: LiquidGlassSurfaceView!
    private var answerContextLabel: NSTextField!
    private var currentTableTSV: String?
    private var currentTableCSV: String?
    private var currentDetectedEmails: [String] = []
    private var currentDetectedPhones: [String] = []
    private var currentDetectedDates: [Date] = []
    private var followUpField: NSTextField!
    private var addContactChip: LiquidGlassButton!
    private var addCalendarChip: LiquidGlassButton!
    private var copyTSVChip: LiquidGlassButton!
    private var webThemeButton: LiquidGlassButton!
    private var moreButton: LiquidGlassButton!
    private var topBarStack: NSView!
    private var heroRightStackRef: NSStackView!
    private var snippetRowRef: NSStackView!

    private var heroCard: NSView!
    private var searchBarContainer: AdaptiveSurfaceView!
    private var searchField: NSTextField!
    private var snippetPreviewLabel: NSTextField!
    private var snippetCopyButton: LiquidGlassButton!

    private var actionRowScroll: NSScrollView!
    private var chipsDocViewRef: NSView!
    private var actionChipsStack: NSStackView!
    private var searchActionBtn: LiquidGlassButton!
    private var translateActionBtn: LiquidGlassButton!
    private var copyTextChip: LiquidGlassButton!
    private var explainActionBtn: LiquidGlassButton!
    private var openLinkChip: LiquidGlassButton!
    private var mathResultChip: LiquidGlassButton!
    private var colorHexChip: LiquidGlassButton!

    private var aiAnswerCard: LiquidGlassSurfaceView!
    private var aiAnswerLabel: NSTextField!
    private var aiCopyButton: LiquidGlassButton!

    private var emptySelectionCard: LiquidGlassSurfaceView!
    private var errorStateCard: LiquidGlassSurfaceView!
    private var errorStateTitleLabel: NSTextField!

    private var webOuterCard: NSView!
    private var webClipViewRef: AdaptiveSurfaceView!
    private var webView: WKWebView!
    private var loadingOverlay: AdaptiveSurfaceView!
    private let loaderHorizonGlowLayer = CAGradientLayer()
    private let loaderHorizonPeakLayer = CAGradientLayer()
    private var loadingStatusLabel: NSTextField!
    private var searchOpticalOrb: BlueSearchOpticalOrbView?
    private var shimmerLayer = CAGradientLayer()
    private var loadingFallbackTask: Task<Void, Never>?

    private static func webColorSchemeScript(dark: Bool) -> String {
        if !dark {
            return """
            (function() {
                if (window.__ctsThemeObserver) {
                    window.__ctsThemeObserver.disconnect();
                    window.__ctsThemeObserver = null;
                }
                window.__ctsDarkEnabled = false;
                var st = document.getElementById('cts-dark-theme-style');
                if (st) st.remove();
                document.documentElement.style.colorScheme = 'light';
                var bgEls = document.querySelectorAll('[data-cts-dark-bg]');
                for (var i = 0; i < bgEls.length; i++) {
                    bgEls[i].style.removeProperty('background-color');
                    bgEls[i].style.removeProperty('border-color');
                    bgEls[i].removeAttribute('data-cts-dark-bg');
                }
                var imgEls = document.querySelectorAll('[data-cts-dark-bgi]');
                for (var k = 0; k < imgEls.length; k++) {
                    imgEls[k].style.removeProperty('background-image');
                    imgEls[k].style.removeProperty('background');
                    imgEls[k].removeAttribute('data-cts-dark-bgi');
                }
                var fgEls = document.querySelectorAll('[data-cts-dark-fg]');
                for (var j = 0; j < fgEls.length; j++) {
                    fgEls[j].style.removeProperty('color');
                    fgEls[j].removeAttribute('data-cts-dark-fg');
                }
            })();
            """
        }
        return """
        (function() {
            if (location.pathname.indexOf('/sorry') === 0) return;
            window.__ctsDarkEnabled = true;
            document.documentElement.style.colorScheme = 'dark';
            var st = document.getElementById('cts-dark-theme-style');
            if (!st) {
                st = document.createElement('style');
                st.id = 'cts-dark-theme-style';
                st.textContent = `
                    :root, html, body {
                        color-scheme: dark !important;
                        background-color: #0b0b0d !important;
                        color: #e8eaed !important;
                    }
                    code, pre, kbd, samp, tt {
                        background-color: rgba(32, 33, 36, 0.92) !important;
                        color: #e8eaed !important;
                        border-color: rgba(255, 255, 255, 0.14) !important;
                    }
                    mark, mark * {
                        background-color: rgba(255, 255, 255, 0.12) !important;
                        color: #e8eaed !important;
                        border-radius: 4px !important;
                    }
                    code *, pre *, kbd *, samp * {
                        background-color: transparent !important;
                        color: inherit !important;
                    }
                    table, th, td, blockquote, details, summary {
                        background-color: rgba(24, 25, 28, 0.92) !important;
                        color: #e8eaed !important;
                        border-color: rgba(255, 255, 255, 0.12) !important;
                    }
                    input:not([type="checkbox"]):not([type="radio"]):not([type="submit"]):not([type="button"]):not([type="range"]),
                    textarea {
                        background-color: transparent !important;
                        background-image: none !important;
                        color: #e8eaed !important;
                        caret-color: #e8eaed !important;
                        border-color: transparent !important;
                        box-shadow: none !important;
                        outline: none !important;
                    }
                    input::placeholder, textarea::placeholder {
                        color: #9aa0a6 !important;
                    }
                    a:not([role="button"]), a:not([role="button"]) * {
                        background-color: transparent !important;
                        background-image: none !important;
                    }
                `;
                (document.head || document.documentElement).appendChild(st);
            }
            function applyDarkPass() {
                if (!window.__ctsDarkEnabled || !document.body) return;
                var skipTags = { IMG:1, VIDEO:1, CANVAS:1, PICTURE:1, SOURCE:1, SVG:1, PATH:1, CIRCLE:1, RECT:1, POLYGON:1, SCRIPT:1, STYLE:1, LINK:1, META:1, NOSCRIPT:1, BR:1, HR:1, CODE:1, PRE:1, KBD:1, SAMP:1, MARK:1 };
                var nodes = [document.body];
                var all = document.body.getElementsByTagName('*');
                for (var k = 0; k < all.length; k++) { nodes.push(all[k]); }
                var vw = window.innerWidth || 420;
                var vh = window.innerHeight || 640;
                for (var i = 0; i < nodes.length; i++) {
                    var el = nodes[i];
                    if (skipTags[el.tagName]) continue;
                    var cs = window.getComputedStyle(el);
                    var bgi = cs.backgroundImage;
                    if (bgi && bgi.indexOf('gradient(') !== -1 && bgi.indexOf('url(') === -1 && /(255|248|249|250|241|243|244|238|232|229)/.test(bgi)) {
                        var hasMaskBg = (el.textContent || '').trim().length < 36 && el.querySelector('img, textarea, input') === null;
                        if (hasMaskBg) {
                            el.style.setProperty('background-image', 'linear-gradient(to bottom, rgba(11, 11, 13, 0), rgba(11, 11, 13, 0.96))', 'important');
                            el.setAttribute('data-cts-dark-bgi', '1');
                        }
                    }
                    var isMediaWrap = el.querySelector('img, picture, video') !== null
                        && (el.innerText || '').trim().length < 28
                        && el.querySelector('textarea, input, [role="tab"]') === null;
                    if (isMediaWrap && el.tagName !== 'BODY' && el.tagName !== 'MAIN') {
                        el.style.setProperty('background-color', 'transparent', 'important');
                        el.setAttribute('data-cts-dark-bg', '1');
                        continue;
                    }
                    var bg = cs.backgroundColor;
                    if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') {
                        var m = bg.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([\\d.]+))?\\)/);
                        if (m) {
                            var r = +m[1], g = +m[2], b = +m[3], a = m[4] !== undefined ? +m[4] : 1;
                            var hasBorder = parseFloat(cs.borderTopWidth) > 0.2 || parseFloat(cs.borderBottomWidth) > 0.2 || parseFloat(cs.borderLeftWidth) > 0.2 || parseFloat(cs.borderRightWidth) > 0.2;
                            if ((el.tagName === 'SPAN' || el.tagName === 'EM') && a > 0.15 && b > 135 && (b - r) > 38 && g < 195) {
                                var wrapsLink = el.querySelector('a') !== null || el.closest('a') !== null;
                                el.style.setProperty('background-color', wrapsLink ? 'transparent' : 'rgba(255, 255, 255, 0.10)', 'important');
                                el.setAttribute('data-cts-dark-bg', '1');
                            } else if (a > 0.12 && r > 155 && g > 155 && b > 155) {
                                var isRoot = (el.tagName === 'BODY' || el.tagName === 'MAIN');
                                el.style.setProperty('background-color', isRoot ? '#0b0b0d' : 'rgba(24, 25, 28, 0.94)', 'important');
                                if (hasBorder) {
                                    el.style.setProperty('border-color', 'rgba(255, 255, 255, 0.12)', 'important');
                                }
                                el.setAttribute('data-cts-dark-bg', '1');
                            } else if (a > 0.72 && Math.max(r, g, b) <= 52 && (Math.max(r, g, b) - Math.min(r, g, b)) <= 10) {
                                var rect = el.getBoundingClientRect();
                                if (rect.width >= vw * 0.84) {
                                    el.style.setProperty('background-color', '#0b0b0d', 'important');
                                    el.setAttribute('data-cts-dark-bg', '1');
                                }
                            }
                        }
                    }
                    var fg = cs.color;
                    if (fg) {
                        var fm = fg.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)/);
                        if (fm) {
                            var fr = +fm[1], fgv = +fm[2], fb = +fm[3];
                            if (Math.max(fr, fgv, fb) < 168) {
                                var isSecondary = Math.min(fr, fgv, fb) > 78;
                                el.style.setProperty('color', isSecondary ? '#9aa0a6' : '#e8eaed', 'important');
                                el.setAttribute('data-cts-dark-fg', '1');
                            }
                        }
                    }
                }
                // Keep bottom AI Mode composer dock clean and opaque so scrolled text never bleeds behind it
                var composers = document.querySelectorAll('textarea, input[type="text"], input:not([type])');
                for (var c = 0; c < composers.length; c++) {
                    var inp = composers[c];
                    var ir = inp.getBoundingClientRect();
                    if (ir.width < 120 || ir.bottom < vh * 0.52) continue;
                    var pill = inp.closest('form') || inp.parentElement;
                    var p = inp.parentElement;
                    for (var up = 0; up < 4 && p && p !== document.body; up++) {
                        var pr = p.getBoundingClientRect();
                        if (pr.width >= 200 && pr.height >= 42 && pr.height <= 170) {
                            pill = p;
                        }
                        p = p.parentElement;
                    }
                    if (pill) {
                        pill.style.setProperty('background-color', 'rgba(24, 25, 28, 0.96)', 'important');
                        pill.style.setProperty('border', '1px solid rgba(255, 255, 255, 0.14)', 'important');
                        pill.style.setProperty('border-radius', '20px', 'important');
                        pill.style.setProperty('box-shadow', '0 4px 18px rgba(0, 0, 0, 0.35)', 'important');
                        pill.style.setProperty('overflow', 'hidden', 'important');
                        pill.setAttribute('data-cts-keep', '1');
                    }
                    var dock = pill ? pill.parentElement : null;
                    while (dock && dock !== document.body) {
                        var dcs = window.getComputedStyle(dock);
                        if (dcs.position === 'fixed' || dcs.position === 'sticky') {
                            dock.style.setProperty('background-color', '#090e1a', 'important');
                            dock.style.setProperty('background-image', 'linear-gradient(to bottom, rgba(9, 14, 26, 0.92), #090e1a 16px)', 'important');
                            dock.style.setProperty('padding-top', '6px', 'important');
                            dock.setAttribute('data-cts-keep', '1');
                            break;
                        }
                        dock = dock.parentElement;
                    }
                }
            }
            applyDarkPass();
            if (!window.__ctsThemeObserver && document.body) {
                var queued = false;
                window.__ctsThemeObserver = new MutationObserver(function() {
                    if (!window.__ctsDarkEnabled || queued) return;
                    queued = true;
                    requestAnimationFrame(function() {
                        queued = false;
                        applyDarkPass();
                    });
                });
                window.__ctsThemeObserver.observe(document.body, { childList: true, subtree: true });
            }
        })();
        """
    }

    private var isEffectiveDarkMode: Bool {
        switch AppSettings.shared.webResultsTheme {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            switch AppSettings.shared.theme {
            case .dark:
                return true
            case .light:
                return false
            case .system:
                return effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }
    }

    func syncWebViewAppearance() {
        guard webView != nil else { return }
        let dark = isEffectiveDarkMode
        webView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = dark
            ? NSColor(white: 0.07, alpha: 1.0)
            : NSColor(white: 0.98, alpha: 1.0)
    }

    private func updateWebThemeButtonUI(dark: Bool) {
        _ = dark
    }

    func prepareForClose() {
        loadingFallbackTask?.cancel()
        aiStreamingTask?.cancel()
        stopLoaderAnimations()
        webView?.stopLoading()
        webView?.evaluateJavaScript(
            """
            if(window.__ctsThemeObserver){window.__ctsThemeObserver.disconnect();window.__ctsThemeObserver=null;}
            if(window.__ctsCleanObserver){window.__ctsCleanObserver.disconnect();window.__ctsCleanObserver=null;}
            """,
            completionHandler: nil
        )
        webView?.loadHTMLString("", baseURL: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        syncWebViewAppearance()
    }

    private static let googleLensCleanUpScript = """
    (function() {
        if (location.pathname.indexOf('/sorry') === 0) return;
        var st = document.getElementById('cts-clean-style');
        if (!st) {
            st = document.createElement('style');
            st.id = 'cts-clean-style';
            st.textContent = `
                header, #searchform,
                #sfcnt, #tophf,
                div[data-hveid] input[aria-label*="Add to your search"],
                div[jscontroller] > div > a[aria-label="Google"],
                div[aria-label="Add to your search"],
                hr, [role="separator"] {
                    display: none !important;
                }
                html, body {
                    width: 100% !important;
                    max-width: 100% !important;
                    padding-top: 10px !important;
                    padding-bottom: 14px !important;
                    margin-top: 0 !important;
                    overflow-x: hidden !important;
                    box-sizing: border-box !important;
                }
                main, [role="main"], c-wiz, form {
                    max-width: 100% !important;
                    min-width: 0 !important;
                    box-sizing: border-box !important;
                }
                img, video, svg {
                    max-width: 100% !important;
                }
                c-wiz img:not(a[href] img), [role="main"] img:not(a[href] img) {
                    object-fit: contain !important;
                }
                div[data-attrid], div[data-hveid], section, c-wiz {
                    margin-bottom: 4px !important;
                }
                a, [role="button"], button, div[data-hveid] > div, g-card, .g {
                    transition: transform 0.20s cubic-bezier(0.22, 1, 0.36, 1),
                                box-shadow 0.22s ease,
                                background-color 0.18s ease,
                                border-color 0.18s ease,
                                opacity 0.18s ease !important;
                }
                a img {
                    transition: transform 0.24s cubic-bezier(0.22, 1, 0.36, 1),
                                filter 0.20s ease !important;
                }
                a:hover img {
                    transform: scale(1.028) !important;
                    filter: brightness(1.06) !important;
                }
                g-card:hover, div[jsaction] a:hover {
                    border-color: rgba(74, 194, 255, 0.34) !important;
                }
                button:hover, [role="button"]:hover {
                    opacity: 0.94 !important;
                }
                @media (prefers-reduced-motion: reduce) {
                    a, [role="button"], button, a img, g-card, .g {
                        transition: none !important;
                    }
                    a:hover img {
                        transform: none !important;
                    }
                }
            `;
            (document.head || document.documentElement).appendChild(st);
        }
        function hasVisibleInteractiveOrMedia(root) {
            var items = root.querySelectorAll('img, svg, canvas, video, input, textarea, [role="tab"], [role="tablist"], [role="button"], button, a');
            for (var m = 0; m < items.length; m++) {
                var item = items[m];
                var ics = window.getComputedStyle(item);
                if (ics.display === 'none' || ics.visibility === 'hidden' || parseFloat(ics.opacity) === 0) continue;
                var ir = item.getBoundingClientRect();
                if (ir.width > 2 && ir.height > 2) return true;
            }
            return false;
        }
        function runCleanupPass() {
            if (location.pathname.indexOf('/sorry') === 0 || !document.body) return;
            // 1. Hide any top search chrome without breaking bottom AI Mode composer forms
            var walker = document.querySelectorAll('input, span, div, form[action="/search"], [role="search"]');
            for (var i = 0; i < walker.length; i++) {
                var el = walker[i];
                if (el.getAttribute('data-cts-keep') === '1' || el.querySelector('textarea')) continue;
                if (el.tagName === 'FORM' || el.getAttribute('role') === 'search') {
                    var fr = el.getBoundingClientRect();
                    if (fr.top < 170 && fr.height < 130) {
                        el.style.setProperty('display', 'none', 'important');
                    }
                    continue;
                }
                var txt = (el.getAttribute('placeholder') || el.getAttribute('aria-label') || '').toLowerCase();
                if (txt.indexOf('add to your search') !== -1) {
                    var box = el.closest('form') || el.closest('[role="search"]') || el.parentElement;
                    if (box && box.offsetHeight < 120 && !box.querySelector('textarea')) {
                        box.style.setProperty('display', 'none', 'important');
                    }
                }
            }
            // 2. Collapse empty orphaned top header chrome without clipping real headings
            var allDivs = document.querySelectorAll('div, section, nav');
            for (var j = 0; j < allDivs.length; j++) {
                var d = allDivs[j];
                if (d.getAttribute('data-cts-keep') === '1') continue;
                var style = window.getComputedStyle(d);
                if (style.position === 'fixed' || style.position === 'sticky' || style.overflowY === 'auto' || style.overflowY === 'scroll') continue;
                var rect = d.getBoundingClientRect();
                var textTrim = (d.innerText || '').trim();
                if (rect.top >= -12 && rect.top < 140 && rect.height >= 10 && rect.height <= 180) {
                    if (textTrim.length === 0 && !hasVisibleInteractiveOrMedia(d)) {
                        d.style.setProperty('display', 'none', 'important');
                        d.style.setProperty('height', '0px', 'important');
                        d.style.setProperty('min-height', '0px', 'important');
                        d.style.setProperty('margin', '0px', 'important');
                        d.style.setProperty('padding', '0px', 'important');
                        d.style.setProperty('border', 'none', 'important');
                        continue;
                    }
                }
                if (d.children.length === 0 && (d.textContent || '').trim() === '' && d.offsetHeight >= 14 && d.offsetHeight <= 150) {
                    var bg = style.backgroundImage;
                    if (!bg || bg === 'none') {
                        d.style.setProperty('display', 'none', 'important');
                        d.style.setProperty('height', '0px', 'important');
                        d.style.setProperty('margin', '0px', 'important');
                        d.style.setProperty('padding', '0px', 'important');
                        continue;
                    }
                }
                var hasHeading = d.querySelector('h1, h2, h3, [role="heading"]') !== null;
                if (!hasHeading && rect.top >= -4 && rect.top < 120) {
                    if (parseInt(style.paddingTop, 10) > 28) {
                        d.style.setProperty('padding-top', '10px', 'important');
                    }
                    if (parseInt(style.marginTop, 10) > 24) {
                        d.style.setProperty('margin-top', '4px', 'important');
                    }
                }
                if (parseInt(style.marginBottom, 10) > 16) {
                    d.style.setProperty('margin-bottom', '6px', 'important');
                }
                if (parseInt(style.paddingBottom, 10) > 20 && d.offsetHeight < 220) {
                    d.style.setProperty('padding-bottom', '6px', 'important');
                }
            }
            var mainWrap = document.querySelector('main, [role="main"], #main, #cnt, #rcnt');
            if (mainWrap) {
                var mcs = window.getComputedStyle(mainWrap);
                if (parseInt(mcs.paddingTop, 10) > 20) {
                    mainWrap.style.setProperty('padding-top', '10px', 'important');
                }
                if (parseInt(mcs.marginTop, 10) > 18) {
                    mainWrap.style.setProperty('margin-top', '2px', 'important');
                }
            }
        }
        runCleanupPass();
        if (!window.__ctsCleanObserver && document.body) {
            var cleanQueued = false;
            window.__ctsCleanObserver = new MutationObserver(function() {
                if (cleanQueued) return;
                cleanQueued = true;
                requestAnimationFrame(function() {
                    cleanQueued = false;
                    runCleanupPass();
                });
            });
            window.__ctsCleanObserver.observe(document.body, { childList: true, subtree: true });
        }
    })();
    """

    init(
        thumbnail: NSImage,
        croppedCGImage: CGImage,
        isCompactWidth: Bool,
        dockedFrame: CGRect,
        expandedFrame: CGRect,
        allowedOrigins: @escaping (CGSize) -> CGRect,
        onCopyImage: @escaping () -> Void,
        onSaveImage: @escaping () -> Void,
        onPinImage: @escaping () -> Void,
        onCopySubjectSticker: @escaping () -> Void,
        onTranslateInPlace: @escaping ([RecognizedTextBlock]) -> Void,
        onShowToast: @escaping (String) -> Void,
        onOpenExternalURL: @escaping (URL) -> Void,
        onResultsReady: @escaping () -> Void,
        onFrameChanged: @escaping (CGRect) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.thumbnail = thumbnail
        self.croppedCGImage = croppedCGImage
        self.isCompactWidth = isCompactWidth
        self.dockedFrame = dockedFrame
        self.expandedFrame = expandedFrame
        self.allowedOrigins = allowedOrigins
        self.onCopyImage = onCopyImage
        self.onSaveImage = onSaveImage
        self.onPinImage = onPinImage
        self.onCopySubjectSticker = onCopySubjectSticker
        self.onTranslateInPlace = onTranslateInPlace
        self.onShowToast = onShowToast
        self.onOpenExternalURL = onOpenExternalURL
        self.onResultsReady = onResultsReady
        self.onFrameChanged = onFrameChanged
        self.onClose = onClose
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowRadius = 28
        layer?.shadowOffset = CGSize(width: 0, height: -8)

        setupUI()
        sheetGlowLayer.opacity = 0.78
        sheetGlowLayer.zPosition = 20
        layer?.addSublayer(sheetGlowLayer)
        setupSheetDragGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        aiStreamingTask?.cancel()
        loadingFallbackTask?.cancel()
    }

    func playEntranceCascade() {
        guard !AppSettings.shared.effectiveReduceMotion else { return }
        let sections: [NSView?] = [topBarStack, heroCard, actionRowScroll, webOuterCard]
        for (idx, item) in sections.compactMap({ $0 }).enumerated() {
            let delay = Double(idx) * 0.035
            let isWeb = (item === webOuterCard)
            AppleMotion.kineticHorizonSpring(
                view: item,
                fromTilt: isWeb ? 0.0 : ((idx % 2 == 0) ? -0.014 : 0.012),
                fromY: isWeb ? 10.0 : 12.0,
                fromScale: isWeb ? 0.980 : 0.970,
                dampingRatio: 0.88,
                response: 0.36,
                delay: delay,
                key: "cascadeHorizon_\(idx)"
            )
        }
    }

    private func setupSheetDragGestures() {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handleSheetPan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleSheetReset))
        doubleClick.numberOfClicksRequired = 2
        grabHandleView.addGestureRecognizer(doubleClick)

        resizeHandleView.onDragDelta = { [weak self] delta in
            guard let self else { return }
            let maxAllowedW = max(920, (self.superview?.bounds.width ?? 1440) - 24)
            let maxAllowedH = max(760, (self.superview?.bounds.height ?? 960) - 48)
            let newW = max(520, min(maxAllowedW, self.frame.width + delta.width))
            let newH = max(420, min(maxAllowedH, self.frame.height + delta.height))
            let newOriginY = self.frame.maxY - newH
            let allowed = self.allowedOrigins(CGSize(width: newW, height: newH))
            let clampedX = max(allowed.minX, min(allowed.maxX, self.frame.origin.x))
            let clampedY = max(allowed.minY, min(allowed.maxY, newOriginY))
            let nextFrame = CGRect(x: clampedX, y: clampedY, width: newW, height: newH)
            self.frame = nextFrame
            self.onFrameChanged(nextFrame)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        DragInertiaEngine.shouldAllowDragStart(in: self, event: event, excludingRoots: [webView, resizeHandleView])
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            dragEngine.popCursorIfNeeded()
        }
    }

    @objc private func handleSheetPan(_ pan: NSPanGestureRecognizer) {
        dragEngine.handlePan(
            pan,
            in: superview,
            currentOrigin: { frame.origin },
            allowedBounds: { allowedOrigins(bounds.size) },
            applyOrigin: { [weak self] origin in
                guard let self else { return }
                self.frame.origin = origin
                self.onFrameChanged(self.frame)
            },
            onGrabChanged: { [weak self] grabbed in
                self?.setGrabbedAppearance(grabbed)
            }
        )
    }

    @objc private func handleSheetReset() {
        dragEngine.popCursorIfNeeded()
        dragEngine = DragInertiaEngine()
        isExpanded = false
        onFrameChanged(dockedFrame)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.36)
            ctx.timingFunction = AppleMotion.easeInOut
            animator().frame = dockedFrame
        }
    }

    private func toggleExpandSheet(forceExpand: Bool = false) {
        if forceExpand && isExpanded { return }
        isExpanded.toggle()
        let target = isExpanded ? expandedFrame : dockedFrame
        onFrameChanged(target)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.38)
            ctx.timingFunction = AppleMotion.easeOut
            animator().frame = target
        }
    }

    func updatePhysics(dt: CFTimeInterval) {
        if let next = dragEngine.step(origin: frame.origin, in: allowedOrigins(bounds.size), dt: dt) {
            frame.origin = next
            onFrameChanged(frame)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let headerTrackingArea {
            removeTrackingArea(headerTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        headerTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        if DragInertiaEngine.shouldAllowDragStart(in: self, event: event, excludingRoots: [webView, resizeHandleView]) {
            (dragEngine.isDragging ? NSCursor.closedHand : NSCursor.openHand).set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    private func setGrabbedAppearance(_ grabbed: Bool) {
        grabHandleView.setGrabbed(grabbed)
        layoutSubtreeIfNeeded()
        if let layer {
            AppleMotion.springScale(
                layer: layer,
                bounds: bounds,
                scale: grabbed ? 1.010 : 1.0,
                dampingRatio: grabbed ? 0.80 : 0.82,
                response: grabbed ? 0.26 : 0.34,
                key: "sheetSpring"
            )
            layer.shadowOpacity = grabbed ? 0.54 : 0.42
            layer.shadowRadius = grabbed ? 32 : 26
            layer.shadowOffset = CGSize(width: 0, height: grabbed ? -12 : -8)
        }
    }

    func updateGlow(time t: Double) {
        let gMult = AppSettings.shared.glowIntensity.opacityMultiplier
        let effective = AppSettings.shared.effectiveReduceMotion ? gMult * 0.55 : gMult
        let isSearching = !loadingOverlay.isHidden
        let sheetBreathe = 0.90 + 0.10 * sin(t * 1.9)
        let targetSheetAlpha = isSearching ? 0.58 : 0.34
        sheetGlowLayer.opacity = min(1.0, Float(sheetBreathe * targetSheetAlpha * effective))
        sheetGlowLayer.updateAnimation(time: t, speed: 1.05)

        backdropView.horizonWellView.isSearchPulseActive = false
        backdropView.horizonWellView.wavePhase = t * 0.60
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        searchBarContainer.isFocused = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        searchBarContainer.isFocused = false
    }

    private func setupUI() {
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdropView)

        NSLayoutConstraint.activate([
            backdropView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1.5),
            backdropView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1.5),
            backdropView.topAnchor.constraint(equalTo: topAnchor, constant: 1.5),
            backdropView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1.5)
        ])

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        backdropView.contentContainer.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: backdropView.contentContainer.leadingAnchor, constant: 10),
            rootStack.trailingAnchor.constraint(equalTo: backdropView.contentContainer.trailingAnchor, constant: -10),
            rootStack.topAnchor.constraint(equalTo: backdropView.contentContainer.topAnchor, constant: 8),
            rootStack.bottomAnchor.constraint(equalTo: backdropView.contentContainer.bottomAnchor, constant: -10)
        ])

        // 1. Clean Top Bar: Engine + Back on Left, True-Centered Grab Pill, Unified 26pt Controls on Right
        backButton = makeGlassCircleButton(symbol: "chevron.left", pointSize: 10.5, weight: .semibold, tooltip: "Back") { [weak self] in
            self?.handleBack()
        }
        backButton.isHidden = true
        backButton.setAccessibilityLabel("Back")

        let initialTabIndex: Int = (AppSettings.shared.panelDefaultTab == .answer) ? 0 : 1
        resultsModeSegmented = LiquidGlassSegmentedControl(
            options: [
                .init(title: "Answer", symbol: "sparkles"),
                .init(title: "Lens", symbol: "globe")
            ],
            selectedIndex: initialTabIndex,
            height: 24,
            compact: true
        ) { [weak self] idx in
            self?.handleResultsModeChanged(idx)
        }

        let leftTopGroup = LiquidGlassGroupView(spacing: 5)
        leftTopGroup.stackView.addArrangedSubview(backButton)
        leftTopGroup.stackView.addArrangedSubview(resultsModeSegmented)

        let pinBtn = makeGlassCircleButton(symbol: "pin.fill", pointSize: 10.0, weight: .medium, tooltip: "Pin to Screen (⌘P)") { [weak self] in
            self?.onPinImage()
        }
        pinBtn.setAccessibilityLabel("Pin to Screen")

        let copyBtn = makeGlassCircleButton(symbol: "doc.on.doc", pointSize: 10.0, weight: .medium, tooltip: "Copy Text or Image (⌘C)") { [weak self] in
            self?.triggerKeyboardCopy()
        }
        copyBtn.setAccessibilityLabel("Copy Text or Image")

        moreButton = makeGlassCircleButton(symbol: "ellipsis", pointSize: 11.0, weight: .bold, tooltip: "More Actions (Sticker, Save, Expand, Browser)") { [weak self] in
            self?.showMoreActionsMenu()
        }
        moreButton.setAccessibilityLabel("More Actions")

        let closeBtn = makeGlassCircleButton(symbol: "xmark", pointSize: 10.0, weight: .semibold, tooltip: "Close (Esc)") { [weak self] in
            self?.handleClose()
        }
        closeBtn.setAccessibilityLabel("Close")

        let actionsGroup = LiquidGlassGroupView(spacing: 4)
        actionsGroup.stackView.addArrangedSubview(pinBtn)
        actionsGroup.stackView.addArrangedSubview(copyBtn)
        actionsGroup.stackView.addArrangedSubview(moreButton)
        actionsGroup.stackView.addArrangedSubview(closeBtn)

        let topBarContainer = NSView()
        topBarContainer.wantsLayer = true
        topBarContainer.translatesAutoresizingMaskIntoConstraints = false
        topBarContainer.heightAnchor.constraint(equalToConstant: 26).isActive = true

        leftTopGroup.translatesAutoresizingMaskIntoConstraints = false
        actionsGroup.translatesAutoresizingMaskIntoConstraints = false
        grabHandleView.translatesAutoresizingMaskIntoConstraints = false

        topBarContainer.addSubview(leftTopGroup)
        topBarContainer.addSubview(grabHandleView)
        topBarContainer.addSubview(actionsGroup)

        NSLayoutConstraint.activate([
            leftTopGroup.leadingAnchor.constraint(equalTo: topBarContainer.leadingAnchor),
            leftTopGroup.centerYAnchor.constraint(equalTo: topBarContainer.centerYAnchor),

            actionsGroup.trailingAnchor.constraint(equalTo: topBarContainer.trailingAnchor),
            actionsGroup.centerYAnchor.constraint(equalTo: topBarContainer.centerYAnchor),

            leftTopGroup.trailingAnchor.constraint(lessThanOrEqualTo: actionsGroup.leadingAnchor, constant: -8),

            grabHandleView.centerXAnchor.constraint(equalTo: topBarContainer.centerXAnchor),
            grabHandleView.centerYAnchor.constraint(equalTo: topBarContainer.centerYAnchor),
            grabHandleView.widthAnchor.constraint(equalToConstant: 44),
            grabHandleView.heightAnchor.constraint(equalToConstant: 22)
        ])

        topBarStack = topBarContainer
        rootStack.addArrangedSubview(topBarContainer)
        topBarContainer.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        // 2. Clean Flat Screenshot Preview + Matte Search Header (Zero Nested Liquid Glass)
        heroCard = NSView()
        heroCard.wantsLayer = true
        heroCard.translatesAutoresizingMaskIntoConstraints = false

        let thumbShadowHost = NSView()
        thumbShadowHost.wantsLayer = true
        thumbShadowHost.layer?.masksToBounds = false
        thumbShadowHost.layer?.shadowColor = NSColor.black.cgColor
        thumbShadowHost.layer?.shadowOpacity = 0.24
        thumbShadowHost.layer?.shadowRadius = 6
        thumbShadowHost.layer?.shadowOffset = CGSize(width: 0, height: -2)
        thumbShadowHost.translatesAutoresizingMaskIntoConstraints = false
        thumbShadowHost.widthAnchor.constraint(equalToConstant: 66).isActive = true
        thumbShadowHost.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let thumbContainer = AdaptiveSurfaceView(
            cornerRadius: 10,
            darkFill: NSColor.white.withAlphaComponent(0.04),
            lightFill: NSColor.black.withAlphaComponent(0.04),
            darkBorder: NSColor.white.withAlphaComponent(0.12),
            lightBorder: NSColor.black.withAlphaComponent(0.09),
            borderWidth: 0.75
        )
        thumbContainer.translatesAutoresizingMaskIntoConstraints = false
        thumbShadowHost.addSubview(thumbContainer)
        NSLayoutConstraint.activate([
            thumbContainer.leadingAnchor.constraint(equalTo: thumbShadowHost.leadingAnchor),
            thumbContainer.trailingAnchor.constraint(equalTo: thumbShadowHost.trailingAnchor),
            thumbContainer.topAnchor.constraint(equalTo: thumbShadowHost.topAnchor),
            thumbContainer.bottomAnchor.constraint(equalTo: thumbShadowHost.bottomAnchor)
        ])

        let thumbView = NSImageView(image: thumbnail)
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        thumbContainer.addSubview(thumbView)
        NSLayoutConstraint.activate([
            thumbView.leadingAnchor.constraint(equalTo: thumbContainer.leadingAnchor),
            thumbView.trailingAnchor.constraint(equalTo: thumbContainer.trailingAnchor),
            thumbView.topAnchor.constraint(equalTo: thumbContainer.topAnchor),
            thumbView.bottomAnchor.constraint(equalTo: thumbContainer.bottomAnchor)
        ])

        searchBarContainer = AdaptiveSurfaceView(
            cornerRadius: 11,
            darkFill: NSColor.white.withAlphaComponent(0.06),
            lightFill: NSColor.black.withAlphaComponent(0.045),
            darkBorder: NSColor.white.withAlphaComponent(0.11),
            lightBorder: NSColor.black.withAlphaComponent(0.09),
            borderWidth: 0.75
        )
        searchBarContainer.enableHoverHighlight = true
        searchBarContainer.translatesAutoresizingMaskIntoConstraints = false
        searchBarContainer.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let searchIcon = NSImageView()
        let searchIconConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(searchIconConfig)
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.setContentHuggingPriority(.required, for: .horizontal)

        searchField = NSTextField()
        searchField.placeholderString = "Add to your search or ask AI..."
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 12.5, weight: .regular)
        searchField.textColor = .labelColor
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(handleMultisearchSubmit)
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let submitBtn = LiquidGlassButton(
            symbol: "arrow.right",
            symbolPointSize: 11.5,
            symbolWeight: .bold,
            tooltip: "Search",
            fixedSize: CGSize(width: 24, height: 24),
            style: .clear,
            tintColor: NSColor(red: 0.10, green: 0.42, blue: 0.92, alpha: 0.72),
            lightTintColor: NSColor(red: 0.14, green: 0.48, blue: 0.96, alpha: 0.86),
            foregroundColor: .white
        ) { [weak self] in
            self?.handleMultisearchSubmit()
        }
        submitBtn.setContentHuggingPriority(.required, for: .horizontal)

        let searchInputStack = NSStackView(views: [searchIcon, searchField, submitBtn])
        searchInputStack.orientation = .horizontal
        searchInputStack.alignment = .centerY
        searchInputStack.spacing = 7
        searchInputStack.translatesAutoresizingMaskIntoConstraints = false
        searchBarContainer.addSubview(searchInputStack)
        NSLayoutConstraint.activate([
            searchInputStack.leadingAnchor.constraint(equalTo: searchBarContainer.leadingAnchor, constant: 10),
            searchInputStack.trailingAnchor.constraint(equalTo: searchBarContainer.trailingAnchor, constant: -6),
            searchInputStack.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor)
        ])

        snippetPreviewLabel = NSTextField(labelWithString: "Analyzing selection…")
        snippetPreviewLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        snippetPreviewLabel.textColor = .secondaryLabelColor
        snippetPreviewLabel.usesSingleLineMode = false
        snippetPreviewLabel.lineBreakMode = .byTruncatingTail
        snippetPreviewLabel.maximumNumberOfLines = 2
        snippetPreviewLabel.cell?.wraps = true
        snippetPreviewLabel.cell?.truncatesLastVisibleLine = true
        snippetPreviewLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        snippetPreviewLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(120), for: .horizontal)

        snippetCopyButton = LiquidGlassButton(
            symbol: "doc.on.doc",
            symbolPointSize: 10,
            symbolWeight: .semibold,
            title: "Copy",
            tooltip: "Copy Recognized Text (⌘C)",
            height: 22,
            minWidth: 58,
            style: .regular,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 10.5, weight: .semibold)
        ) { [weak self] in
            self?.handleCopyText()
        }
        snippetCopyButton.setContentHuggingPriority(.required, for: .horizontal)
        snippetCopyButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        snippetCopyButton.widthAnchor.constraint(equalToConstant: 60).isActive = true
        snippetCopyButton.isHidden = true

        let snippetRow = NSStackView(views: [snippetPreviewLabel, snippetCopyButton])
        snippetRow.orientation = .horizontal
        snippetRow.alignment = .centerY
        snippetRow.distribution = .fill
        snippetRow.spacing = 8
        snippetRowRef = snippetRow

        let heroRightStack = NSStackView(views: [searchBarContainer, snippetRow])
        heroRightStack.orientation = .vertical
        heroRightStack.alignment = .leading
        heroRightStack.spacing = 4
        heroRightStack.translatesAutoresizingMaskIntoConstraints = false
        searchBarContainer.widthAnchor.constraint(equalTo: heroRightStack.widthAnchor).isActive = true
        snippetRow.widthAnchor.constraint(equalTo: heroRightStack.widthAnchor).isActive = true
        heroRightStackRef = heroRightStack

        let heroMainStack = NSStackView(views: [thumbShadowHost, heroRightStack])
        heroMainStack.orientation = .horizontal
        heroMainStack.alignment = .centerY
        heroMainStack.spacing = 10
        heroMainStack.translatesAutoresizingMaskIntoConstraints = false
        heroMainStack.distribution = .fill
        thumbShadowHost.setContentHuggingPriority(.required, for: .horizontal)
        thumbShadowHost.setContentCompressionResistancePriority(.required, for: .horizontal)
        heroRightStack.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        heroRightStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        heroCard.addSubview(heroMainStack)

        NSLayoutConstraint.activate([
            heroMainStack.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor),
            heroMainStack.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor),
            heroMainStack.topAnchor.constraint(equalTo: heroCard.topAnchor),
            heroMainStack.bottomAnchor.constraint(equalTo: heroCard.bottomAnchor)
        ])

        rootStack.addArrangedSubview(heroCard)
        heroCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        heroCard.setContentCompressionResistancePriority(.required, for: .vertical)

        // 3. Single-Row Leading-Aligned Scrollable Action Strip (No dangling centered second row)
        searchActionBtn = makeGlassChip(title: "Search", symbol: "magnifyingglass") { [weak self] in
            guard let self else { return }
            self.resultsModeSegmented?.setSelectedIndex(1, animated: true)
            self.handleResultsModeChanged(1)
        }
        translateActionBtn = makeGlassChip(title: "Translate", symbol: "character.bubble") { [weak self] in
            self?.handleTranslateText()
        }
        copyTextChip = makeGlassChip(title: "Copy Text", symbol: "text.alignleft") { [weak self] in
            self?.handleCopyText()
        }
        explainActionBtn = makeGlassChip(title: "Explain", symbol: "sparkles") { [weak self] in
            self?.handleExplainSelection()
        }
        openLinkChip = makeGlassChip(title: "Open Link", symbol: "link") { [weak self] in
            self?.handleOpenDetectedURL()
        }
        openLinkChip.isHidden = true

        mathResultChip = makeGlassChip(title: "= 0", symbol: "function") { [weak self] in
            self?.handleCopyMathResult()
        }
        mathResultChip.isHidden = true

        colorHexChip = makeGlassChip(title: "#FFFFFF", symbol: "paintpalette") { [weak self] in
            self?.handleCopyColorHex()
        }
        colorHexChip.isHidden = true

        addContactChip = makeGlassChip(title: "Add to Contacts", symbol: "person.crop.circle.badge.plus") { [weak self] in
            self?.handleAddToContacts()
        }
        addContactChip.isHidden = true

        addCalendarChip = makeGlassChip(title: "Add to Calendar", symbol: "calendar.badge.plus") { [weak self] in
            self?.handleAddToCalendar()
        }
        addCalendarChip.isHidden = true

        copyTSVChip = makeGlassChip(title: "Copy TSV/CSV", symbol: "tablecells") { [weak self] in
            self?.handleCopyTable()
        }
        copyTSVChip.isHidden = true

        let overviewJumpBtn = makeGlassChip(title: "Overview", symbol: "doc.text.magnifyingglass") { [weak self] in
            self?.scrollWebResults(toVisualMatches: false)
        }
        let visualMatchesJumpBtn = makeGlassChip(title: "Visual matches", symbol: "photo.stack") { [weak self] in
            self?.scrollWebResults(toVisualMatches: true)
        }

        actionChipsStack = NSStackView(views: [
            searchActionBtn,
            openLinkChip,
            mathResultChip,
            addContactChip,
            addCalendarChip,
            copyTSVChip,
            translateActionBtn,
            copyTextChip,
            explainActionBtn,
            colorHexChip,
            overviewJumpBtn,
            visualMatchesJumpBtn
        ])
        actionChipsStack.orientation = .horizontal
        actionChipsStack.alignment = .centerY
        actionChipsStack.spacing = 6
        actionChipsStack.translatesAutoresizingMaskIntoConstraints = false

        let chipsDocView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 27))
        chipsDocView.addSubview(actionChipsStack)
        NSLayoutConstraint.activate([
            actionChipsStack.leadingAnchor.constraint(equalTo: chipsDocView.leadingAnchor),
            actionChipsStack.centerYAnchor.constraint(equalTo: chipsDocView.centerYAnchor)
        ])
        chipsDocViewRef = chipsDocView

        actionRowScroll = NSScrollView()
        actionRowScroll.drawsBackground = false
        actionRowScroll.hasVerticalScroller = false
        actionRowScroll.hasHorizontalScroller = false
        actionRowScroll.borderType = .noBorder
        actionRowScroll.horizontalScrollElasticity = .automatic
        actionRowScroll.verticalScrollElasticity = .none
        actionRowScroll.documentView = chipsDocView
        actionRowScroll.translatesAutoresizingMaskIntoConstraints = false
        actionRowScroll.heightAnchor.constraint(equalToConstant: 27).isActive = true
        rootStack.addArrangedSubview(actionRowScroll)
        actionRowScroll.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        actionRowScroll.setContentCompressionResistancePriority(.required, for: .vertical)

        // 4. Inline Streaming AI Answer Card (Right Above Google Results: 1-2 lines, streaming text, Copy button)
        aiAnswerCard = LiquidGlassSurfaceView(
            cornerRadius: 14,
            style: .regular,
            tintColor: NSColor(red: 0.36, green: 0.28, blue: 0.88, alpha: 0.16),
            lightTintColor: NSColor(red: 0.42, green: 0.34, blue: 0.92, alpha: 0.10)
        )
        aiAnswerCard.translatesAutoresizingMaskIntoConstraints = false
        aiAnswerCard.isHidden = true

        let aiIcon = LoopBrandLogoView(size: 16)
        aiIcon.translatesAutoresizingMaskIntoConstraints = false
        aiIcon.setContentHuggingPriority(.required, for: .horizontal)
        aiIcon.setContentCompressionResistancePriority(.required, for: .horizontal)

        aiAnswerLabel = NSTextField(labelWithString: "Generating answer…")
        aiAnswerLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        aiAnswerLabel.textColor = .labelColor
        aiAnswerLabel.usesSingleLineMode = false
        aiAnswerLabel.lineBreakMode = .byTruncatingTail
        aiAnswerLabel.maximumNumberOfLines = 6
        aiAnswerLabel.cell?.wraps = true
        aiAnswerLabel.cell?.truncatesLastVisibleLine = true
        aiAnswerLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        aiAnswerLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(120), for: .horizontal)

        aiCopyButton = LiquidGlassButton(
            symbol: "doc.on.doc",
            symbolPointSize: 9.5,
            symbolWeight: .semibold,
            title: "Copy",
            tooltip: "Copy AI Answer",
            height: 22,
            minWidth: 58,
            style: .regular,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 10.5, weight: .semibold)
        ) { [weak self] in
            self?.handleCopyAIExplanation()
        }
        aiCopyButton.setContentHuggingPriority(.required, for: .horizontal)
        aiCopyButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        aiCopyButton.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let hasKeyConfigured = !KeychainHelper.loadAPIKey().isEmpty
        aiSourceBadgeLabel = NSTextField(labelWithString: hasKeyConfigured ? "Gemini answer · may be wrong" : "On-device answer · may be wrong")
        aiSourceBadgeLabel.font = .systemFont(ofSize: 10.0, weight: .semibold)
        aiSourceBadgeLabel.textColor = .secondaryLabelColor

        let aiStack = NSStackView(views: [aiIcon, aiAnswerLabel, aiCopyButton])
        aiStack.orientation = .horizontal
        aiStack.alignment = .centerY
        aiStack.distribution = .fill
        aiStack.spacing = 8

        let suggest1 = makeGlassChip(title: "Summarize", symbol: "text.alignleft") { [weak self] in
            self?.startAIExplanationStream(prompt: "Summarize this concisely in 2 sentences.", forceShow: true)
        }
        let suggest2 = makeGlassChip(title: "Key points", symbol: "list.bullet") { [weak self] in
            self?.startAIExplanationStream(prompt: "List the key factual points shown here.", forceShow: true)
        }
        let suggest3 = makeGlassChip(title: "Open Lens", symbol: "globe") { [weak self] in
            self?.resultsModeSegmented?.setSelectedIndex(1, animated: true)
            self?.handleResultsModeChanged(1)
        }
        let suggestedRow = NSStackView(views: [suggest1, suggest2, suggest3])
        suggestedRow.orientation = .horizontal
        suggestedRow.alignment = .centerY
        suggestedRow.spacing = 6

        followUpField = NSTextField()
        followUpField.isBezeled = false
        followUpField.drawsBackground = false
        followUpField.focusRingType = .none
        followUpField.font = .systemFont(ofSize: 11.5, weight: .regular)
        followUpField.textColor = .labelColor
        followUpField.placeholderString = "Ask a follow-up question…"
        followUpField.target = self
        followUpField.action = #selector(handleFollowUpSubmit)

        let followUpContainer = AdaptiveSurfaceView(
            cornerRadius: 10,
            darkFill: NSColor.white.withAlphaComponent(0.06),
            lightFill: NSColor.black.withAlphaComponent(0.04),
            darkBorder: NSColor.white.withAlphaComponent(0.10),
            lightBorder: NSColor.black.withAlphaComponent(0.08),
            borderWidth: 0.75
        )
        followUpContainer.translatesAutoresizingMaskIntoConstraints = false
        followUpField.translatesAutoresizingMaskIntoConstraints = false
        followUpContainer.addSubview(followUpField)
        NSLayoutConstraint.activate([
            followUpContainer.heightAnchor.constraint(equalToConstant: 28),
            followUpField.leadingAnchor.constraint(equalTo: followUpContainer.leadingAnchor, constant: 10),
            followUpField.trailingAnchor.constraint(equalTo: followUpContainer.trailingAnchor, constant: -10),
            followUpField.centerYAnchor.constraint(equalTo: followUpContainer.centerYAnchor)
        ])

        let aiCardBodyStack = NSStackView(views: [aiSourceBadgeLabel, aiStack, suggestedRow, followUpContainer])
        aiCardBodyStack.orientation = .vertical
        aiCardBodyStack.alignment = .leading
        aiCardBodyStack.spacing = 6
        aiCardBodyStack.translatesAutoresizingMaskIntoConstraints = false
        aiAnswerCard.contentContainer.addSubview(aiCardBodyStack)
        NSLayoutConstraint.activate([
            followUpContainer.widthAnchor.constraint(equalTo: aiCardBodyStack.widthAnchor),
            aiStack.widthAnchor.constraint(equalTo: aiCardBodyStack.widthAnchor),
            aiCardBodyStack.leadingAnchor.constraint(equalTo: aiAnswerCard.contentContainer.leadingAnchor, constant: 10),
            aiCardBodyStack.trailingAnchor.constraint(equalTo: aiAnswerCard.contentContainer.trailingAnchor, constant: -8),
            aiCardBodyStack.topAnchor.constraint(equalTo: aiAnswerCard.contentContainer.topAnchor, constant: 7),
            aiCardBodyStack.bottomAnchor.constraint(equalTo: aiAnswerCard.contentContainer.bottomAnchor, constant: -7)
        ])
        rootStack.addArrangedSubview(aiAnswerCard)
        aiAnswerCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        aiAnswerCard.setContentCompressionResistancePriority(.required, for: .vertical)

        answerContextCard = LiquidGlassSurfaceView(
            cornerRadius: 14,
            style: .regular,
            tintColor: NSColor.labelColor.withAlphaComponent(0.04)
        )
        answerContextCard.translatesAutoresizingMaskIntoConstraints = false
        answerContextCard.isHidden = true
        answerContextLabel = NSTextField(wrappingLabelWithString: "")
        answerContextLabel.font = .systemFont(ofSize: 12.0, weight: .regular)
        answerContextLabel.textColor = .secondaryLabelColor
        answerContextLabel.isSelectable = true
        answerContextLabel.translatesAutoresizingMaskIntoConstraints = false
        answerContextCard.contentContainer.addSubview(answerContextLabel)
        NSLayoutConstraint.activate([
            answerContextLabel.leadingAnchor.constraint(equalTo: answerContextCard.contentContainer.leadingAnchor, constant: 12),
            answerContextLabel.trailingAnchor.constraint(equalTo: answerContextCard.contentContainer.trailingAnchor, constant: -12),
            answerContextLabel.topAnchor.constraint(equalTo: answerContextCard.contentContainer.topAnchor, constant: 10),
            answerContextLabel.bottomAnchor.constraint(lessThanOrEqualTo: answerContextCard.contentContainer.bottomAnchor, constant: -10)
        ])
        rootStack.addArrangedSubview(answerContextCard)
        answerContextCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        // 5. Empty / Boring Selection Card ("Not much here. Try selecting something with text or an object.")
        emptySelectionCard = LiquidGlassSurfaceView(
            cornerRadius: 14,
            style: .regular,
            tintColor: NSColor.labelColor.withAlphaComponent(0.05)
        )
        emptySelectionCard.isHidden = true
        emptySelectionCard.translatesAutoresizingMaskIntoConstraints = false

        let emptyIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "viewfinder.trianglebadge.exclamationmark", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            emptyIcon.image = img.withSymbolConfiguration(cfg)
            emptyIcon.contentTintColor = .secondaryLabelColor
        }
        let emptyTitle = NSTextField(labelWithString: "Not much here. Try selecting something with text or an object.")
        emptyTitle.font = .systemFont(ofSize: 12.5, weight: .semibold)
        emptyTitle.textColor = .labelColor
        emptyTitle.alignment = .center
        emptyTitle.maximumNumberOfLines = 2
        emptyTitle.cell?.wraps = true

        let emptySub = NSTextField(labelWithString: "Drag a new box or freehand loop anywhere on screen, or type a query above.")
        emptySub.font = .systemFont(ofSize: 11.0, weight: .regular)
        emptySub.textColor = .secondaryLabelColor
        emptySub.alignment = .center

        let emptyStack = NSStackView(views: [emptyIcon, emptyTitle, emptySub])
        emptyStack.orientation = .vertical
        emptyStack.alignment = .centerX
        emptyStack.spacing = 6
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptySelectionCard.contentContainer.addSubview(emptyStack)
        NSLayoutConstraint.activate([
            emptyStack.leadingAnchor.constraint(equalTo: emptySelectionCard.contentContainer.leadingAnchor, constant: 18),
            emptyStack.trailingAnchor.constraint(equalTo: emptySelectionCard.contentContainer.trailingAnchor, constant: -18),
            emptyStack.topAnchor.constraint(equalTo: emptySelectionCard.contentContainer.topAnchor, constant: 22),
            emptyStack.bottomAnchor.constraint(equalTo: emptySelectionCard.contentContainer.bottomAnchor, constant: -22)
        ])
        rootStack.addArrangedSubview(emptySelectionCard)
        emptySelectionCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        // 6. Friendly Error / CAPTCHA Card ("Lens didn’t load. Open in browser / Try another search engine")
        errorStateCard = LiquidGlassSurfaceView(
            cornerRadius: 14,
            style: .regular,
            tintColor: NSColor.systemBlue.withAlphaComponent(0.18)
        )
        errorStateCard.isHidden = true
        errorStateCard.translatesAutoresizingMaskIntoConstraints = false

        errorStateTitleLabel = NSTextField(labelWithString: "Lens didn’t load. Open in browser or try another search engine.")
        errorStateTitleLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        errorStateTitleLabel.textColor = .labelColor
        errorStateTitleLabel.lineBreakMode = .byTruncatingTail

        let errOpenBrowserBtn = LiquidGlassButton(
            symbol: "safari",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Open in Browser",
            tooltip: "Open in your default browser",
            height: 25,
            minWidth: 116,
            style: .regular,
            tintColor: NSColor(red: 0.30, green: 0.54, blue: 0.98, alpha: 0.85),
            foregroundColor: .white,
            font: .systemFont(ofSize: 11, weight: .semibold)
        ) { [weak self] in
            self?.handleOpenInBrowser()
        }

        let errSwitchEngineBtn = LiquidGlassButton(
            symbol: "arrow.triangle.2.circlepath",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Try Another Search Engine",
            tooltip: "Switch to Google Web, Perplexity, or Bing",
            height: 25,
            minWidth: 162,
            style: .regular,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 11, weight: .semibold)
        ) { [weak self] in
            self?.handleTryFallbackSearchEngine()
        }

        let errButtonsRow = NSStackView(views: [errOpenBrowserBtn, errSwitchEngineBtn])
        errButtonsRow.orientation = .horizontal
        errButtonsRow.alignment = .centerY
        errButtonsRow.spacing = 8

        let errMainStack = NSStackView(views: [errorStateTitleLabel, errButtonsRow])
        errMainStack.orientation = .vertical
        errMainStack.alignment = .leading
        errMainStack.spacing = 7
        errMainStack.translatesAutoresizingMaskIntoConstraints = false
        errorStateCard.contentContainer.addSubview(errMainStack)
        NSLayoutConstraint.activate([
            errMainStack.leadingAnchor.constraint(equalTo: errorStateCard.contentContainer.leadingAnchor, constant: 12),
            errMainStack.trailingAnchor.constraint(equalTo: errorStateCard.contentContainer.trailingAnchor, constant: -12),
            errMainStack.topAnchor.constraint(equalTo: errorStateCard.contentContainer.topAnchor, constant: 8),
            errMainStack.bottomAnchor.constraint(equalTo: errorStateCard.contentContainer.bottomAnchor, constant: -8)
        ])
        rootStack.addArrangedSubview(errorStateCard)
        errorStateCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        errorStateCard.setContentCompressionResistancePriority(.required, for: .vertical)

        // 7. Flattened Web Results Container + Pure-GPU Animated Blue Searching State
        webOuterCard = NSView()
        webOuterCard.wantsLayer = true
        webOuterCard.translatesAutoresizingMaskIntoConstraints = false

        let webClipView = AdaptiveSurfaceView(
            cornerRadius: 14,
            darkFill: NSColor.black.withAlphaComponent(0.18),
            lightFill: NSColor.black.withAlphaComponent(0.03),
            darkBorder: NSColor.white.withAlphaComponent(0.08),
            lightBorder: NSColor.black.withAlphaComponent(0.08),
            borderWidth: 0.75
        )
        webClipView.translatesAutoresizingMaskIntoConstraints = false
        webClipViewRef = webClipView
        webOuterCard.addSubview(webClipView)

        let webMaskView = NSView()
        webMaskView.wantsLayer = true
        webMaskView.layer?.cornerRadius = 14
        webMaskView.layer?.cornerCurve = .continuous
        webMaskView.layer?.masksToBounds = true
        webMaskView.translatesAutoresizingMaskIntoConstraints = false
        webClipView.addSubview(webMaskView)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Never inject custom CSS into Google's page; rely purely on WKWebView.appearance.
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = GoogleLensService.desktopSafariUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 14
        webView.layer?.cornerCurve = .continuous
        webView.layer?.masksToBounds = true
        webView.alphaValue = 0.0
        webView.translatesAutoresizingMaskIntoConstraints = false
        webMaskView.addSubview(webView)
        syncWebViewAppearance()

        // GPU-composited Searching Overlay (zero nested NSGlassEffectView blur & zero per-frame CPU CGGradient draws)
        loadingOverlay = AdaptiveSurfaceView(
            cornerRadius: 14,
            darkFill: NSColor(red: 0.008, green: 0.015, blue: 0.036, alpha: 0.96),
            lightFill: NSColor(white: 0.96, alpha: 0.95),
            darkBorder: .clear,
            lightBorder: .clear,
            borderWidth: 0.0
        )
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false

        loaderHorizonGlowLayer.type = .radial
        loaderHorizonGlowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        loaderHorizonGlowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        loaderHorizonGlowLayer.colors = [
            NSColor(red: 0.14, green: 0.74, blue: 1.00, alpha: 0.52).cgColor,
            NSColor(red: 0.04, green: 0.42, blue: 0.96, alpha: 0.28).cgColor,
            NSColor(red: 0.06, green: 0.16, blue: 0.48, alpha: 0.10).cgColor,
            NSColor.clear.cgColor
        ]
        loaderHorizonGlowLayer.locations = [0.0, 0.36, 0.70, 1.0]
        loaderHorizonGlowLayer.zPosition = -15
        loadingOverlay.layer?.addSublayer(loaderHorizonGlowLayer)

        loaderHorizonPeakLayer.type = .radial
        loaderHorizonPeakLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        loaderHorizonPeakLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        loaderHorizonPeakLayer.colors = [
            NSColor(red: 0.88, green: 0.98, blue: 1.00, alpha: 0.62).cgColor,
            NSColor(red: 0.18, green: 0.78, blue: 1.00, alpha: 0.38).cgColor,
            NSColor.clear.cgColor
        ]
        loaderHorizonPeakLayer.locations = [0.0, 0.42, 1.0]
        loaderHorizonPeakLayer.zPosition = -10
        loadingOverlay.layer?.addSublayer(loaderHorizonPeakLayer)

        shimmerLayer.colors = [
            NSColor.clear.cgColor,
            NSColor(red: 0.14, green: 0.68, blue: 1.00, alpha: 0.035).cgColor,
            NSColor.white.withAlphaComponent(0.035).cgColor,
            NSColor(red: 0.08, green: 0.46, blue: 0.98, alpha: 0.025).cgColor,
            NSColor.clear.cgColor
        ]
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.35)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.65)
        shimmerLayer.zPosition = -5
        loadingOverlay.layer?.addSublayer(shimmerLayer)

        // Animated Optical Blue Search Orb (120fps Hardware-Composited Ripples & Conic Arcs)
        let opticalOrb = BlueSearchOpticalOrbView()
        opticalOrb.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            opticalOrb.widthAnchor.constraint(equalToConstant: 96),
            opticalOrb.heightAnchor.constraint(equalToConstant: 96)
        ])
        self.searchOpticalOrb = opticalOrb

        let searchTitleLabel = NSTextField(labelWithString: "Searching")
        searchTitleLabel.font = .systemFont(ofSize: 15.5, weight: .semibold)
        searchTitleLabel.textColor = .labelColor

        loadingStatusLabel = NSTextField(labelWithString: "Scanning visual space…")
        loadingStatusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        loadingStatusLabel.textColor = NSColor(red: 0.58, green: 0.84, blue: 1.0, alpha: 0.86)
        loadingStatusLabel.wantsLayer = true

        let headerStatusStack = NSStackView(views: [searchTitleLabel, loadingStatusLabel])
        headerStatusStack.orientation = .vertical
        headerStatusStack.alignment = .centerX
        headerStatusStack.spacing = 4

        let loadStack = NSStackView(views: [opticalOrb, headerStatusStack])
        loadStack.orientation = .vertical
        loadStack.alignment = .centerX
        loadStack.spacing = 12
        loadStack.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.addSubview(loadStack)

        webClipView.addSubview(loadingOverlay)

        NSLayoutConstraint.activate([
            webClipView.leadingAnchor.constraint(equalTo: webOuterCard.leadingAnchor),
            webClipView.trailingAnchor.constraint(equalTo: webOuterCard.trailingAnchor),
            webClipView.topAnchor.constraint(equalTo: webOuterCard.topAnchor),
            webClipView.bottomAnchor.constraint(equalTo: webOuterCard.bottomAnchor),

            webMaskView.leadingAnchor.constraint(equalTo: webClipView.leadingAnchor),
            webMaskView.trailingAnchor.constraint(equalTo: webClipView.trailingAnchor),
            webMaskView.topAnchor.constraint(equalTo: webClipView.topAnchor),
            webMaskView.bottomAnchor.constraint(equalTo: webClipView.bottomAnchor),

            webView.leadingAnchor.constraint(equalTo: webMaskView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webMaskView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: webMaskView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: webMaskView.bottomAnchor),

            loadingOverlay.leadingAnchor.constraint(equalTo: webClipView.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: webClipView.trailingAnchor),
            loadingOverlay.topAnchor.constraint(equalTo: webClipView.topAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: webClipView.bottomAnchor),

            loadStack.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadStack.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor, constant: -16)
        ])

        rootStack.addArrangedSubview(webOuterCard)
        webOuterCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        let fillHeight = webOuterCard.heightAnchor.constraint(equalTo: rootStack.heightAnchor)
        fillHeight.priority = .init(600)
        fillHeight.isActive = true

        resizeHandleView.translatesAutoresizingMaskIntoConstraints = false
        backdropView.contentContainer.addSubview(resizeHandleView)
        NSLayoutConstraint.activate([
            resizeHandleView.trailingAnchor.constraint(equalTo: backdropView.contentContainer.trailingAnchor),
            resizeHandleView.bottomAnchor.constraint(equalTo: backdropView.contentContainer.bottomAnchor),
            resizeHandleView.widthAnchor.constraint(equalToConstant: 22),
            resizeHandleView.heightAnchor.constraint(equalToConstant: 22)
        ])

        startLoaderAnimations()
    }

    private static func makeSkeletonBar(height: CGFloat, alpha: CGFloat) -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.cornerRadius = height / 2
        bar.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: height).isActive = true
        return bar
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sheetGlowLayer.frame = bounds
        sheetGlowLayer.updatePath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 24, glowPadding: 34)

        let lb = loadingOverlay.bounds
        shimmerLayer.frame = lb
        let glowH = max(165, lb.height * 0.72)
        loaderHorizonGlowLayer.bounds = CGRect(x: 0, y: 0, width: max(120, lb.width * 1.40), height: glowH)
        loaderHorizonGlowLayer.position = CGPoint(x: lb.width * 0.5, y: 0)
        loaderHorizonGlowLayer.opacity = isDarkAppearance ? 0.96 : 0.25

        loaderHorizonPeakLayer.bounds = CGRect(x: 0, y: 0, width: max(90, lb.width * 0.88), height: 84)
        loaderHorizonPeakLayer.position = CGPoint(x: lb.width * 0.5, y: 2)
        loaderHorizonPeakLayer.opacity = isDarkAppearance ? 0.95 : 0.22
        CATransaction.commit()

        if let rightStack = heroRightStackRef {
            let copySpace: CGFloat = snippetCopyButton.isHidden ? 4 : 68
            snippetPreviewLabel.preferredMaxLayoutWidth = max(110, rightStack.bounds.width - copySpace)
        }
        if !aiAnswerCard.isHidden {
            aiAnswerLabel.preferredMaxLayoutWidth = max(120, aiAnswerCard.bounds.width - 104)
        }
        updateChipsScrollContentSize()
    }

    private func startLoaderAnimations() {
        searchOpticalOrb?.startAnimating()
        guard !AppSettings.shared.effectiveReduceMotion else { return }

        let sine = CAMediaTimingFunction(controlPoints: 0.45, 0.05, 0.55, 0.95)

        if loaderHorizonGlowLayer.animation(forKey: "horizonDrift") == nil {
            let drift = CABasicAnimation(keyPath: "transform.translation.x")
            drift.fromValue = -26.0
            drift.toValue = 26.0
            drift.duration = 4.20
            drift.autoreverses = true
            drift.timingFunction = sine
            drift.repeatCount = .infinity
            drift.isRemovedOnCompletion = false
            loaderHorizonGlowLayer.add(drift, forKey: "horizonDrift")

            let tide = CABasicAnimation(keyPath: "transform.scale.y")
            tide.fromValue = 0.92
            tide.toValue = 1.09
            tide.duration = 3.10
            tide.autoreverses = true
            tide.timingFunction = sine
            tide.repeatCount = .infinity
            tide.isRemovedOnCompletion = false
            loaderHorizonGlowLayer.add(tide, forKey: "horizonTide")
        }

        if loaderHorizonPeakLayer.animation(forKey: "peakDrift") == nil {
            let counterDrift = CABasicAnimation(keyPath: "transform.translation.x")
            counterDrift.fromValue = 22.0
            counterDrift.toValue = -22.0
            counterDrift.duration = 3.60
            counterDrift.autoreverses = true
            counterDrift.timingFunction = sine
            counterDrift.repeatCount = .infinity
            counterDrift.isRemovedOnCompletion = false
            loaderHorizonPeakLayer.add(counterDrift, forKey: "peakDrift")

            let breathe = CABasicAnimation(keyPath: "transform.scale.x")
            breathe.fromValue = 0.90
            breathe.toValue = 1.12
            breathe.duration = 2.50
            breathe.autoreverses = true
            breathe.timingFunction = sine
            breathe.repeatCount = .infinity
            breathe.isRemovedOnCompletion = false
            loaderHorizonPeakLayer.add(breathe, forKey: "peakScale")
        }

        if shimmerLayer.animation(forKey: "shimmerMove") == nil {
            let anim = CABasicAnimation(keyPath: "locations")
            anim.fromValue = [-1.0, -0.78, -0.55, -0.32, -0.10]
            anim.toValue = [1.10, 1.32, 1.55, 1.78, 2.0]
            anim.duration = 2.80
            anim.timingFunction = sine
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false
            shimmerLayer.add(anim, forKey: "shimmerMove")
        }

        if let statusLayer = loadingStatusLabel.layer, statusLayer.animation(forKey: "statusPulse") == nil {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.72
            pulse.toValue = 1.0
            pulse.duration = 1.75
            pulse.autoreverses = true
            pulse.timingFunction = sine
            pulse.repeatCount = .infinity
            pulse.isRemovedOnCompletion = false
            statusLayer.add(pulse, forKey: "statusPulse")
        }
    }

    private func stopLoaderAnimations() {
        searchOpticalOrb?.stopAnimating()
        loaderHorizonGlowLayer.removeAllAnimations()
        loaderHorizonPeakLayer.removeAllAnimations()
        shimmerLayer.removeAllAnimations()
        loadingStatusLabel.layer?.removeAnimation(forKey: "statusPulse")
    }

    /// Collapses whitespace and trims long OCR dumps to a clean ~120 character preview ending on a word boundary.
    private static func tidySnippet(_ text: String) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let limit = 120
        guard collapsed.count > limit else { return collapsed }
        let cut = String(collapsed.prefix(limit))
        if let lastSpace = cut.lastIndex(of: " ") {
            return String(cut[..<lastSpace]) + "…"
        }
        return cut + "…"
    }

    private func updateChipsScrollContentSize() {
        guard actionRowScroll != nil, actionChipsStack != nil, let docView = chipsDocViewRef else { return }
        actionChipsStack.layoutSubtreeIfNeeded()
        let contentW = actionChipsStack.fittingSize.width
        let minW = actionRowScroll.bounds.width
        docView.frame = NSRect(x: 0, y: 0, width: max(minW, contentW), height: 27)
    }

    private func relayoutActionChips() {
        actionRowScroll?.contentView.scroll(to: .zero)
        updateChipsScrollContentSize()
    }

    private func leaveLowInfoStateIfNeeded() {
        emptySelectionCard.isHidden = true
        webOuterCard.isHidden = false
        if isLowInfoSelection {
            isLowInfoSelection = false
            snippetPreviewLabel.textColor = .secondaryLabelColor
            if snippetPreviewLabel.stringValue.hasPrefix("Not much here") {
                snippetPreviewLabel.stringValue = ""
                snippetRowRef.isHidden = true
            }
        }
    }

    func updateVisionAnalysis(_ result: VisionAnalysisResult) {
        currentBlocks = result.blocks
        currentClassificationLabels = result.classificationLabels
        currentURL = result.urls.first
        currentHexColor = result.dominantHexColor
        currentMathSolution = result.mathSolution
        isLowInfoSelection = result.isLowInformation

        // 1. Handle Empty or Boring Selections cleanly
        if result.isLowInformation {
            snippetPreviewLabel.stringValue = "Not much here. Try selecting something with text or an object."
            snippetPreviewLabel.textColor = .labelColor
            snippetCopyButton.isHidden = true
            snippetRowRef.isHidden = false
            translateActionBtn.isHidden = true
            openLinkChip.isHidden = true
            mathResultChip.isHidden = true
            colorHexChip.isHidden = true
            aiAnswerCard.isHidden = true
            webOuterCard.isHidden = true
            relayoutActionChips()
            AppleMotion.animateVisibility(emptySelectionCard, visible: true, scale: 0.96, duration: 0.24)
            onResultsReady()
            return
        }

        currentOcrConfidence = result.averageConfidence
        currentDetectedEmails = result.emails
        currentDetectedPhones = result.phoneNumbers
        currentDetectedDates = result.dates
        currentTableTSV = result.tableTSV
        currentTableCSV = result.tableCSV

        emptySelectionCard.isHidden = true
        let isLensSelected = (resultsModeSegmented?.selectedIndex ?? 1) == 1
        webOuterCard.isHidden = !isLensSelected
        answerContextCard?.isHidden = isLensSelected
        let contextParts = [
            result.cleanPreviewText.isEmpty ? nil : "Recognized Text:\n\(result.text)",
            result.classificationLabels.isEmpty ? nil : "Detected Visual Subjects: \(result.classificationLabels.joined(separator: ", "))"
        ].compactMap { $0 }
        answerContextLabel?.stringValue = contextParts.isEmpty
            ? "Switch to the Lens tab above for Google visual & web matches."
            : contextParts.joined(separator: "\n\n")
        let hasRecognizedText = !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        translateActionBtn.isHidden = !hasRecognizedText || result.isSystemLanguage
        addContactChip.isHidden = result.emails.isEmpty && result.phoneNumbers.isEmpty
        addCalendarChip.isHidden = result.dates.isEmpty
        copyTSVChip.isHidden = (result.tableTSV == nil)
        if hasRecognizedText {
            copyTextChip.title = "Copy Text"
            copyTextChip.updateSymbol("text.alignleft", pointSize: 10.5, weight: .medium)
        } else {
            copyTextChip.title = "Copy Image"
            copyTextChip.updateSymbol("photo.on.rectangle", pointSize: 10.5, weight: .medium)
        }

        // Dominant color swatch chip — only when vibrant/saturated (never dull #212121 gray)
        if !currentHexColor.isEmpty && result.hasVibrantColorSwatch {
            colorHexChip.title = currentHexColor
            colorHexChip.isHidden = false
        } else {
            colorHexChip.isHidden = true
        }

        // Math solver chip
        if let math = currentMathSolution {
            mathResultChip.title = "= \(math.result)"
            mathResultChip.isHidden = false
        } else {
            mathResultChip.isHidden = true
        }

        // QR / URL chip
        openLinkChip.isHidden = (currentURL == nil)
        relayoutActionChips()

        let rawText = result.text.isEmpty
            ? result.barcodes.joined(separator: " ")
            : result.text.replacingOccurrences(of: "\n", with: " ")
        currentText = rawText
        let preview = Self.tidySnippet(result.cleanPreviewText.isEmpty ? rawText : result.cleanPreviewText)
        currentPreviewText = preview

        if !preview.isEmpty && AppSettings.shared.showInlineOCR {
            snippetPreviewLabel.stringValue = preview
            snippetPreviewLabel.textColor = .secondaryLabelColor
            snippetPreviewLabel.toolTip = result.text
            snippetPreviewLabel.isHidden = false
            snippetCopyButton.isHidden = true
            snippetRowRef.isHidden = false
        } else if !result.classificationLabels.isEmpty {
            let subjectTags = result.classificationLabels.prefix(3).map { $0.capitalized }.joined(separator: " · ")
            snippetPreviewLabel.stringValue = subjectTags
            snippetPreviewLabel.textColor = .secondaryLabelColor
            snippetPreviewLabel.toolTip = nil
            snippetPreviewLabel.isHidden = false
            snippetCopyButton.isHidden = true
            snippetRowRef.isHidden = false
        } else {
            snippetPreviewLabel.stringValue = ""
            snippetPreviewLabel.toolTip = nil
            snippetPreviewLabel.isHidden = true
            snippetCopyButton.isHidden = true
            snippetRowRef.isHidden = true
        }

        // Auto-show Answer Card when Answer tab is selected, or when a Gemini key / math solution exists
        let hasCloudKey = !KeychainHelper.loadAPIKey().isEmpty
        if hasCloudKey || result.mathSolution != nil || resultsModeSegmented?.selectedIndex == 0 {
            startAIExplanationStream(
                prompt: "Explain this selection concisely in 1 to 3 sentences.",
                forceShow: true
            )
        } else {
            aiAnswerCard.isHidden = true
        }
    }

    private func startAIExplanationStream(prompt: String, forceShow: Bool = false) {
        aiStreamingTask?.cancel()
        let hasKey = !KeychainHelper.loadAPIKey().isEmpty
        if hasKey || forceShow {
            AppleMotion.animateVisibility(aiAnswerCard, visible: true, scale: 0.96, duration: 0.22)
            aiAnswerLabel.stringValue = "Generating answer…"
        } else {
            aiAnswerCard.isHidden = true
        }

        let img = croppedCGImage
        let ocr = currentPreviewText
        let labels = currentClassificationLabels

        aiStreamingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let answer = await AIService.generateExplanation(
                image: img,
                ocrText: ocr,
                ocrConfidence: self.currentOcrConfidence,
                mathSolution: self.currentMathSolution,
                classificationLabels: labels,
                detectedURL: self.currentURL,
                userQuery: (hasKey || forceShow) ? prompt : ""
            )
            guard !Task.isCancelled else { return }
            if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AppleMotion.animateVisibility(self.aiAnswerCard, visible: false, scale: 0.96, duration: 0.18)
                return
            }
            AppleMotion.animateVisibility(self.aiAnswerCard, visible: true, scale: 0.96, duration: 0.22)
            self.currentAIExplanation = answer
            self.aiAnswerLabel.toolTip = answer

            if AppSettings.shared.effectiveReduceMotion {
                self.aiAnswerLabel.stringValue = answer
                return
            }

            // Smooth streaming word-by-word reveal
            let words = answer.split(separator: " ").map(String.init)
            guard words.count > 1 else {
                self.aiAnswerLabel.stringValue = answer
                return
            }
            var built = ""
            for (idx, word) in words.enumerated() {
                guard !Task.isCancelled else { return }
                built += (idx == 0 ? "" : " ") + word
                self.aiAnswerLabel.stringValue = built
                try? await Task.sleep(nanoseconds: 24_000_000)
            }
        }
    }

    func loadLensResults(_ upload: LensUploadResult) {
        guard !isLowInfoSelection else { return }
        baseLensURL = upload.resultsURL
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

        Task {
            for cookie in upload.cookies {
                await cookieStore.setCookie(cookie)
            }
            webView.load(URLRequest(url: upload.resultsURL))
        }
    }

    func showLensError(_ message: String) {
        onResultsReady()
        errorStateTitleLabel.stringValue = "Lens didn’t load (\(message)). Open in browser or try another search engine."
        AppleMotion.animateVisibility(errorStateCard, visible: true, scale: 0.96, duration: 0.22)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.24)
            ctx.timingFunction = AppleMotion.easeOut
            loadingOverlay.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.loadingOverlay.isHidden = true
                self?.stopLoaderAnimations()
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsErr = error as NSError
        if nsErr.code == NSURLErrorCancelled { return }
        showLensError(error.localizedDescription)
    }

    // MARK: - WKNavigationDelegate & WKUIDelegate

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncWebViewAppearance()
    }

    private func fadeOutLoadingOverlay() {
        loadingFallbackTask?.cancel()
        guard !loadingOverlay.isHidden else {
            webView.alphaValue = 1.0
            return
        }
        webView.wantsLayer = true
        webView.layoutSubtreeIfNeeded()
        if webView.bounds.width > 0, webView.bounds.height > 0 {
            let enterSpring = AppleMotion.spring(
                keyPath: "transform",
                from: AppleMotion.centeredTransform(bounds: webView.bounds, scale: 0.985),
                to: CATransform3DIdentity,
                dampingRatio: 0.90,
                response: 0.38
            )
            webView.layer?.transform = CATransform3DIdentity
            webView.layer?.add(enterSpring, forKey: "resultsReveal")
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.34)
            ctx.timingFunction = AppleMotion.easeOut
            webView.animator().alphaValue = 1.0
            loadingOverlay.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.loadingOverlay.isHidden = true
                self?.stopLoaderAnimations()
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        AppleMotion.animateVisibility(backButton, visible: webView.canGoBack, scale: 0.88, duration: 0.20)
        onResultsReady()

        if let current = webView.url {
            if current.path.hasPrefix("/sorry") {
                errorStateTitleLabel.stringValue = "Lens verification required. Open in browser or try another search engine:"
                AppleMotion.animateVisibility(errorStateCard, visible: true, scale: 0.96, duration: 0.22)
                if let comps = URLComponents(url: current, resolvingAgainstBaseURL: false),
                   let continueStr = comps.queryItems?.first(where: { $0.name == "continue" })?.value,
                   let continueURL = URL(string: continueStr) {
                    baseLensURL = continueURL
                }
            } else {
                AppleMotion.animateVisibility(errorStateCard, visible: false, scale: 0.96, duration: 0.18)
                if current.host?.contains("google.") == true, current.path == "/search" {
                    baseLensURL = current
                }
            }
        }

        fadeOutLoadingOverlay()
        // Smoothly scroll desktop Google Lens results into view without clicking or injecting CSS/JS hiding rules
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let scrollOnlyJs = """
            (function() {
                var target = document.querySelector('#search, #rcnt, [role="main"]');
                if (target) {
                    var rect = target.getBoundingClientRect();
                    if (rect.top > 90) {
                        window.scrollTo({ top: Math.max(0, window.scrollY + rect.top - 16), behavior: 'smooth' });
                    }
                }
            })();
            """
            self.webView?.evaluateJavaScript(scrollOnlyJs, completionHandler: nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if url.host?.contains("google.") == true {
                webView.load(URLRequest(url: url))
            } else {
                onOpenExternalURL(url)
            }
        }
        return nil
    }

    // MARK: - Actions & More Menu (⋯)

    func triggerKeyboardCopy() {
        let textToCopy = currentText.isEmpty ? currentPreviewText : currentText
        if !textToCopy.isEmpty {
            handleCopyText()
        } else {
            onCopyImage()
        }
    }

    private func showMoreActionsMenu() {
        let menu = NSMenu(title: "More Actions")

        let stickerItem = NSMenuItem(title: "Remove Background / Copy Sticker", action: #selector(handleMenuCopySticker), keyEquivalent: "")
        stickerItem.target = self
        stickerItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        menu.addItem(stickerItem)

        let copyImgItem = NSMenuItem(title: "Copy Cropped Image", action: #selector(handleCopyImage), keyEquivalent: "")
        copyImgItem.target = self
        copyImgItem.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil)
        menu.addItem(copyImgItem)

        let saveItem = NSMenuItem(title: "Save PNG to Desktop", action: #selector(handleSaveImage), keyEquivalent: "s")
        saveItem.keyEquivalentModifierMask = [.command]
        saveItem.target = self
        saveItem.image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: nil)
        menu.addItem(saveItem)

        menu.addItem(.separator())

        let expandTitle = isExpanded ? "Collapse Panel Size" : "Expand Panel Size"
        let expandItem = NSMenuItem(title: expandTitle, action: #selector(handleMenuToggleExpand), keyEquivalent: "")
        expandItem.target = self
        expandItem.image = NSImage(
            systemSymbolName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: nil
        )
        menu.addItem(expandItem)

        let openItem = NSMenuItem(title: "Open Results in Browser", action: #selector(handleOpenInBrowser), keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = [.command]
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
        menu.addItem(openItem)

        menu.addItem(.separator())

        let engineSubmenu = NSMenu(title: "Search Engine")
        for engine in SearchEngine.allCases {
            let item = NSMenuItem(title: engine.title, action: #selector(handleSelectEngineFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = engine.rawValue
            item.state = (AppSettings.shared.searchEngine == engine) ? .on : .off
            item.image = loopSymbolImage(engine.symbolName, accessibility: nil, pointSize: 12)
            engineSubmenu.addItem(item)
        }
        let engineParent = NSMenuItem(title: "Switch Search Engine", action: nil, keyEquivalent: "")
        engineParent.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        engineParent.submenu = engineSubmenu
        menu.addItem(engineParent)

        let webThemeSubmenu = NSMenu(title: "Web Results Mode")
        for mode in AppTheme.allCases {
            let title = (mode == .system) ? "Auto (Match App)" : mode.title
            let item = NSMenuItem(title: title, action: #selector(handleSelectWebThemeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (AppSettings.shared.webResultsTheme == mode) ? .on : .off
            item.image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: nil)
            webThemeSubmenu.addItem(item)
        }
        let webThemeParent = NSMenuItem(title: "Web Results Theme", action: nil, keyEquivalent: "")
        webThemeParent.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: nil)
        webThemeParent.submenu = webThemeSubmenu
        menu.addItem(webThemeParent)

        let pt = NSPoint(x: 0, y: moreButton.bounds.height + 4)
        menu.popUp(positioning: nil, at: pt, in: moreButton)
    }

    @objc private func handleMenuCopySticker() {
        onCopySubjectSticker()
    }

    @objc private func handleMenuToggleExpand() {
        toggleExpandSheet()
    }

    @objc private func handleSelectEngineFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = SearchEngine(rawValue: raw) else { return }
        switchToSearchEngine(engine)
    }

    @objc private func handleSelectWebThemeFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AppTheme(rawValue: raw) else { return }
        applyWebResultsTheme(mode)
    }

    private func cycleWebResultsTheme() {
        let all = AppTheme.allCases
        let current = AppSettings.shared.webResultsTheme
        let nextIdx = ((all.firstIndex(of: current) ?? 0) + 1) % all.count
        applyWebResultsTheme(all[nextIdx])
    }

    private func applyWebResultsTheme(_ mode: AppTheme) {
        AppSettings.shared.webResultsTheme = mode
        syncWebViewAppearance()
        let label = (mode == .system) ? "Auto (\(isEffectiveDarkMode ? "Dark" : "Light"))" : "\(mode.title) Mode"
        onShowToast("Results browser: \(label)")
    }

    private func showLoadingOverlay(status: String) {
        loadingFallbackTask?.cancel()
        loadingStatusLabel.stringValue = status
        webView.alphaValue = 0.0
        if loadingOverlay.isHidden {
            loadingOverlay.alphaValue = 0
            loadingOverlay.isHidden = false
        }
        startLoaderAnimations()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.20)
            ctx.timingFunction = AppleMotion.easeOut
            loadingOverlay.animator().alphaValue = 1.0
        }
        loadingFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_800_000_000)
            guard !Task.isCancelled else { return }
            self?.fadeOutLoadingOverlay()
        }
    }

    private func cycleSearchEngine() {
        let all = SearchEngine.allCases
        let current = AppSettings.shared.searchEngine
        let nextIdx = ((all.firstIndex(of: current) ?? 0) + 1) % all.count
        switchToSearchEngine(all[nextIdx])
    }

    private func switchToSearchEngine(_ next: SearchEngine) {
        AppSettings.shared.searchEngine = next
        engineButton?.title = next.shortTitle
        engineButton?.toolTip = "Switch Search Engine (\(next.title))"
        engineButton?.updateSymbol(next.symbolName, pointSize: 10.5, weight: .semibold)
        errorStateCard.isHidden = true
        leaveLowInfoStateIfNeeded()

        let typed = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackQuery = !currentPreviewText.isEmpty
            ? currentPreviewText
            : (currentClassificationLabels.first?.replacingOccurrences(of: "_", with: " ") ?? "visual screen selection")
        let query = !typed.isEmpty ? typed : fallbackQuery

        if next == .aiExplain {
            startAIExplanationStream(prompt: "Explain this selection clearly: \(query)", forceShow: true)
        }
        if next == .googleLens, let base = baseLensURL {
            showLoadingOverlay(status: "Switching to Google Lens…")
            webView.load(URLRequest(url: base))
        } else if let url = next.searchURL(for: query) {
            showLoadingOverlay(status: "Searching on \(next.title)…")
            webView.load(URLRequest(url: url))
        }
    }

    private func handleTryFallbackSearchEngine() {
        let current = AppSettings.shared.searchEngine
        let fallback: SearchEngine = (current == .googleLens) ? .perplexity : (current == .perplexity ? .bing : .google)
        switchToSearchEngine(fallback)
    }

    @objc private func handleMultisearchSubmit() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        leaveLowInfoStateIfNeeded()
        startAIExplanationStream(prompt: query)

        let engine = AppSettings.shared.searchEngine
        showLoadingOverlay(status: "Searching with \(engine.title)…")

        if engine == .googleLens, let base = baseLensURL {
            let url = GoogleLensService.multisearchURL(from: base, query: query)
            webView.load(URLRequest(url: url))
        } else if let url = engine.searchURL(for: query) {
            webView.load(URLRequest(url: url))
        }
    }

    @objc private func handleBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    @objc private func handleCopyImage() { onCopyImage() }
    @objc private func handleSaveImage() { onSaveImage() }

    @objc private func handleOpenInBrowser() {
        if let current = webView.url, !current.path.hasPrefix("/sorry") {
            onOpenExternalURL(current)
        } else if let base = baseLensURL {
            onOpenExternalURL(base)
        } else if let url = URL(string: "https://lens.google.com/") {
            onCopyImage()
            onOpenExternalURL(url)
        }
    }

    @objc private func handleClose() { onClose() }

    @objc private func handleSearchText() {
        let typed = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = !typed.isEmpty ? typed : currentPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            if let base = baseLensURL {
                showLoadingOverlay(status: "Refreshing visual matches…")
                webView.load(URLRequest(url: base))
            }
            return
        }
        leaveLowInfoStateIfNeeded()
        let engine = AppSettings.shared.searchEngine == .googleLens ? SearchEngine.google : AppSettings.shared.searchEngine
        guard let url = engine.searchURL(for: query) else { return }
        showLoadingOverlay(status: "Searching on \(engine.title)…")
        webView.load(URLRequest(url: url))
    }

    @objc private func handleTranslateText() {
        if !currentBlocks.isEmpty {
            onTranslateInPlace(currentBlocks)
            onShowToast("Translated text overlaid in-place on selection")
        }
        let query = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/?sl=auto&tl=en&text=\(encoded)") else {
            if let base = baseLensURL {
                let url = GoogleLensService.multisearchURL(from: base, query: "translate to English")
                showLoadingOverlay(status: "Translating image text…")
                webView.load(URLRequest(url: url))
            }
            return
        }
        showLoadingOverlay(status: "Translating…")
        webView.load(URLRequest(url: url))
    }

    @objc private func handleExplainSelection() {
        let typed = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextText = currentPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        let customPrompt = !typed.isEmpty
            ? typed
            : (contextText.isEmpty ? "Explain what is shown in this image and why it matters." : "Explain this clearly: \(contextText)")
        startAIExplanationStream(prompt: customPrompt, forceShow: true)

        if let base = baseLensURL {
            let url = GoogleLensService.multisearchURL(from: base, query: customPrompt)
            showLoadingOverlay(status: "Asking AI about selection…")
            webView.load(URLRequest(url: url))
        } else if let url = SearchEngine.aiExplain.searchURL(for: !contextText.isEmpty ? contextText : "Explain selected screen item") {
            showLoadingOverlay(status: "Asking AI…")
            webView.load(URLRequest(url: url))
        }
    }

    func markLensUploadStarted() {
        hasTriggeredLensUpload = true
    }

    func applyInitialTab(_ idx: Int) {
        resultsModeSegmented?.setSelectedIndex(idx, animated: false)
        handleResultsModeChanged(idx)
    }

    private func handleResultsModeChanged(_ idx: Int) {
        let isLensTab = (idx == 1)
        webOuterCard.isHidden = !isLensTab
        answerContextCard?.isHidden = isLensTab
        aiAnswerCard.isHidden = isLensTab && currentAIExplanation.isEmpty && KeychainHelper.loadAPIKey().isEmpty && currentMathSolution == nil
        if !isLensTab && aiAnswerCard.isHidden {
            startAIExplanationStream(prompt: "Explain this selection concisely in 1 to 3 sentences.", forceShow: true)
        }
        if isLensTab && !hasTriggeredLensUpload {
            triggerLazyLensUpload()
        }
    }

    private func triggerLazyLensUpload() {
        guard !hasTriggeredLensUpload else { return }
        hasTriggeredLensUpload = true
        let imgToSend = croppedCGImage
        showLoadingOverlay(status: "Searching with \(AppSettings.shared.searchEngine.shortTitle)…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let existingCookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            do {
                let upload = try await GoogleLensService.uploadImage(imgToSend, existingCookies: existingCookies)
                self.loadLensResults(upload)
            } catch {
                self.showLensError(error.localizedDescription)
            }
        }
    }

    @objc private func handleFollowUpSubmit() {
        let q = followUpField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        startAIExplanationStream(prompt: q, forceShow: true)
    }

    private func handleAddToContacts() {
        if let email = currentDetectedEmails.first,
           let url = URL(string: "mailto:\(email)") {
            NSWorkspace.shared.open(url)
        } else if let phone = currentDetectedPhones.first {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(phone, forType: .string)
            onShowToast("Copied phone \(phone) — ready for Contacts")
        }
    }

    private func handleAddToCalendar() {
        if let firstDate = currentDetectedDates.first {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(formatter.string(from: firstDate), forType: .string)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
            onShowToast("Opened Calendar • Date copied")
        }
    }

    private func handleCopyTable() {
        let payload = currentTableTSV ?? currentTableCSV ?? ""
        guard !payload.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        onShowToast("Copied table as TSV")
    }

    private func scrollWebResults(toVisualMatches: Bool) {
        guard webView != nil else { return }
        let js: String
        if !toVisualMatches {
            js = "window.scrollTo({ top: 0, behavior: 'smooth' });"
        } else {
            js = """
            (function() {
                var headings = document.querySelectorAll('h1, h2, h3, [role="heading"], div, span');
                for (var i = 0; i < headings.length; i++) {
                    var txt = (headings[i].textContent || '').trim();
                    if (/^(Visual matches|Exact matches|Related searches|Similar images)$/i.test(txt)) {
                        headings[i].scrollIntoView({ behavior: 'smooth', block: 'start' });
                        return;
                    }
                }
                window.scrollTo({ top: Math.max(420, Math.round(document.body.scrollHeight * 0.45)), behavior: 'smooth' });
            })();
            """
        }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc private func handleCopyAIExplanation() {
        guard !currentAIExplanation.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentAIExplanation, forType: .string)
        aiCopyButton.title = "Copied!"
        onShowToast("Copied AI answer to clipboard")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.aiCopyButton.title = "Copy"
        }
    }

    @objc private func handleCopyText() {
        let textToCopy = currentText.isEmpty ? currentPreviewText : currentText
        guard !textToCopy.isEmpty else {
            onCopyImage()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        snippetCopyButton.title = "Copied!"
        copyTextChip.title = "Copied!"
        onShowToast("Copied text to clipboard")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.snippetCopyButton.title = "Copy"
            self?.copyTextChip.title = "Copy Text"
        }
    }

    @objc private func handleOpenDetectedURL() {
        if let url = currentURL {
            onOpenExternalURL(url)
        }
    }

    @objc private func handleCopyMathResult() {
        guard let math = currentMathSolution else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(math.result, forType: .string)
        onShowToast("Copied \(math.expression) = \(math.result)")
    }

    @objc private func handleCopyColorHex() {
        guard !currentHexColor.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentHexColor, forType: .string)
        onShowToast("Copied color \(currentHexColor) to clipboard")
    }

    private func makeGlassCircleButton(
        symbol: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        tooltip: String,
        action: @escaping () -> Void
    ) -> LiquidGlassButton {
        LiquidGlassButton(
            symbol: symbol,
            symbolPointSize: pointSize,
            symbolWeight: weight,
            tooltip: tooltip,
            fixedSize: CGSize(width: 26, height: 26),
            style: .regular,
            foregroundColor: .labelColor,
            onAction: action
        )
    }

    private func makeGlassChip(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> LiquidGlassButton {
        LiquidGlassButton(
            symbol: symbol,
            symbolPointSize: 10.5,
            symbolWeight: .medium,
            title: title,
            tooltip: title,
            height: 25,
            style: .regular,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 11, weight: .medium),
            onAction: action
        )
    }
}

// MARK: - Crisp Vector Google 'G' Badge

private final class GoogleGLogoView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.40
        let lineWidth = radius * 0.40

        let segments: [(CGFloat, CGFloat, NSColor)] = [
            (315, 360, NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)),
            (45, 145, NSColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1)),
            (145, 220, NSColor(red: 0.98, green: 0.74, blue: 0.02, alpha: 1)),
            (220, 315, NSColor(red: 0.20, green: 0.66, blue: 0.33, alpha: 1))
        ]

        for (start, end, color) in segments {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .butt
            color.setStroke()
            arc.stroke()
        }

        let bar = NSBezierPath()
        bar.move(to: CGPoint(x: center.x, y: center.y))
        bar.line(to: CGPoint(x: center.x + radius + lineWidth * 0.45, y: center.y))
        bar.lineWidth = lineWidth * 0.92
        NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1).setStroke()
        bar.stroke()
    }
}

// MARK: - Retina 4-Point Sparkle Star Texture Factory

private enum SparkleFactory {
    private static let cachedSparkleImage: CGImage? = renderSparkleCGImage()
    private static let cachedOrbFlareImage: CGImage? = renderOrbFlareCGImage()

    static func makeSparkleCGImage() -> CGImage? {
        cachedSparkleImage
    }

    static func makeOrbFlareCGImage() -> CGImage? {
        cachedOrbFlareImage
    }

    private static func renderSparkleCGImage() -> CGImage? {
        let size = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)

        // Soft diffused starlight halo
        let colors = [
            NSColor.white.withAlphaComponent(0.90).cgColor,
            NSColor(red: 0.72, green: 0.88, blue: 1.0, alpha: 0.32).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.36, 1]) {
            ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: 28, options: [])
        }

        // Sleek concave 4-point star silhouette
        ctx.setFillColor(NSColor.white.cgColor)
        let star = CGMutablePath()
        let outer: CGFloat = 21.0
        let waist: CGFloat = 2.8
        star.move(to: CGPoint(x: center.x, y: center.y - outer))
        star.addQuadCurve(
            to: CGPoint(x: center.x + outer, y: center.y),
            control: CGPoint(x: center.x + waist, y: center.y - waist)
        )
        star.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y + outer),
            control: CGPoint(x: center.x + waist, y: center.y + waist)
        )
        star.addQuadCurve(
            to: CGPoint(x: center.x - outer, y: center.y),
            control: CGPoint(x: center.x - waist, y: center.y + waist)
        )
        star.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y - outer),
            control: CGPoint(x: center.x - waist, y: center.y - waist)
        )
        star.closeSubpath()
        ctx.addPath(star)
        ctx.fillPath()

        return ctx.makeImage()
    }

    private static func renderOrbFlareCGImage() -> CGImage? {
        let size = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        let colors = [
            NSColor.white.cgColor,
            NSColor.white.withAlphaComponent(0.92).cgColor,
            NSColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 0.42).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 0.24, 0.56, 1.0]) {
            ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: 30, options: [])
        }
        return ctx.makeImage()
    }
}
