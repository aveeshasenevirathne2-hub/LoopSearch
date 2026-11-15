import AppKit
import QuartzCore

/// Apple-style physics springs (`dampingRatio` + `response`) and smooth ease-in / ease-out curves.
@MainActor
enum AppleMotion {
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
    static let easeInOut = CAMediaTimingFunction(controlPoints: 0.65, 0.0, 0.35, 1.0)
    static let easeIn = CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.67, 0.0)

    static func duration(_ base: TimeInterval) -> TimeInterval {
        if AppSettings.shared.effectiveReduceMotion {
            return max(0.05, base * 0.35)
        }
        return base * AppSettings.shared.motionFeel.durationScale
    }

    static func spring(
        keyPath: String,
        from: Any? = nil,
        to: Any? = nil,
        dampingRatio: CGFloat = 0.85,
        response: Double = 0.42,
        initialVelocity: CGFloat = 0
    ) -> CASpringAnimation {
        let reduced = AppSettings.shared.effectiveReduceMotion
        let scaledResponse = reduced
            ? 0.14
            : max(0.08, response * AppSettings.shared.motionFeel.durationScale)
        let effectiveDamping: CGFloat = reduced ? 1.0 : dampingRatio
        let anim = CASpringAnimation(keyPath: keyPath)
        anim.mass = 1.0
        let omega = (2.0 * .pi) / scaledResponse
        anim.stiffness = omega * omega
        anim.damping = 2.0 * effectiveDamping * omega
        anim.initialVelocity = reduced ? 0 : initialVelocity
        anim.fromValue = from
        anim.toValue = to
        anim.duration = anim.settlingDuration
        return anim
    }

    static func animateVisibility(
        _ view: NSView,
        visible: Bool,
        scale: CGFloat = 0.95,
        duration baseDuration: TimeInterval = 0.24
    ) {
        view.wantsLayer = true
        if visible {
            if !view.isHidden && view.alphaValue > 0.99 { return }
            view.alphaValue = 0
            view.isHidden = false
            view.layoutSubtreeIfNeeded()
            if let layer = view.layer {
                let start = centeredTransform(bounds: view.bounds, scale: scale)
                let springAnim = spring(
                    keyPath: "transform",
                    from: layer.presentation()?.transform ?? start,
                    to: CATransform3DIdentity,
                    dampingRatio: 0.84,
                    response: max(0.24, baseDuration * 1.15)
                )
                layer.transform = CATransform3DIdentity
                layer.add(springAnim, forKey: "visSpring")
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration(baseDuration)
                ctx.timingFunction = easeOut
                view.animator().alphaValue = 1.0
            }
        } else {
            if view.isHidden { return }
            if let layer = view.layer {
                let end = centeredTransform(bounds: view.bounds, scale: scale)
                let anim = CABasicAnimation(keyPath: "transform")
                anim.fromValue = layer.presentation()?.transform ?? layer.transform
                anim.toValue = end
                anim.duration = duration(baseDuration * 0.8)
                anim.timingFunction = easeIn
                layer.transform = end
                layer.add(anim, forKey: "visSpring")
            }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration(baseDuration * 0.8)
                ctx.timingFunction = easeIn
                view.animator().alphaValue = 0.0
            }, completionHandler: {
                Task { @MainActor in
                    if view.alphaValue < 0.05 {
                        view.isHidden = true
                        view.layer?.transform = CATransform3DIdentity
                    }
                }
            })
        }
    }

    static func centeredTransform(
        bounds: CGRect,
        scale: CGFloat = 1.0,
        scaleX: CGFloat? = nil,
        scaleY: CGFloat? = nil,
        rotationZ: CGFloat = 0.0,
        translation: CGPoint = .zero
    ) -> CATransform3D {
        let sx = scaleX ?? scale
        let sy = scaleY ?? scale
        let cx = bounds.midX
        let cy = bounds.midY
        var t = CATransform3DMakeTranslation(translation.x, translation.y, 0)
        t = CATransform3DTranslate(t, cx, cy, 0)
        if abs(rotationZ) > 0.0001 {
            t = CATransform3DRotate(t, rotationZ, 0, 0, 1)
        }
        t = CATransform3DScale(t, sx, sy, 1)
        t = CATransform3DTranslate(t, -cx, -cy, 0)
        return t
    }

    static func springScale(
        layer: CALayer,
        bounds: CGRect,
        scale: CGFloat = 1.0,
        scaleX: CGFloat? = nil,
        scaleY: CGFloat? = nil,
        rotationZ: CGFloat = 0.0,
        dampingRatio: CGFloat = 0.80,
        response: Double = 0.30,
        key: String = "scaleSpring"
    ) {
        let target = centeredTransform(bounds: bounds, scale: scale, scaleX: scaleX, scaleY: scaleY, rotationZ: rotationZ)
        let from = layer.presentation()?.transform ?? layer.transform
        let anim = spring(
            keyPath: "transform",
            from: from,
            to: target,
            dampingRatio: dampingRatio,
            response: response
        )
        layer.transform = target
        layer.add(anim, forKey: key)
    }

    /// Kinetic Horizon Emergence Spring: elements rise from the bottom cyan-white horizon pool with a subtle perspective tilt (`rotationZ`), vertical rise, and spring scale.
    static func kineticHorizonSpring(
        view: NSView,
        fromTilt: CGFloat = -0.042,
        fromY: CGFloat = 18.0,
        fromScale: CGFloat = 0.94,
        dampingRatio: CGFloat = 0.82,
        response: Double = 0.44,
        delay: TimeInterval = 0.0,
        key: String = "kineticHorizonSpring"
    ) {
        guard !AppSettings.shared.effectiveReduceMotion else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let b = view.bounds.width > 1 ? view.bounds : CGRect(x: 0, y: 0, width: 260, height: 48)
        let startXform = centeredTransform(
            bounds: b,
            scale: fromScale,
            rotationZ: fromTilt,
            translation: CGPoint(x: 0, y: fromY)
        )
        let now = CACurrentMediaTime()
        let springAnim = spring(
            keyPath: "transform",
            from: startXform,
            to: CATransform3DIdentity,
            dampingRatio: dampingRatio,
            response: response
        )
        springAnim.beginTime = now + delay
        springAnim.fillMode = .backwards
        layer.transform = CATransform3DIdentity
        layer.add(springAnim, forKey: key)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        fade.duration = duration(0.28)
        fade.beginTime = now + delay
        fade.fillMode = .backwards
        fade.timingFunction = easeOut
        layer.opacity = 1.0
        layer.add(fade, forKey: "\(key)_fade")
    }
}

/// 2D rubber-band clamping and exponential momentum settling for floating Liquid Glass surfaces.
@MainActor
struct DragInertiaEngine {
    var isDragging = false
    var isSettling = false
    var dragStartOrigin = CGPoint.zero
    var velocity = CGPoint.zero
    private var hasPushedDragCursor = false

    mutating func beginDrag(origin: CGPoint) {
        isDragging = true
        isSettling = false
        dragStartOrigin = origin
        velocity = .zero
    }

    mutating func pushCursorIfNeeded() {
        if !hasPushedDragCursor {
            NSCursor.closedHand.push()
            hasPushedDragCursor = true
        }
    }

    mutating func popCursorIfNeeded() {
        if hasPushedDragCursor {
            NSCursor.pop()
            hasPushedDragCursor = false
        }
    }

    mutating func handlePan(
        _ pan: NSPanGestureRecognizer,
        in canvas: NSView?,
        currentOrigin: () -> CGPoint,
        allowedBounds: () -> CGRect,
        applyOrigin: (CGPoint) -> Void,
        onGrabChanged: (Bool) -> Void
    ) {
        guard let canvas else { return }
        switch pan.state {
        case .began:
            beginDrag(origin: currentOrigin())
            pushCursorIfNeeded()
            onGrabChanged(true)
        case .changed:
            let next = draggedOrigin(translation: pan.translation(in: canvas), in: allowedBounds())
            applyOrigin(next)
        case .ended, .cancelled, .failed:
            popCursorIfNeeded()
            endDrag(velocity: pan.velocity(in: canvas))
            onGrabChanged(false)
        default:
            break
        }
    }

    func draggedOrigin(translation: CGPoint, in allowedBounds: CGRect) -> CGPoint {
        let rawX = dragStartOrigin.x + translation.x
        let rawY = dragStartOrigin.y + translation.y
        return CGPoint(
            x: Self.rubberBand(rawX, min: allowedBounds.minX, max: allowedBounds.maxX),
            y: Self.rubberBand(rawY, min: allowedBounds.minY, max: allowedBounds.maxY)
        )
    }

    mutating func endDrag(velocity rawVelocity: CGPoint) {
        isDragging = false
        let speed = hypot(rawVelocity.x, rawVelocity.y)
        let maxSpeed: CGFloat = 1400
        if speed > maxSpeed {
            let factor = maxSpeed / speed
            velocity = CGPoint(x: rawVelocity.x * factor, y: rawVelocity.y * factor)
        } else {
            velocity = rawVelocity
        }
        isSettling = true
    }

    mutating func step(origin: CGPoint, in allowedBounds: CGRect, dt: CFTimeInterval) -> CGPoint? {
        guard isSettling, !isDragging, dt > 0 else { return nil }
        var pos = origin
        pos.x += velocity.x * CGFloat(dt)
        pos.y += velocity.y * CGFloat(dt)

        let decay = CGFloat(exp(-12.5 * dt))
        velocity.x *= decay
        velocity.y *= decay

        let springPull = CGFloat(1.0 - exp(-22.0 * dt))
        let clampedX = min(max(pos.x, allowedBounds.minX), allowedBounds.maxX)
        let clampedY = min(max(pos.y, allowedBounds.minY), allowedBounds.maxY)

        if pos.x != clampedX {
            pos.x += (clampedX - pos.x) * springPull
            velocity.x *= CGFloat(exp(-24.0 * dt))
        }
        if pos.y != clampedY {
            pos.y += (clampedY - pos.y) * springPull
            velocity.y *= CGFloat(exp(-24.0 * dt))
        }

        let speed = hypot(velocity.x, velocity.y)
        if speed < 8, abs(pos.x - clampedX) < 0.35, abs(pos.y - clampedY) < 0.35 {
            velocity = .zero
            isSettling = false
            return CGPoint(x: clampedX, y: clampedY)
        }
        return pos
    }

    static func shouldAllowDragStart(
        in host: NSView,
        event: NSEvent,
        excludingRoots: [NSView] = []
    ) -> Bool {
        guard let superPt = host.superview?.convert(event.locationInWindow, from: nil),
              let hit = host.hitTest(superPt) else {
            return false
        }
        var cursor: NSView? = hit
        while let current = cursor, current !== host {
            if current is LiquidGlassButton
                || current is LiquidGlassSegmentedControl
                || current is LiquidGlassToggle
                || current is NSTextView
                || excludingRoots.contains(where: { $0 === current }) {
                return false
            }
            if let field = current as? NSTextField, field.isEditable || field.isSelectable {
                return false
            }
            cursor = current.superview
        }
        return true
    }

    private static func rubberBand(_ value: CGFloat, min: CGFloat, max: CGFloat, limit: CGFloat = 52) -> CGFloat {
        if value < min {
            let d = min - value
            return min - (d * 0.28 * limit) / (d * 0.28 + limit)
        }
        if value > max {
            let d = value - max
            return max + (d * 0.28 * limit) / (d * 0.28 + limit)
        }
        return value
    }
}

/// Visual style mapping across macOS Tahoe (26+) native `NSGlassEffectView` and earlier macOS fallback.
enum LiquidGlassStyle {
    case regular
    case clear
}

extension NSView {
    var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// Renders the signature deep-obsidian squircle lighting matching the Horizon aesthetic:
/// 1) Top-edge crisp metallic silver-charcoal dome reflection + specular rim
/// 2) Bottom-up incandescent white-ice -> electric sky-cyan -> vivid azure -> soft indigo-violet -> pitch-obsidian Horizon Light Pool
/// 3) Optional active Blue Search Glow animation (`isSearchPulseActive`) with dual undulating horizon waves and rising light tide
@MainActor
final class HorizonLightWellView: NSView {
    var cornerRadius: CGFloat {
        didSet { if oldValue != cornerRadius { updateLayers() } }
    }
    var intensity: CGFloat {
        didSet { if abs(oldValue - intensity) > 0.005 { updateLayers() } }
    }
    var poolHeightFraction: CGFloat = 0.44 {
        didSet { if oldValue != poolHeightFraction { updateLayers() } }
    }
    var baseObsidianDarkness: CGFloat = 0.0 {
        didSet { if oldValue != baseObsidianDarkness { updateLayers() } }
    }
    var rimStrength: CGFloat = 0.28 {
        didSet { if oldValue != rimStrength { updateLayers() } }
    }
    var isSearchPulseActive: Bool = false {
        didSet {
            if oldValue != isSearchPulseActive {
                updateLayers()
                updateWaveAnimations()
            }
        }
    }
    // Retained for call-site compatibility; continuous motion is 100% GPU-composited now.
    var wavePhase: Double = 0.0

    private var continuousWaveEnabled = false
    private let clipContainer = CALayer()
    private let obsidianFillLayer = CALayer()
    private let axialPoolLayer = CAGradientLayer()
    private let radialCoreLayer = CAGradientLayer()
    private let secondaryWaveLayer = CAGradientLayer()
    private let topDomeSheenLayer = CAGradientLayer()
    private let rimGradientLayer = CAGradientLayer()
    private let rimMaskLayer = CAShapeLayer()
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?

    init(cornerRadius: CGFloat, intensity: CGFloat = 0.0) {
        self.cornerRadius = cornerRadius
        self.intensity = intensity
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        setupLayers()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .circleToSearchSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateLayers()
                self?.updateWaveAnimations()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setContinuousWaveEnabled(_ enabled: Bool) {
        continuousWaveEnabled = enabled
        updateWaveAnimations()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.contentsScale = scale
        clipContainer.contentsScale = scale
        axialPoolLayer.contentsScale = scale
        radialCoreLayer.contentsScale = scale
        secondaryWaveLayer.contentsScale = scale
        topDomeSheenLayer.contentsScale = scale
        rimGradientLayer.contentsScale = scale
        rimMaskLayer.contentsScale = scale
        updateLayers()
        updateWaveAnimations()
    }

    override func layout() {
        super.layout()
        updateLayers()
    }

    private func setupLayers() {
        guard let root = layer else { return }

        clipContainer.masksToBounds = true
        root.addSublayer(clipContainer)

        clipContainer.addSublayer(obsidianFillLayer)

        axialPoolLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        axialPoolLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        clipContainer.addSublayer(axialPoolLayer)

        radialCoreLayer.type = .radial
        radialCoreLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        radialCoreLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        clipContainer.addSublayer(radialCoreLayer)

        secondaryWaveLayer.type = .radial
        secondaryWaveLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        secondaryWaveLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        secondaryWaveLayer.isHidden = true
        clipContainer.addSublayer(secondaryWaveLayer)

        topDomeSheenLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        topDomeSheenLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        clipContainer.addSublayer(topDomeSheenLayer)

        rimGradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        rimGradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        rimMaskLayer.fillColor = nil
        rimMaskLayer.strokeColor = NSColor.white.cgColor
        rimGradientLayer.mask = rimMaskLayer
        root.addSublayer(rimGradientLayer)
    }

    private func updateLayers() {
        let w = bounds.width
        let h = bounds.height
        guard w > 2, h > 2 else { return }

        let dark = isDarkAppearance
        let gMult = CGFloat(AppSettings.shared.glowIntensity.opacityMultiplier)
        let reduceScale: CGFloat = AppSettings.shared.effectiveReduceMotion ? 0.55 : 1.0
        let searchBoost: CGFloat = isSearchPulseActive ? 0.20 : 0.0
        let effIntensity = max(0.0, min(1.45, (intensity + searchBoost) * gMult * reduceScale))
        let effRim = max(0.0, min(1.20, rimStrength * (0.35 + 0.65 * gMult) * reduceScale))

        let r = min(cornerRadius, min(w, h) * 0.5)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        clipContainer.frame = bounds
        clipContainer.cornerRadius = r

        if baseObsidianDarkness > 0.01 && dark {
            obsidianFillLayer.isHidden = false
            obsidianFillLayer.frame = bounds
            obsidianFillLayer.backgroundColor = NSColor(red: 0.012, green: 0.016, blue: 0.034, alpha: baseObsidianDarkness).cgColor
        } else {
            obsidianFillLayer.isHidden = true
        }

        if effIntensity > 0.015 {
            let poolH = max(14.0, h * min(0.74, poolHeightFraction))
            let darkScale: CGFloat = dark ? 1.0 : 0.38
            let a = effIntensity * darkScale

            axialPoolLayer.isHidden = false
            axialPoolLayer.frame = CGRect(x: 0, y: 0, width: w, height: poolH)
            axialPoolLayer.colors = [
                NSColor(red: 0.88, green: 0.98, blue: 1.00, alpha: min(1.0, 0.86 * a)).cgColor,
                NSColor(red: 0.14, green: 0.76, blue: 1.00, alpha: min(1.0, 0.76 * a)).cgColor,
                NSColor(red: 0.02, green: 0.50, blue: 0.98, alpha: min(1.0, 0.60 * a)).cgColor,
                NSColor(red: 0.16, green: 0.21, blue: 0.56, alpha: min(1.0, 0.38 * a)).cgColor,
                NSColor(red: 0.04, green: 0.10, blue: 0.30, alpha: min(1.0, 0.18 * a)).cgColor,
                NSColor.clear.cgColor
            ]
            axialPoolLayer.locations = [0.0, 0.11, 0.25, 0.44, 0.68, 1.0]

            let coreRX = max(w * 0.64, 34.0)
            let coreRY = max(poolH * (isSearchPulseActive ? 0.98 : 0.84), 16.0)
            radialCoreLayer.isHidden = false
            radialCoreLayer.bounds = CGRect(x: 0, y: 0, width: coreRX * 2.0, height: coreRY * 2.0)
            radialCoreLayer.position = CGPoint(x: w * 0.5, y: -h * 0.02)
            radialCoreLayer.colors = [
                NSColor(red: 0.94, green: 0.99, blue: 1.00, alpha: min(1.0, 0.90 * a)).cgColor,
                NSColor(red: 0.20, green: 0.82, blue: 1.00, alpha: min(1.0, 0.72 * a)).cgColor,
                NSColor(red: 0.04, green: 0.46, blue: 0.98, alpha: min(1.0, 0.38 * a)).cgColor,
                NSColor(red: 0.16, green: 0.22, blue: 0.58, alpha: min(1.0, 0.18 * a)).cgColor,
                NSColor.clear.cgColor
            ]
            radialCoreLayer.locations = [0.0, 0.22, 0.50, 0.76, 1.0]

            if isSearchPulseActive {
                let secRX = max(w * 0.52, 28.0)
                let secRY = max(poolH * 0.68, 14.0)
                secondaryWaveLayer.isHidden = false
                secondaryWaveLayer.bounds = CGRect(x: 0, y: 0, width: secRX * 2.0, height: secRY * 2.0)
                secondaryWaveLayer.position = CGPoint(x: w * 0.5, y: poolH * 0.10)
                secondaryWaveLayer.colors = [
                    NSColor(red: 0.68, green: 0.95, blue: 1.00, alpha: min(1.0, 0.48 * a)).cgColor,
                    NSColor(red: 0.06, green: 0.62, blue: 1.00, alpha: min(1.0, 0.30 * a)).cgColor,
                    NSColor.clear.cgColor
                ]
                secondaryWaveLayer.locations = [0.0, 0.45, 1.0]
            } else {
                secondaryWaveLayer.isHidden = true
            }
        } else {
            axialPoolLayer.isHidden = true
            radialCoreLayer.isHidden = true
            secondaryWaveLayer.isHidden = true
        }

        if effRim > 0.35 || baseObsidianDarkness > 0.5 {
            let domeBoost: CGFloat = (baseObsidianDarkness > 0.5 && dark) ? 1.65 : 0.75
            let sheenAlpha: CGFloat = min(0.42, (dark ? 0.11 : 0.18) * effRim * domeBoost)
            topDomeSheenLayer.isHidden = false
            topDomeSheenLayer.frame = CGRect(x: 0, y: h * 0.60, width: w, height: h * 0.40)
            topDomeSheenLayer.colors = [
                NSColor(red: 0.60, green: 0.63, blue: 0.68, alpha: sheenAlpha).cgColor,
                NSColor(red: 0.30, green: 0.32, blue: 0.37, alpha: sheenAlpha * 0.42).cgColor,
                NSColor.clear.cgColor
            ]
            topDomeSheenLayer.locations = [0.0, 0.38, 1.0]
        } else {
            topDomeSheenLayer.isHidden = true
        }

        if effRim > 0.01 {
            let hasHorizonGlow = effIntensity > 0.04
            let strokeWidth: CGFloat = hasHorizonGlow ? 1.15 : 0.85
            let insetRect = bounds.insetBy(dx: strokeWidth * 0.5, dy: strokeWidth * 0.5)
            let insetR = max(0, r - strokeWidth * 0.5)
            rimGradientLayer.isHidden = false
            rimGradientLayer.frame = bounds
            rimMaskLayer.frame = bounds
            rimMaskLayer.lineWidth = strokeWidth
            rimMaskLayer.path = (insetRect.width > 1 && insetRect.height > 1)
                ? CGPath(roundedRect: insetRect, cornerWidth: insetR, cornerHeight: insetR, transform: nil)
                : nil

            if hasHorizonGlow {
                let topRimAlpha = min(1.0, (dark ? 0.46 : 0.55) * effRim)
                let midRimAlpha = min(1.0, (dark ? 0.09 : 0.16) * effRim)
                let lowCyanAlpha = min(1.0, (dark ? 0.62 : 0.42) * effIntensity)
                let botWhiteCyanAlpha = min(1.0, (dark ? 0.88 : 0.56) * effIntensity)
                rimGradientLayer.colors = [
                    NSColor(red: 0.88, green: 0.91, blue: 0.96, alpha: topRimAlpha).cgColor,
                    NSColor(red: 0.58, green: 0.64, blue: 0.74, alpha: topRimAlpha * 0.35).cgColor,
                    NSColor(red: 0.22, green: 0.34, blue: 0.66, alpha: midRimAlpha).cgColor,
                    NSColor(red: 0.12, green: 0.74, blue: 1.00, alpha: lowCyanAlpha).cgColor,
                    NSColor(red: 0.90, green: 0.98, blue: 1.00, alpha: botWhiteCyanAlpha).cgColor
                ]
                rimGradientLayer.locations = [0.0, 0.18, 0.52, 0.84, 1.0]
            } else {
                let quietTop = min(0.24, (dark ? 0.13 : 0.18) * max(0.5, gMult))
                let quietBot = min(0.12, (dark ? 0.05 : 0.08) * max(0.5, gMult))
                rimGradientLayer.colors = [
                    NSColor.white.withAlphaComponent(quietTop).cgColor,
                    NSColor.white.withAlphaComponent(quietBot).cgColor
                ]
                rimGradientLayer.locations = [0.0, 1.0]
            }
        } else {
            rimGradientLayer.isHidden = true
        }

        CATransaction.commit()
    }

    private func updateWaveAnimations() {
        let shouldAnimate = (continuousWaveEnabled || isSearchPulseActive)
            && window != nil
            && !AppSettings.shared.effectiveReduceMotion
            && (intensity > 0.015 || isSearchPulseActive)

        guard shouldAnimate else {
            radialCoreLayer.removeAllAnimations()
            secondaryWaveLayer.removeAllAnimations()
            axialPoolLayer.removeAllAnimations()
            return
        }

        let sine = CAMediaTimingFunction(controlPoints: 0.45, 0.05, 0.55, 0.95)
        let driftSpan = max(14.0, bounds.width * (isSearchPulseActive ? 0.12 : 0.055))

        if radialCoreLayer.animation(forKey: "gpuHorizonDrift") == nil {
            let drift = CABasicAnimation(keyPath: "transform.translation.x")
            drift.fromValue = -driftSpan
            drift.toValue = driftSpan
            drift.duration = isSearchPulseActive ? 2.6 : 4.2
            drift.autoreverses = true
            drift.timingFunction = sine
            drift.repeatCount = .infinity
            drift.isRemovedOnCompletion = false
            radialCoreLayer.add(drift, forKey: "gpuHorizonDrift")

            let tide = CABasicAnimation(keyPath: "transform.scale.y")
            tide.fromValue = 0.94
            tide.toValue = isSearchPulseActive ? 1.12 : 1.06
            tide.duration = isSearchPulseActive ? 2.1 : 3.4
            tide.autoreverses = true
            tide.timingFunction = sine
            tide.repeatCount = .infinity
            tide.isRemovedOnCompletion = false
            radialCoreLayer.add(tide, forKey: "gpuHorizonTide")
        }

        if isSearchPulseActive, secondaryWaveLayer.animation(forKey: "gpuSecondaryDrift") == nil {
            let drift = CABasicAnimation(keyPath: "transform.translation.x")
            drift.fromValue = driftSpan * 1.1
            drift.toValue = -driftSpan * 1.1
            drift.duration = 3.1
            drift.autoreverses = true
            drift.timingFunction = sine
            drift.repeatCount = .infinity
            drift.isRemovedOnCompletion = false
            secondaryWaveLayer.add(drift, forKey: "gpuSecondaryDrift")
        } else if !isSearchPulseActive {
            secondaryWaveLayer.removeAllAnimations()
        }
    }
}

/// Precision Dual-Arc Radial Tick-Mark Dial + Glowing Diamond-Tapered Indicator Needle Beam.
/// Matches the chronograph / vision radar aesthetic with outer & inner micro-tick arcs and proximity tick illumination.
@MainActor
final class PrecisionDialArcView: NSView {
    enum DialStyle {
        case chronograph
        case compactWatermark
    }

    private let dialStyle: DialStyle
    /// Relative needle angle in radians (`0` = 12 o'clock straight up, negative = left, positive = right).
    var needleAngle: CGFloat = 0.0 {
        didSet { if abs(oldValue - needleAngle) > 0.001 { needsDisplay = true } }
    }
    var dialOpacity: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }

    private var sweepTimer: Timer?
    private var sweepStartTime: CFTimeInterval = 0

    init(style: DialStyle = .chronograph) {
        self.dialStyle = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        sweepTimer?.invalidate()
    }

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func startSweepAnimation() {
        sweepTimer?.invalidate()
        sweepTimer = nil
        guard !AppSettings.shared.effectiveReduceMotion else {
            needleAngle = 0.0
            return
        }
        sweepStartTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 45.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.window != nil, !self.isHiddenOrHasHiddenAncestor else { return }
                let t = CACurrentMediaTime() - self.sweepStartTime
                let maxSwing: CGFloat = (self.dialStyle == .chronograph) ? 0.36 : 0.28
                self.needleAngle = maxSwing * CGFloat(sin(t * 1.65) * 0.78 + sin(t * 0.68) * 0.22)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    func stopSweepAnimation() {
        sweepTimer?.invalidate()
        sweepTimer = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopSweepAnimation()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        guard w > 16, h > 12, let ctx = NSGraphicsContext.current?.cgContext else { return }

        let dark = isDarkAppearance
        let baseMult = dialOpacity * (dark ? 1.0 : 0.65)
        guard baseMult > 0.01 else { return }

        let isFull = (dialStyle == .chronograph)
        let outerRadius = max(w * (isFull ? 0.56 : 0.62), 68.0)
        let arcGap: CGFloat = isFull ? 21.0 : 14.0
        let innerRadius = outerRadius - arcGap
        let apexY = h * (isFull ? 0.68 : 0.74)
        let circleCenter = CGPoint(x: w * 0.5, y: apexY - outerRadius)

        let outerCount = isFull ? 61 : 47
        let outerSpread: CGFloat = isFull ? 0.78 : 0.68
        let outerTickLen: CGFloat = isFull ? 7.2 : 5.0

        ctx.saveGState()
        ctx.setLineCap(.round)

        // 1. Outer Radial Tick-Mark Arc
        for i in 0..<outerCount {
            let frac = CGFloat(i) / CGFloat(max(1, outerCount - 1)) // 0...1
            let relAngle = (frac * 2.0 - 1.0) * outerSpread
            let theta = (.pi * 0.5) - relAngle
            let cosT = cos(theta)
            let sinT = sin(theta)

            let edgeWindow = pow(max(0.0, cos((relAngle / outerSpread) * (.pi * 0.5))), 1.35)
            let distToNeedle = abs(relAngle - needleAngle)
            let needleProx = exp(-pow(distToNeedle / 0.13, 2.0))

            let tickAlpha = baseMult * edgeWindow * (0.28 + 0.68 * needleProx)
            guard tickAlpha > 0.015 else { continue }

            let extraLen = needleProx * (isFull ? 1.8 : 1.0)
            let rStart = outerRadius - outerTickLen - extraLen * 0.4
            let rEnd = outerRadius + extraLen * 0.6

            let p1 = CGPoint(x: circleCenter.x + rStart * cosT, y: circleCenter.y + rStart * sinT)
            let p2 = CGPoint(x: circleCenter.x + rEnd * cosT, y: circleCenter.y + rEnd * sinT)

            let color = NSColor(
                red: 0.74 + 0.24 * needleProx,
                green: 0.80 + 0.19 * needleProx,
                blue: 0.90 + 0.10 * needleProx,
                alpha: tickAlpha
            )
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth((isFull ? 1.30 : 1.05) + 0.45 * needleProx)
            ctx.move(to: p1)
            ctx.addLine(to: p2)
            ctx.strokePath()
        }

        // 2. Inner Concentric Micro-Tick Arc
        let innerCount = isFull ? 49 : 35
        let innerSpread: CGFloat = isFull ? 0.64 : 0.54
        let innerTickLen: CGFloat = isFull ? 3.2 : 2.4

        for i in 0..<innerCount {
            let frac = CGFloat(i) / CGFloat(max(1, innerCount - 1))
            let relAngle = (frac * 2.0 - 1.0) * innerSpread
            let theta = (.pi * 0.5) - relAngle
            let cosT = cos(theta)
            let sinT = sin(theta)

            let edgeWindow = pow(max(0.0, cos((relAngle / innerSpread) * (.pi * 0.5))), 1.45)
            let distToNeedle = abs(relAngle - needleAngle)
            let needleProx = exp(-pow(distToNeedle / 0.14, 2.0))

            let tickAlpha = baseMult * edgeWindow * (0.20 + 0.56 * needleProx)
            guard tickAlpha > 0.015 else { continue }

            let rStart = innerRadius - innerTickLen
            let rEnd = innerRadius
            let p1 = CGPoint(x: circleCenter.x + rStart * cosT, y: circleCenter.y + rStart * sinT)
            let p2 = CGPoint(x: circleCenter.x + rEnd * cosT, y: circleCenter.y + rEnd * sinT)

            let color = NSColor(
                red: 0.68 + 0.28 * needleProx,
                green: 0.78 + 0.20 * needleProx,
                blue: 0.92 + 0.08 * needleProx,
                alpha: tickAlpha
            )
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(isFull ? 1.05 : 0.85)
            ctx.move(to: p1)
            ctx.addLine(to: p2)
            ctx.strokePath()
        }

        // 3. Glowing Diamond-Tapered Radial Indicator Needle Beam
        let needleTheta = (.pi * 0.5) - needleAngle
        let ux = cos(needleTheta)
        let uy = sin(needleTheta)
        // Perpendicular tangent vector
        let px = -uy
        let py = ux

        let rTop = outerRadius + (isFull ? 13.5 : 8.5)
        let rShoulder = outerRadius - (isFull ? 1.5 : 1.0)
        let rBottom = innerRadius - (isFull ? 12.5 : 7.5)

        let topTip = CGPoint(x: circleCenter.x + rTop * ux, y: circleCenter.y + rTop * uy)
        let shoulderCenter = CGPoint(x: circleCenter.x + rShoulder * ux, y: circleCenter.y + rShoulder * uy)
        let bottomTip = CGPoint(x: circleCenter.x + rBottom * ux, y: circleCenter.y + rBottom * uy)

        let halfWTop: CGFloat = isFull ? 0.95 : 0.70
        let halfWShoulder: CGFloat = isFull ? 1.45 : 1.05

        let needlePath = CGMutablePath()
        needlePath.move(to: CGPoint(x: topTip.x - px * halfWTop, y: topTip.y - py * halfWTop))
        needlePath.addLine(to: CGPoint(x: topTip.x + px * halfWTop, y: topTip.y + py * halfWTop))
        needlePath.addLine(to: CGPoint(x: shoulderCenter.x + px * halfWShoulder, y: shoulderCenter.y + py * halfWShoulder))
        needlePath.addLine(to: bottomTip)
        needlePath.addLine(to: CGPoint(x: shoulderCenter.x - px * halfWShoulder, y: shoulderCenter.y - py * halfWShoulder))
        needlePath.closeSubpath()

        // Soft cyan-white outer halo behind needle
        ctx.saveGState()
        ctx.setShadow(
            offset: .zero,
            blur: isFull ? 8.0 : 5.0,
            color: NSColor(red: 0.45, green: 0.88, blue: 1.00, alpha: 0.85 * baseMult).cgColor
        )
        ctx.addPath(needlePath)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.35 * baseMult).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Gradient fill inside needle from pure white at top to translucent cyan at bottom tip
        ctx.saveGState()
        ctx.addPath(needlePath)
        ctx.clip()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let needleColors = [
            NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.98 * baseMult).cgColor,
            NSColor(red: 0.82, green: 0.95, blue: 1.00, alpha: 0.88 * baseMult).cgColor,
            NSColor(red: 0.32, green: 0.84, blue: 1.00, alpha: 0.32 * baseMult).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        if let needleGrad = CGGradient(colorsSpace: colorSpace, colors: needleColors, locations: [0.0, 0.38, 0.78, 1.0]) {
            ctx.drawLinearGradient(needleGrad, start: topTip, end: bottomTip, options: [])
        }
        ctx.restoreGState()

        ctx.restoreGState()
    }
}

/// Large Bold Kinetic Tilted Numerals (`"58"`) emerging from the bottom incandescent blue-white Horizon Light Pool.
@MainActor
final class HorizonKineticCounterView: NSView {
    var displayValue: Int = 12 {
        didSet {
            let clamped = max(1, min(99, displayValue))
            if clamped != displayValue {
                displayValue = clamped
            }
            if oldValue != displayValue {
                needsDisplay = true
            }
        }
    }

    var tiltRadians: CGFloat = -0.145 {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        guard w > 20, h > 20, let ctx = NSGraphicsContext.current?.cgContext else { return }

        let text = String(format: "%02d", displayValue)
        let fontSize = min(h * 0.96, w * 0.48)
        let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let roundedFont: NSFont
        if let desc = baseFont.fontDescriptor.withDesign(.rounded),
           let custom = NSFont(descriptor: desc, size: fontSize) {
            roundedFont = custom
        } else {
            roundedFont = baseFont
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: roundedFont,
            .kern: -fontSize * 0.035,
            .foregroundColor: NSColor.white
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let lineHeight = ascent + descent

        ctx.saveGState()
        // Center horizontally, position near bottom so lower edge dips into the horizon light pool
        let centerX = w * 0.5
        let centerY = h * 0.42
        ctx.translateBy(x: centerX, y: centerY)
        ctx.rotate(by: tiltRadians)
        ctx.translateBy(x: -centerX, y: -centerY)

        // Convert CTLine runs to CGPath so we can fill with a pure-white -> ice-cyan horizon gradient
        let glyphPath = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        let textOriginX = (w - lineWidth) * 0.5
        let textOriginY = (h - lineHeight) * 0.5 + descent - h * 0.08

        for run in runs {
            let runAttrs = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = runAttrs[kCTFontAttributeName as String] else { continue }
            let cfFont = runFont as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, count), &positions)

            for i in 0..<count {
                if let letter = CTFontCreatePathForGlyph(cfFont, glyphs[i], nil) {
                    let t = CGAffineTransform(translationX: textOriginX + positions[i].x, y: textOriginY + positions[i].y)
                    glyphPath.addPath(letter, transform: t)
                }
            }
        }

        // Soft outer cyan-blue horizon bloom behind the numerals
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -4),
            blur: 18.0,
            color: NSColor(red: 0.10, green: 0.68, blue: 1.00, alpha: 0.72).cgColor
        )
        ctx.addPath(glyphPath)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.28).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Vertical gradient fill: crisp pure white at top of numerals -> luminous translucent sky-cyan at bottom
        ctx.saveGState()
        ctx.addPath(glyphPath)
        ctx.clip()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let numColors = [
            NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.99).cgColor,
            NSColor(red: 0.90, green: 0.96, blue: 1.00, alpha: 0.94).cgColor,
            NSColor(red: 0.58, green: 0.84, blue: 1.00, alpha: 0.72).cgColor,
            NSColor(red: 0.22, green: 0.72, blue: 1.00, alpha: 0.28).cgColor
        ] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: numColors, locations: [0.0, 0.45, 0.78, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: centerX, y: textOriginY + ascent),
                end: CGPoint(x: centerX, y: textOriginY - descent * 0.5),
                options: []
            )
        }
        ctx.restoreGState()

        ctx.restoreGState()
    }
}

/// Native macOS Liquid Glass container surface (`NSGlassEffectView` on macOS 26+ with clean frosted fallback)
/// enhanced with `HorizonLightWellView` (top silver specular rim + bottom-up electric cyan-cobalt horizon light pool).
@MainActor
final class LiquidGlassSurfaceView: NSView {
    let contentContainer = NSView()
    let horizonWellView: HorizonLightWellView

    private let cornerRadius: CGFloat
    private let glassStyle: LiquidGlassStyle
    private var tint: NSColor?
    private var adaptiveDarkTint: NSColor?
    private var adaptiveLightTint: NSColor?
    private let interactive: Bool

    var horizonGlowIntensity: CGFloat {
        get { horizonWellView.intensity }
        set { horizonWellView.intensity = newValue }
    }

    var horizonRimStrength: CGFloat {
        get { horizonWellView.rimStrength }
        set { horizonWellView.rimStrength = newValue }
    }

    var horizonPoolHeightFraction: CGFloat {
        get { horizonWellView.poolHeightFraction }
        set { horizonWellView.poolHeightFraction = newValue }
    }

    var baseObsidianDarkness: CGFloat {
        get { horizonWellView.baseObsidianDarkness }
        set { horizonWellView.baseObsidianDarkness = newValue }
    }

    private var nativeGlassView: NSView?
    private var fallbackBlurView: NSVisualEffectView?
    private var fallbackTintLayer: CALayer?
    private var specularBorderLayer: CAShapeLayer?
    private let useNativeGlass: Bool

    var enableHoverGlow: Bool = false {
        didSet {
            guard oldValue != enableHoverGlow else { return }
            updateHoverTrackingArea()
        }
    }
    private var hoverTrackingArea: NSTrackingArea?
    private var isSurfaceHovered = false
    private let cardHoverHighlightLayer = CALayer()
    private let cardHoverSpotlightLayer = CAGradientLayer()

    init(
        cornerRadius: CGFloat,
        style: LiquidGlassStyle = .regular,
        tintColor: NSColor? = nil,
        lightTintColor: NSColor? = nil,
        interactive: Bool = false,
        useNativeGlass: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.glassStyle = style
        self.tint = tintColor
        self.adaptiveDarkTint = tintColor
        self.adaptiveLightTint = lightTintColor
        self.interactive = interactive
        self.useNativeGlass = useNativeGlass
        self.horizonWellView = HorizonLightWellView(
            cornerRadius: cornerRadius,
            intensity: 0.0
        )
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        setupSurface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSurface() {
        if useNativeGlass {
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                glass.cornerRadius = cornerRadius
                glass.style = (glassStyle == .regular) ? .regular : .clear
                glass.tintColor = tint
                if #available(macOS 27.0, *) {
                    glass.effectIsInteractive = interactive
                }
                glass.contentView = contentContainer
                glass.translatesAutoresizingMaskIntoConstraints = false
                addSubview(glass)
                NSLayoutConstraint.activate([
                    glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                    glass.trailingAnchor.constraint(equalTo: trailingAnchor),
                    glass.topAnchor.constraint(equalTo: topAnchor),
                    glass.bottomAnchor.constraint(equalTo: bottomAnchor)
                ])
                nativeGlassView = glass
            } else {
                let blur = NSVisualEffectView()
                blur.material = (glassStyle == .regular) ? .popover : .hudWindow
                blur.state = .active
                blur.wantsLayer = true
                blur.layer?.cornerRadius = cornerRadius
                blur.layer?.masksToBounds = true
                blur.translatesAutoresizingMaskIntoConstraints = false
                addSubview(blur)
                NSLayoutConstraint.activate([
                    blur.leadingAnchor.constraint(equalTo: leadingAnchor),
                    blur.trailingAnchor.constraint(equalTo: trailingAnchor),
                    blur.topAnchor.constraint(equalTo: topAnchor),
                    blur.bottomAnchor.constraint(equalTo: bottomAnchor)
                ])

                let tintLayer = CALayer()
                tintLayer.backgroundColor = (tint ?? .clear).cgColor
                tintLayer.cornerRadius = cornerRadius
                blur.layer?.addSublayer(tintLayer)
                fallbackTintLayer = tintLayer

                let rim = CAShapeLayer()
                rim.fillColor = nil
                rim.strokeColor = NSColor.white.withAlphaComponent(0.24).cgColor
                rim.lineWidth = 0.85
                blur.layer?.addSublayer(rim)
                specularBorderLayer = rim

                contentContainer.translatesAutoresizingMaskIntoConstraints = false
                blur.addSubview(contentContainer)
                NSLayoutConstraint.activate([
                    contentContainer.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                    contentContainer.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                    contentContainer.topAnchor.constraint(equalTo: blur.topAnchor),
                    contentContainer.bottomAnchor.constraint(equalTo: blur.bottomAnchor)
                ])
                fallbackBlurView = blur
            }
        } else {
            let tintLayer = CALayer()
            tintLayer.backgroundColor = (tint ?? .clear).cgColor
            tintLayer.cornerRadius = cornerRadius
            layer?.addSublayer(tintLayer)
            fallbackTintLayer = tintLayer

            contentContainer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(contentContainer)
            NSLayoutConstraint.activate([
                contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                contentContainer.topAnchor.constraint(equalTo: topAnchor),
                contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        horizonWellView.translatesAutoresizingMaskIntoConstraints = false
        horizonWellView.layer?.zPosition = -10
        contentContainer.addSubview(horizonWellView)
        NSLayoutConstraint.activate([
            horizonWellView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            horizonWellView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            horizonWellView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            horizonWellView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])

        contentContainer.wantsLayer = true
        cardHoverHighlightLayer.cornerRadius = cornerRadius
        cardHoverHighlightLayer.masksToBounds = true
        cardHoverHighlightLayer.borderWidth = 0.85
        cardHoverHighlightLayer.borderColor = NSColor(red: 0.34, green: 0.78, blue: 1.0, alpha: 0.28).cgColor
        cardHoverHighlightLayer.backgroundColor = NSColor(red: 0.14, green: 0.48, blue: 0.96, alpha: 0.06).cgColor
        cardHoverHighlightLayer.opacity = 0.0
        cardHoverHighlightLayer.zPosition = -5

        cardHoverSpotlightLayer.type = .radial
        cardHoverSpotlightLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        cardHoverSpotlightLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        cardHoverSpotlightLayer.bounds = CGRect(x: 0, y: 0, width: 220, height: 220)
        cardHoverSpotlightLayer.colors = [
            NSColor(red: 0.28, green: 0.76, blue: 1.0, alpha: 0.16).cgColor,
            NSColor(red: 0.08, green: 0.42, blue: 0.96, alpha: 0.06).cgColor,
            NSColor.clear.cgColor
        ]
        cardHoverSpotlightLayer.locations = [0.0, 0.55, 1.0]
        cardHoverHighlightLayer.addSublayer(cardHoverSpotlightLayer)
        contentContainer.layer?.addSublayer(cardHoverHighlightLayer)
    }

    private func updateHoverTrackingArea() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
            self.hoverTrackingArea = nil
        }
        guard enableHoverGlow else { return }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if enableHoverGlow {
            updateHoverTrackingArea()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard enableHoverGlow else { return }
        isSurfaceHovered = true
        let pt = contentContainer.convert(event.locationInWindow, from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardHoverSpotlightLayer.position = pt
        CATransaction.commit()
        updateSurfaceHoverAppearance(animated: true)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard enableHoverGlow, isSurfaceHovered else { return }
        let pt = contentContainer.convert(event.locationInWindow, from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardHoverSpotlightLayer.position = pt
        CATransaction.commit()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard enableHoverGlow else { return }
        isSurfaceHovered = false
        updateSurfaceHoverAppearance(animated: true)
    }

    private func updateSurfaceHoverAppearance(animated: Bool) {
        let targetOpacity: Float = isSurfaceHovered ? 1.0 : 0.0
        horizonRimStrength = isSurfaceHovered ? 0.22 : 0.08
        horizonGlowIntensity = isSurfaceHovered ? 0.12 : 0.0
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(AppleMotion.duration(0.20))
            CATransaction.setAnimationTimingFunction(AppleMotion.easeOut)
            cardHoverHighlightLayer.opacity = targetOpacity
            CATransaction.commit()
        } else {
            cardHoverHighlightLayer.opacity = targetOpacity
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAdaptiveTint()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAdaptiveTint()
    }

    func setAdaptiveTint(dark: NSColor?, light: NSColor? = nil) {
        self.tint = dark
        self.adaptiveDarkTint = dark
        self.adaptiveLightTint = light
        if dark == nil && light == nil {
            if #available(macOS 26.0, *), let glass = nativeGlassView as? NSGlassEffectView {
                glass.tintColor = nil
            }
            fallbackTintLayer?.backgroundColor = NSColor.clear.cgColor
        } else {
            applyAdaptiveTint()
        }
    }

    private func applyAdaptiveTint() {
        guard adaptiveDarkTint != nil || adaptiveLightTint != nil else { return }
        let resolved: NSColor? = isDarkAppearance
            ? adaptiveDarkTint
            : (adaptiveLightTint ?? NSColor(white: 0.97, alpha: 0.80))
        if #available(macOS 26.0, *), let glass = nativeGlassView as? NSGlassEffectView {
            glass.tintColor = resolved
        }
        fallbackTintLayer?.backgroundColor = (resolved ?? .clear).cgColor
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardHoverHighlightLayer.frame = bounds
        cardHoverHighlightLayer.cornerRadius = cornerRadius
        if let fallbackTintLayer {
            fallbackTintLayer.frame = bounds
            fallbackTintLayer.cornerRadius = cornerRadius
        }
        if let rim = specularBorderLayer {
            rim.frame = bounds
            rim.path = CGPath(
                roundedRect: bounds.insetBy(dx: 0.45, dy: 0.45),
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
        }
        CATransaction.commit()
    }
}

/// Groups nearby interactive Liquid Glass controls using `NSGlassEffectContainerView` so glass merges seamlessly.
@MainActor
final class LiquidGlassGroupView: NSView {
    let stackView = NSStackView()

    init(spacing: CGFloat = 6) {
        super.init(frame: .zero)
        wantsLayer = true

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = spacing
        stackView.translatesAutoresizingMaskIntoConstraints = false

        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView()
            container.spacing = spacing
            let host = NSView()
            container.contentView = host
            container.translatesAutoresizingMaskIntoConstraints = false
            addSubview(container)
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: leadingAnchor),
                container.trailingAnchor.constraint(equalTo: trailingAnchor),
                container.topAnchor.constraint(equalTo: topAnchor),
                container.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

            host.addSubview(stackView)
            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                stackView.topAnchor.constraint(equalTo: host.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ])
        } else {
            addSubview(stackView)
            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
                stackView.topAnchor.constraint(equalTo: topAnchor),
                stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Zero-clipping, centered Liquid Glass circular/pill control with smooth spring hover, press physics & instant hover tooltip.
@MainActor
final class LiquidGlassButton: NSView {
    private let surface: LiquidGlassSurfaceView
    private let hoverOverlayLayer = CALayer()
    private let hoverSpotlightLayer = CAGradientLayer()
    private let hoverSheenLayer = CAGradientLayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var floatingTooltipView: NSView?

    private var onAction: () -> Void
    private var defaultDarkTint: NSColor?
    private var defaultLightTint: NSColor?
    private let defaultForegroundColor: NSColor
    private var isSelectedAccent = false
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    var title: String {
        get { titleLabel.stringValue }
        set {
            titleLabel.stringValue = newValue
            titleLabel.isHidden = newValue.isEmpty
            setAccessibilityLabel(newValue.isEmpty ? (toolTip ?? "Button") : newValue)
        }
    }

    func updateSymbol(_ symbolName: String, pointSize: CGFloat = 11.5, weight: NSFont.Weight = .semibold) {
        if let baseImg = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip ?? title) {
            let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            iconView.image = baseImg.withSymbolConfiguration(cfg) ?? baseImg
        }
    }

    init(
        symbol: String? = nil,
        symbolPointSize: CGFloat = 11.5,
        symbolWeight: NSFont.Weight = .medium,
        title: String = "",
        tooltip: String? = nil,
        fixedSize: CGSize? = nil,
        height: CGFloat = 28,
        minWidth: CGFloat? = nil,
        style: LiquidGlassStyle = .regular,
        tintColor: NSColor? = nil,
        lightTintColor: NSColor? = nil,
        foregroundColor: NSColor = .labelColor,
        font: NSFont = .systemFont(ofSize: 11.5, weight: .semibold),
        onAction: @escaping () -> Void
    ) {
        let radius = (fixedSize?.height ?? height) / 2
        let isDefaultUntinted = (tintColor == nil && lightTintColor == nil)
        let resolvedStyle: LiquidGlassStyle = isDefaultUntinted ? .clear : style
        let resolvedDarkTint = tintColor ?? NSColor(red: 0.045, green: 0.062, blue: 0.115, alpha: 0.72)
        let resolvedLightTint = lightTintColor ?? tintColor ?? NSColor(white: 0.92, alpha: 0.58)
        self.defaultDarkTint = resolvedDarkTint
        self.defaultLightTint = resolvedLightTint
        self.defaultForegroundColor = foregroundColor
        self.surface = LiquidGlassSurfaceView(
            cornerRadius: radius,
            style: resolvedStyle,
            tintColor: resolvedDarkTint,
            lightTintColor: resolvedLightTint,
            interactive: true,
            useNativeGlass: false
        )
        self.onAction = onAction
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        self.toolTip = tooltip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title.isEmpty ? (tooltip ?? "Button") : title)

        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        hoverOverlayLayer.backgroundColor = NSColor(red: 0.28, green: 0.64, blue: 1.0, alpha: 0.16).cgColor
        hoverOverlayLayer.borderWidth = 1.0
        hoverOverlayLayer.borderColor = NSColor(red: 0.42, green: 0.84, blue: 1.0, alpha: 0.56).cgColor
        hoverOverlayLayer.cornerRadius = radius
        hoverOverlayLayer.masksToBounds = true
        hoverOverlayLayer.opacity = 0.0

        hoverSpotlightLayer.type = .radial
        hoverSpotlightLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        hoverSpotlightLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        hoverSpotlightLayer.bounds = CGRect(x: 0, y: 0, width: 92, height: 92)
        hoverSpotlightLayer.colors = [
            NSColor(red: 0.60, green: 0.90, blue: 1.0, alpha: 0.34).cgColor,
            NSColor(red: 0.16, green: 0.60, blue: 1.0, alpha: 0.15).cgColor,
            NSColor.clear.cgColor
        ]
        hoverSpotlightLayer.locations = [0.0, 0.52, 1.0]
        hoverOverlayLayer.addSublayer(hoverSpotlightLayer)

        hoverSheenLayer.colors = [
            NSColor.clear.cgColor,
            NSColor(red: 0.50, green: 0.88, blue: 1.0, alpha: 0.24).cgColor,
            NSColor(red: 0.92, green: 0.98, blue: 1.0, alpha: 0.30).cgColor,
            NSColor(red: 0.42, green: 0.82, blue: 1.0, alpha: 0.14).cgColor,
            NSColor.clear.cgColor
        ]
        hoverSheenLayer.locations = [0.0, 0.28, 0.50, 0.72, 1.0]
        hoverSheenLayer.startPoint = CGPoint(x: 0.0, y: 0.20)
        hoverSheenLayer.endPoint = CGPoint(x: 1.0, y: 0.80)
        hoverSheenLayer.opacity = 0.0
        hoverOverlayLayer.addSublayer(hoverSheenLayer)

        layer?.shadowColor = NSColor(red: 0.24, green: 0.74, blue: 1.0, alpha: 1.0).cgColor
        layer?.shadowRadius = 11
        layer?.shadowOffset = .zero
        layer?.shadowOpacity = 0.0
        surface.contentContainer.wantsLayer = true
        surface.contentContainer.layer?.cornerRadius = radius
        surface.contentContainer.layer?.masksToBounds = true
        surface.contentContainer.layer?.addSublayer(hoverOverlayLayer)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4.5
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let symbol,
           let baseImg = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip ?? title) {
            let cfg = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: symbolWeight)
            iconView.image = baseImg.withSymbolConfiguration(cfg) ?? baseImg
            iconView.imageScaling = .scaleNone
            iconView.contentTintColor = foregroundColor
            iconView.wantsLayer = true
            stack.addArrangedSubview(iconView)
        }

        titleLabel.stringValue = title
        titleLabel.font = font
        titleLabel.textColor = foregroundColor
        titleLabel.alignment = .center
        titleLabel.isHidden = title.isEmpty
        if !title.isEmpty {
            stack.addArrangedSubview(titleLabel)
        }

        surface.contentContainer.addSubview(stack)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        if let fixedSize {
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: fixedSize.width),
                heightAnchor.constraint(equalToConstant: fixedSize.height),
                stack.centerXAnchor.constraint(equalTo: surface.contentContainer.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: surface.contentContainer.centerYAnchor)
            ])
        } else {
            let hPad: CGFloat = symbol != nil && !title.isEmpty ? 9 : 11
            stack.setContentHuggingPriority(.required, for: .horizontal)
            let hugWidth = widthAnchor.constraint(equalTo: stack.widthAnchor, constant: hPad * 2)
            hugWidth.priority = .defaultHigh
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: height),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: surface.contentContainer.leadingAnchor, constant: hPad),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: surface.contentContainer.trailingAnchor, constant: -hPad),
                hugWidth,
                stack.centerXAnchor.constraint(equalTo: surface.contentContainer.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: surface.contentContainer.centerYAnchor)
            ])
            if let minWidth {
                widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
            }
        }
        updateInteractionAppearance(animated: false)
    }

    func setSelectedAccent(_ selected: Bool) {
        guard isSelectedAccent != selected else { return }
        isSelectedAccent = selected
        if selected {
            let darkCobalt = NSColor(red: 0.08, green: 0.36, blue: 0.82, alpha: 0.84)
            let lightCobalt = NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.90)
            surface.setAdaptiveTint(dark: darkCobalt, light: lightCobalt)
            iconView.contentTintColor = .white
            titleLabel.textColor = .white
        } else {
            surface.setAdaptiveTint(dark: defaultDarkTint, light: defaultLightTint)
            iconView.contentTintColor = defaultForegroundColor
            titleLabel.textColor = defaultForegroundColor
        }
        updateInteractionAppearance(animated: false)
    }

    func setTint(dark: NSColor?, light: NSColor? = nil, foregroundColor: NSColor? = nil) {
        isSelectedAccent = false
        defaultDarkTint = dark
        defaultLightTint = light ?? dark
        surface.setAdaptiveTint(dark: defaultDarkTint, light: defaultLightTint)
        if let foregroundColor {
            iconView.contentTintColor = foregroundColor
            titleLabel.textColor = foregroundColor
        }
        updateInteractionAppearance(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverOverlayLayer.frame = bounds
        let spotDiameter = max(84, bounds.width * 0.95)
        hoverSpotlightLayer.bounds = CGRect(x: 0, y: 0, width: spotDiameter, height: spotDiameter)
        hoverSheenLayer.frame = CGRect(x: 0, y: 0, width: max(46, bounds.width * 0.72), height: bounds.height)
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        let pt = convert(event.locationInWindow, from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverSpotlightLayer.position = pt
        CATransaction.commit()
        playHoverSheenSweep()
        updateInteractionAppearance(animated: true)
        setFloatingTooltipVisible(true)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isHovered else { return }
        let pt = convert(event.locationInWindow, from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverSpotlightLayer.position = pt
        CATransaction.commit()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateInteractionAppearance(animated: true)
        setFloatingTooltipVisible(false)
    }

    private func playHoverSheenSweep() {
        guard !AppSettings.shared.effectiveReduceMotion, bounds.width > 12 else { return }
        let sheenW = max(46, bounds.width * 0.72)
        hoverSheenLayer.removeAllAnimations()

        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = -sheenW
        slide.toValue = bounds.width + sheenW * 0.35
        slide.duration = AppleMotion.duration(0.46)
        slide.timingFunction = AppleMotion.easeOut

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 0.95, 0.70, 0.0]
        fade.keyTimes = [0.0, 0.25, 0.70, 1.0]
        fade.duration = AppleMotion.duration(0.46)
        fade.timingFunction = AppleMotion.easeOut

        let group = CAAnimationGroup()
        group.animations = [slide, fade]
        group.duration = AppleMotion.duration(0.46)
        group.isRemovedOnCompletion = true
        hoverSheenLayer.add(group, forKey: "hoverSheen")
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        setFloatingTooltipVisible(false)
        updateInteractionAppearance(animated: true)
    }

    private func setFloatingTooltipVisible(_ visible: Bool) {
        guard let tip = toolTip, !tip.isEmpty, titleLabel.isHidden else {
            floatingTooltipView?.removeFromSuperview()
            floatingTooltipView = nil
            return
        }
        if visible {
            guard floatingTooltipView == nil, let rootView = window?.contentView else { return }
            let badge = NSView()
            badge.wantsLayer = true
            let dark = isDarkAppearance
            badge.layer?.backgroundColor = (dark
                ? NSColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 0.95)
                : NSColor(white: 0.14, alpha: 0.92)).cgColor
            badge.layer?.cornerRadius = 7
            badge.layer?.cornerCurve = .continuous
            badge.layer?.borderWidth = 0.75
            badge.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            badge.layer?.shadowColor = NSColor.black.cgColor
            badge.layer?.shadowOpacity = 0.35
            badge.layer?.shadowRadius = 8
            badge.layer?.shadowOffset = CGSize(width: 0, height: -2)

            let lbl = NSTextField(labelWithString: tip)
            lbl.font = .systemFont(ofSize: 11, weight: .medium)
            lbl.textColor = .white
            lbl.sizeToFit()

            let padX: CGFloat = 8
            let padY: CGFloat = 4
            let size = NSSize(width: lbl.frame.width + padX * 2, height: lbl.frame.height + padY * 2)
            lbl.frame = NSRect(x: padX, y: padY, width: lbl.frame.width, height: lbl.frame.height)
            badge.addSubview(lbl)

            let buttonFrameInRoot = convert(bounds, to: rootView)
            let isFlippedRoot = rootView.isFlipped
            let badgeX = max(8, min(rootView.bounds.width - size.width - 8, buttonFrameInRoot.midX - size.width / 2))
            let badgeY: CGFloat
            if isFlippedRoot {
                badgeY = (buttonFrameInRoot.maxY + 6 + size.height < rootView.bounds.height - 8)
                    ? (buttonFrameInRoot.maxY + 6)
                    : (buttonFrameInRoot.minY - size.height - 6)
            } else {
                badgeY = (buttonFrameInRoot.minY - size.height - 6 > 8)
                    ? (buttonFrameInRoot.minY - size.height - 6)
                    : (buttonFrameInRoot.maxY + 6)
            }
            badge.frame = NSRect(origin: NSPoint(x: badgeX, y: badgeY), size: size)
            badge.alphaValue = 0
            rootView.addSubview(badge)
            floatingTooltipView = badge

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = AppleMotion.duration(0.14)
                ctx.timingFunction = AppleMotion.easeOut
                badge.animator().alphaValue = 1.0
            }
        } else if let badge = floatingTooltipView {
            floatingTooltipView = nil
            badge.removeFromSuperview()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            floatingTooltipView?.removeFromSuperview()
            floatingTooltipView = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != isPressed {
            isPressed = inside
            updateInteractionAppearance(animated: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let shouldFire = isPressed && inside
        isPressed = false
        updateInteractionAppearance(animated: true)
        if shouldFire {
            onAction()
        }
    }

    private func updateInteractionAppearance(animated: Bool) {
        let hoverScale: CGFloat = bounds.width > 95 ? 1.022 : 1.052
        let targetScale: CGFloat = isPressed ? 0.94 : (isHovered ? hoverScale : 1.0)
        let targetTilt: CGFloat = isPressed ? -0.012 : (isHovered ? 0.008 : 0.0)
        let targetOverlay: Float = isPressed ? 0.92 : (isHovered ? 0.78 : 0.0)
        let targetShadow: Float = isPressed ? 0.56 : (isHovered ? 0.42 : 0.0)
        let baseRim: CGFloat = isSelectedAccent ? 0.18 : 0.08
        let baseGlow: CGFloat = isSelectedAccent ? 0.20 : 0.0
        surface.horizonGlowIntensity = isPressed ? 0.68 : (isHovered ? 0.48 : baseGlow)
        surface.horizonRimStrength = isPressed ? 0.72 : (isHovered ? 0.48 : baseRim)

        guard let layer else { return }
        let xform = AppleMotion.centeredTransform(bounds: bounds, scale: targetScale, rotationZ: targetTilt)
        let iconTargetScale: CGFloat = isPressed ? 0.92 : (isHovered ? 1.10 : 1.0)

        if animated {
            let fromXform = layer.presentation()?.transform ?? layer.transform
            let anim = AppleMotion.spring(
                keyPath: "transform",
                from: fromXform,
                to: xform,
                dampingRatio: 0.74,
                response: 0.26
            )
            layer.transform = xform
            layer.add(anim, forKey: "glassBounce")

            if let iconLayer = iconView.layer, iconView.bounds.width > 1 {
                AppleMotion.springScale(
                    layer: iconLayer,
                    bounds: iconView.bounds,
                    scale: iconTargetScale,
                    dampingRatio: 0.72,
                    response: 0.26,
                    key: "iconHoverBounce"
                )
            }

            CATransaction.begin()
            CATransaction.setAnimationDuration(AppleMotion.duration(0.18))
            CATransaction.setAnimationTimingFunction(AppleMotion.easeOut)
            hoverOverlayLayer.opacity = targetOverlay
            layer.shadowOpacity = targetShadow
            CATransaction.commit()
        } else {
            layer.transform = xform
            hoverOverlayLayer.opacity = targetOverlay
            layer.shadowOpacity = targetShadow
        }
    }
}

/// Gemini-inspired sliding Liquid Glass segmented pill (`[ Chat | Task ]` style) with spring thumb glide.
@MainActor
final class LiquidGlassSegmentedControl: NSView {
    struct Option {
        let title: String
        let symbol: String?

        init(title: String, symbol: String? = nil) {
            self.title = title
            self.symbol = symbol
        }
    }

    private let options: [Option]
    private let pillHeight: CGFloat
    private let compact: Bool
    private let onSelect: (Int) -> Void

    private let trackSurface: LiquidGlassSurfaceView
    private let hoverThumbLayer = CALayer()
    private let thumbLayer = CALayer()
    private let thumbHorizonLayer = CAGradientLayer()
    private let thumbBorderLayer = CAShapeLayer()
    private var segmentViews: [(container: NSView, icon: NSImageView?, label: NSTextField)] = []
    private var trackingArea: NSTrackingArea?
    private var hoveredIndex: Int?

    private(set) var selectedIndex: Int {
        didSet {
            guard oldValue != selectedIndex else { return }
            updateThumbPosition(animated: true)
            updateSegmentColors(animated: true)
        }
    }

    init(
        options: [Option],
        selectedIndex: Int = 0,
        height: CGFloat = 28,
        compact: Bool = false,
        onSelect: @escaping (Int) -> Void
    ) {
        self.options = options
        self.selectedIndex = max(0, min(max(0, options.count - 1), selectedIndex))
        self.pillHeight = height
        self.compact = compact
        self.onSelect = onSelect
        self.trackSurface = LiquidGlassSurfaceView(
            cornerRadius: height / 2,
            style: .clear,
            tintColor: NSColor(red: 0.04, green: 0.055, blue: 0.11, alpha: 0.74),
            lightTintColor: NSColor(white: 0.88, alpha: 0.52),
            interactive: true,
            useNativeGlass: false
        )
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelectedIndex(_ index: Int, animated: Bool = true) {
        let clamped = max(0, min(max(0, options.count - 1), index))
        guard clamped != selectedIndex else { return }
        selectedIndex = clamped
        updateThumbPosition(animated: animated)
        updateSegmentColors(animated: animated)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: pillHeight)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    private func setupUI() {
        trackSurface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trackSurface)
        NSLayoutConstraint.activate([
            trackSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackSurface.topAnchor.constraint(equalTo: topAnchor),
            trackSurface.bottomAnchor.constraint(equalTo: bottomAnchor),
            trackSurface.heightAnchor.constraint(equalToConstant: pillHeight)
        ])

        let content = trackSurface.contentContainer
        content.wantsLayer = true

        hoverThumbLayer.cornerRadius = (pillHeight - 4) / 2
        hoverThumbLayer.borderWidth = 0.75
        hoverThumbLayer.opacity = 0.0
        content.layer?.addSublayer(hoverThumbLayer)

        thumbLayer.backgroundColor = NSColor(red: 0.08, green: 0.32, blue: 0.74, alpha: 0.78).cgColor
        thumbLayer.shadowColor = NSColor(red: 0.16, green: 0.72, blue: 1.0, alpha: 0.72).cgColor
        thumbLayer.shadowRadius = 7
        thumbLayer.shadowOpacity = 0.42
        thumbLayer.shadowOffset = CGSize(width: 0, height: -1)
        thumbLayer.cornerRadius = (pillHeight - 4) / 2

        thumbHorizonLayer.colors = [
            NSColor(red: 0.58, green: 0.86, blue: 1.0, alpha: 0.24).cgColor,
            NSColor(red: 0.14, green: 0.68, blue: 1.0, alpha: 0.22).cgColor,
            NSColor(red: 0.06, green: 0.30, blue: 0.82, alpha: 0.08).cgColor,
            NSColor.clear.cgColor
        ]
        thumbHorizonLayer.locations = [0.0, 0.26, 0.65, 1.0]
        thumbHorizonLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        thumbHorizonLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        thumbHorizonLayer.cornerRadius = (pillHeight - 4) / 2
        thumbLayer.addSublayer(thumbHorizonLayer)

        thumbBorderLayer.fillColor = nil
        thumbBorderLayer.strokeColor = NSColor.white.withAlphaComponent(0.16).cgColor
        thumbBorderLayer.lineWidth = 0.75
        thumbLayer.addSublayer(thumbBorderLayer)
        content.layer?.addSublayer(thumbLayer)

        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 2
        row.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 2),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -2),
            row.topAnchor.constraint(equalTo: content.topAnchor, constant: 2),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -2)
        ])

        for opt in options {
            let cell = NSView()
            cell.wantsLayer = true
            cell.translatesAutoresizingMaskIntoConstraints = false

            let inner = NSStackView()
            inner.orientation = .horizontal
            inner.alignment = .centerY
            inner.spacing = compact ? 4 : 5
            inner.translatesAutoresizingMaskIntoConstraints = false

            var iconView: NSImageView?
            if let sym = opt.symbol, let img = NSImage(systemSymbolName: sym, accessibilityDescription: opt.title) {
                let iv = NSImageView(image: img)
                iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: compact ? 10 : 11, weight: .semibold)
                inner.addArrangedSubview(iv)
                iconView = iv
            }

            let label = NSTextField(labelWithString: opt.title)
            label.font = .systemFont(ofSize: compact ? 11.5 : 12, weight: .medium)
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.setContentHuggingPriority(.required, for: .horizontal)
            inner.addArrangedSubview(label)

            cell.addSubview(inner)
            cell.setContentCompressionResistancePriority(.required, for: .horizontal)
            let hPad: CGFloat = compact ? 10 : 13
            NSLayoutConstraint.activate([
                inner.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                inner.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                inner.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: hPad),
                inner.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -hPad),
                cell.heightAnchor.constraint(equalToConstant: pillHeight - 4)
            ])

            row.addArrangedSubview(cell)
            segmentViews.append((cell, iconView, label))
        }

        updateSegmentColors(animated: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updateThumbPosition(animated: false)
        }
    }

    override func layout() {
        super.layout()
        trackSurface.layoutSubtreeIfNeeded()
        updateThumbPosition(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private func segmentIndex(at pt: NSPoint) -> Int? {
        for i in segmentViews.indices {
            if thumbFrame(for: i).contains(pt) {
                return i
            }
        }
        guard !options.isEmpty else { return nil }
        return min(options.count - 1, max(0, Int((pt.x / max(1, bounds.width)) * CGFloat(options.count))))
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard bounds.contains(pt), let idx = segmentIndex(at: pt) else { return }
        if idx != selectedIndex {
            selectedIndex = idx
            onSelect(idx)
        } else {
            // Subtle tactile tap feedback even on current segment
            let f = thumbFrame(for: idx)
            AppleMotion.springScale(layer: thumbLayer, bounds: CGRect(origin: .zero, size: f.size), scale: 0.96, dampingRatio: 0.72, response: 0.24, key: "thumbTap")
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard bounds.contains(pt), let idx = segmentIndex(at: pt) else {
            hoveredIndex = nil
            updateSegmentColors(animated: true)
            return
        }
        if hoveredIndex != idx {
            hoveredIndex = idx
            updateSegmentColors(animated: true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        updateSegmentColors(animated: true)
    }

    private func thumbFrame(for index: Int) -> CGRect {
        if segmentViews.indices.contains(index) {
            let cell = segmentViews[index].container
            if cell.bounds.width > 1 {
                let converted = convert(cell.bounds, from: cell)
                return CGRect(x: converted.origin.x, y: 2, width: converted.width, height: max(0, pillHeight - 4))
            }
        }
        let count = max(1, CGFloat(options.count))
        let contentW = max(0, bounds.width - 4)
        let segW = contentW / count
        return CGRect(x: 2 + segW * CGFloat(index), y: 2, width: segW, height: max(0, pillHeight - 4))
    }

    private func updateThumbPosition(animated: Bool) {
        let target = thumbFrame(for: selectedIndex)
        guard target.width > 1, target.height > 1 else { return }
        let r = target.height / 2
        thumbLayer.cornerRadius = r
        let thumbPath = CGPath(roundedRect: CGRect(origin: .zero, size: target.size), cornerWidth: r, cornerHeight: r, transform: nil)
        thumbLayer.shadowPath = thumbPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumbHorizonLayer.frame = CGRect(origin: .zero, size: target.size)
        thumbHorizonLayer.cornerRadius = r
        let flipped = thumbHorizonLayer.contentsAreFlipped()
        thumbHorizonLayer.startPoint = CGPoint(x: 0.5, y: flipped ? 1.0 : 0.0)
        thumbHorizonLayer.endPoint = CGPoint(x: 0.5, y: flipped ? 0.0 : 1.0)
        thumbBorderLayer.frame = CGRect(origin: .zero, size: target.size)
        thumbBorderLayer.path = CGPath(roundedRect: CGRect(origin: .zero, size: target.size).insetBy(dx: 0.5, dy: 0.5), cornerWidth: r, cornerHeight: r, transform: nil)
        CATransaction.commit()

        if animated {
            let fromRect = thumbLayer.presentation()?.frame ?? thumbLayer.frame
            let springPos = AppleMotion.spring(
                keyPath: "position",
                from: CGPoint(x: fromRect.midX, y: fromRect.midY),
                to: CGPoint(x: target.midX, y: target.midY),
                dampingRatio: 0.80,
                response: 0.34
            )
            let animBounds = CABasicAnimation(keyPath: "bounds")
            animBounds.fromValue = CGRect(origin: .zero, size: fromRect.size)
            animBounds.toValue = CGRect(origin: .zero, size: target.size)
            animBounds.duration = AppleMotion.duration(0.28)
            animBounds.timingFunction = AppleMotion.easeInOut

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            thumbLayer.frame = target
            CATransaction.commit()
            thumbLayer.add(springPos, forKey: "thumbSlide")
            thumbLayer.add(animBounds, forKey: "thumbSize")
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            thumbLayer.frame = target
            CATransaction.commit()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSegmentColors(animated: false)
    }

    private func updateHoverPill(animated: Bool) {
        guard let hoveredIndex, hoveredIndex != selectedIndex else {
            if animated {
                CATransaction.begin()
                CATransaction.setAnimationDuration(AppleMotion.duration(0.16))
                CATransaction.setAnimationTimingFunction(AppleMotion.easeOut)
                hoverThumbLayer.opacity = 0.0
                CATransaction.commit()
            } else {
                hoverThumbLayer.opacity = 0.0
            }
            return
        }
        let target = thumbFrame(for: hoveredIndex).insetBy(dx: 1, dy: 1)
        guard target.width > 1, target.height > 1 else { return }
        hoverThumbLayer.cornerRadius = target.height / 2

        if animated && hoverThumbLayer.opacity > 0.05 {
            let fromRect = hoverThumbLayer.presentation()?.frame ?? hoverThumbLayer.frame
            let springPos = AppleMotion.spring(
                keyPath: "position",
                from: CGPoint(x: fromRect.midX, y: fromRect.midY),
                to: CGPoint(x: target.midX, y: target.midY),
                dampingRatio: 0.84,
                response: 0.24
            )
            let animBounds = CABasicAnimation(keyPath: "bounds")
            animBounds.fromValue = CGRect(origin: .zero, size: fromRect.size)
            animBounds.toValue = CGRect(origin: .zero, size: target.size)
            animBounds.duration = AppleMotion.duration(0.20)
            animBounds.timingFunction = AppleMotion.easeOut

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hoverThumbLayer.frame = target
            CATransaction.commit()
            hoverThumbLayer.add(springPos, forKey: "hoverThumbSlide")
            hoverThumbLayer.add(animBounds, forKey: "hoverThumbSize")

            CATransaction.begin()
            CATransaction.setAnimationDuration(AppleMotion.duration(0.14))
            hoverThumbLayer.opacity = 1.0
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hoverThumbLayer.frame = target
            CATransaction.commit()
            if animated {
                CATransaction.begin()
                CATransaction.setAnimationDuration(AppleMotion.duration(0.16))
                CATransaction.setAnimationTimingFunction(AppleMotion.easeOut)
                hoverThumbLayer.opacity = 1.0
                CATransaction.commit()
            } else {
                hoverThumbLayer.opacity = 1.0
            }
        }
    }

    private func updateSegmentColors(animated: Bool) {
        let dark = isDarkAppearance
        trackSurface.horizonRimStrength = dark ? 0.08 : 0.10
        hoverThumbLayer.backgroundColor = (dark
            ? NSColor(red: 0.22, green: 0.58, blue: 1.0, alpha: 0.15)
            : NSColor(red: 0.14, green: 0.46, blue: 0.98, alpha: 0.10)).cgColor
        hoverThumbLayer.borderColor = NSColor(red: 0.45, green: 0.82, blue: 1.0, alpha: dark ? 0.26 : 0.22).cgColor
        thumbLayer.backgroundColor = (dark
            ? NSColor(red: 0.08, green: 0.32, blue: 0.74, alpha: 0.80)
            : NSColor(red: 0.18, green: 0.46, blue: 0.96, alpha: 0.88)).cgColor
        thumbBorderLayer.strokeColor = NSColor.white.withAlphaComponent(dark ? 0.15 : 0.32).cgColor
        updateHoverPill(animated: animated)

        let apply = {
            for (i, item) in self.segmentViews.enumerated() {
                let isSelected = (i == self.selectedIndex)
                let isHovered = (i == self.hoveredIndex)
                let unselectedColor = dark
                    ? NSColor.white.withAlphaComponent(isHovered ? 0.94 : 0.74)
                    : NSColor.black.withAlphaComponent(isHovered ? 0.90 : 0.68)
                let color: NSColor = isSelected ? .white : unselectedColor
                item.label.textColor = color
                item.label.font = .systemFont(ofSize: self.compact ? 11.5 : 12, weight: isSelected ? .semibold : .medium)
                item.icon?.contentTintColor = isSelected
                    ? (dark ? NSColor(red: 0.68, green: 0.88, blue: 1.0, alpha: 1.0) : .white)
                    : color
                if let cellLayer = item.container.layer, item.container.bounds.width > 1 {
                    let s: CGFloat = (isHovered && !isSelected) ? 1.04 : 1.0
                    let xform = AppleMotion.centeredTransform(bounds: item.container.bounds, scale: s)
                    if animated {
                        AppleMotion.springScale(layer: cellLayer, bounds: item.container.bounds, scale: s, dampingRatio: 0.78, response: 0.22, key: "segHoverScale")
                    } else {
                        cellLayer.transform = xform
                    }
                }
            }
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = AppleMotion.duration(0.18)
                ctx.timingFunction = AppleMotion.easeInOut
                apply()
            }
        } else {
            apply()
        }
    }
}

/// Smooth Liquid Glass pill switch with spring knob glide & VoiceOver support.
@MainActor
final class LiquidGlassToggle: NSView {
    private var suppressNextAnimation = false

    var isOn: Bool {
        didSet {
            guard oldValue != isOn else { return }
            setAccessibilityValue(isOn ? "On" : "Off")
            updateState(animated: !suppressNextAnimation)
        }
    }

    func setOn(_ value: Bool, animated: Bool) {
        guard isOn != value else { return }
        suppressNextAnimation = !animated
        isOn = value
        suppressNextAnimation = false
    }

    private let onToggle: (Bool) -> Void
    private let trackLayer = CALayer()
    private let knobLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(isOn: Bool, accessibilityLabel: String = "Toggle", onToggle: @escaping (Bool) -> Void) {
        self.isOn = isOn
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: 42, height: 24))

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 42).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true

        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityValue(isOn ? "On" : "Off")

        trackLayer.cornerRadius = 12
        trackLayer.borderWidth = 0.9
        trackLayer.shadowColor = NSColor(red: 0.28, green: 0.78, blue: 1.0, alpha: 1.0).cgColor
        trackLayer.shadowRadius = 7
        trackLayer.shadowOffset = .zero
        trackLayer.shadowOpacity = 0
        layer?.addSublayer(trackLayer)

        knobLayer.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        knobLayer.cornerRadius = 9
        knobLayer.backgroundColor = NSColor.white.cgColor
        knobLayer.shadowColor = NSColor.black.cgColor
        knobLayer.shadowOpacity = 0.28
        knobLayer.shadowRadius = 4
        knobLayer.shadowOffset = CGSize(width: 0, height: -1)
        layer?.addSublayer(knobLayer)

        updateState(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.contentsScale = scale
        trackLayer.contentsScale = scale
        knobLayer.contentsScale = scale
    }

    override func layout() {
        super.layout()
        trackLayer.frame = bounds
        trackLayer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 12, cornerHeight: 12, transform: nil)
        updateState(animated: false)
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
        updateHoverAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateHoverAppearance(animated: true)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        onToggle(isOn)
    }

    private func targetTrackColors() -> (bg: CGColor, border: CGColor, shadowAlpha: Float) {
        let dark = isDarkAppearance
        if isOn {
            let bg = NSColor(
                red: isHovered ? 0.14 : 0.10,
                green: isHovered ? 0.60 : 0.54,
                blue: 1.0,
                alpha: isHovered ? 0.96 : 0.92
            ).cgColor
            let border = NSColor(
                red: 0.52,
                green: 0.84,
                blue: 1.0,
                alpha: isHovered ? 0.78 : 0.44
            ).cgColor
            return (bg, border, isHovered ? 0.44 : 0.0)
        } else {
            let bg = (dark
                ? NSColor.white.withAlphaComponent(isHovered ? 0.14 : 0.08)
                : NSColor.black.withAlphaComponent(isHovered ? 0.16 : 0.12)
            ).cgColor
            let border = (isHovered
                ? NSColor(red: 0.36, green: 0.78, blue: 1.0, alpha: dark ? 0.42 : 0.48)
                : (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.14))
            ).cgColor
            return (bg, border, isHovered ? 0.22 : 0.0)
        }
    }

    private func updateHoverAppearance(animated: Bool) {
        let colors = targetTrackColors()
        let reduceMotion = AppSettings.shared.effectiveReduceMotion
        let knobScale: CGFloat = (isHovered && !reduceMotion) ? 1.12 : 1.0
        let targetScale = CATransform3DMakeScale(knobScale, knobScale, 1.0)

        if animated && !reduceMotion {
            let fromScale = knobLayer.presentation()?.transform ?? knobLayer.transform
            let spring = AppleMotion.spring(
                keyPath: "transform",
                from: fromScale,
                to: targetScale,
                dampingRatio: 0.64,
                response: 0.24
            )
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            knobLayer.transform = targetScale
            CATransaction.commit()
            knobLayer.add(spring, forKey: "knobHoverScale")
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            knobLayer.transform = targetScale
            CATransaction.commit()
        }

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(AppleMotion.duration(0.18))
            CATransaction.setAnimationTimingFunction(AppleMotion.easeOut)
            trackLayer.backgroundColor = colors.bg
            trackLayer.borderColor = colors.border
            trackLayer.shadowOpacity = colors.shadowAlpha
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            trackLayer.backgroundColor = colors.bg
            trackLayer.borderColor = colors.border
            trackLayer.shadowOpacity = colors.shadowAlpha
            CATransaction.commit()
        }
    }

    private func updateState(animated: Bool) {
        let knobX: CGFloat = isOn ? (bounds.width - 21) : 3
        let targetPos = CGPoint(x: knobX + 9, y: max(12, bounds.midY))
        let colors = targetTrackColors()

        if animated {
            let fromPos = knobLayer.presentation()?.position ?? knobLayer.position
            let spring = AppleMotion.spring(keyPath: "position", from: fromPos, to: targetPos, dampingRatio: 0.76, response: 0.30)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            knobLayer.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
            knobLayer.position = targetPos
            CATransaction.commit()
            knobLayer.add(spring, forKey: "knobSlide")

            CATransaction.begin()
            CATransaction.setAnimationDuration(AppleMotion.duration(0.22))
            CATransaction.setAnimationTimingFunction(AppleMotion.easeInOut)
            trackLayer.backgroundColor = colors.bg
            trackLayer.borderColor = colors.border
            trackLayer.shadowOpacity = colors.shadowAlpha
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            knobLayer.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
            knobLayer.position = targetPos
            trackLayer.backgroundColor = colors.bg
            trackLayer.borderColor = colors.border
            trackLayer.shadowOpacity = colors.shadowAlpha
            CATransaction.commit()
        }
    }
}

/// Signature LoopSearch Horizon Squircle Logo:
/// Deep pitch-obsidian squircle with a metallic silver-charcoal top dome, bottom-up incandescent white-cyan -> electric azure -> indigo-violet Horizon Light Pool, and a luminous ice-cyan inner loop mark.
final class LoopBrandLogoView: NSView {
    private let logoSize: CGFloat

    convenience init(size: CGFloat) {
        self.init(frame: NSRect(x: 0, y: 0, width: size, height: size), logoSize: size)
    }

    private init(frame: NSRect, logoSize: CGFloat) {
        self.logoSize = logoSize
        super.init(frame: frame)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: logoSize, height: logoSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = min(bounds.width, bounds.height)
        guard s > 4 else { return }
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let inset = max(0.6, s * 0.04)
        let box = CGRect(
            x: (bounds.width - s) * 0.5 + inset,
            y: (bounds.height - s) * 0.5 + inset,
            width: s - inset * 2.0,
            height: s - inset * 2.0
        )
        let r = box.width * 0.27
        let squirclePath = CGPath(roundedRect: box, cornerWidth: r, cornerHeight: r, transform: nil)

        // 1. Squircle Interior: Deep Obsidian + Top Metallic Silver Dome + Bottom Incandescent Blue Horizon Pool
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()

        ctx.setFillColor(NSColor(red: 0.012, green: 0.016, blue: 0.032, alpha: 1.0).cgColor)
        ctx.fill(box)

        // Top metallic charcoal-silver dome gradient
        let domeColors = [
            NSColor(red: 0.56, green: 0.59, blue: 0.65, alpha: 0.68).cgColor,
            NSColor(red: 0.26, green: 0.28, blue: 0.34, alpha: 0.32).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        if let domeGrad = CGGradient(colorsSpace: colorSpace, colors: domeColors, locations: [0.0, 0.42, 1.0]) {
            ctx.drawLinearGradient(
                domeGrad,
                start: CGPoint(x: box.midX, y: box.maxY),
                end: CGPoint(x: box.midX, y: box.minY + box.height * 0.52),
                options: []
            )
        }

        // Bottom-up Horizon Light Pool (White-Cyan -> Electric Blue -> Indigo-Violet -> Obsidian)
        let horizonColors = [
            NSColor(red: 0.94, green: 0.99, blue: 1.00, alpha: 0.98).cgColor,
            NSColor(red: 0.14, green: 0.78, blue: 1.00, alpha: 0.92).cgColor,
            NSColor(red: 0.02, green: 0.50, blue: 0.98, alpha: 0.76).cgColor,
            NSColor(red: 0.16, green: 0.22, blue: 0.58, alpha: 0.48).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        if let horizonGrad = CGGradient(colorsSpace: colorSpace, colors: horizonColors, locations: [0.0, 0.16, 0.36, 0.62, 1.0]) {
            ctx.drawLinearGradient(
                horizonGrad,
                start: CGPoint(x: box.midX, y: box.minY),
                end: CGPoint(x: box.midX, y: box.minY + box.height * 0.58),
                options: []
            )
        }

        // Elliptical bottom horizon core glow
        let coreColors = [
            NSColor(red: 0.98, green: 1.00, blue: 1.00, alpha: 0.95).cgColor,
            NSColor(red: 0.18, green: 0.82, blue: 1.00, alpha: 0.74).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        if let coreGrad = CGGradient(colorsSpace: colorSpace, colors: coreColors, locations: [0.0, 0.45, 1.0]) {
            ctx.saveGState()
            let coreCenter = CGPoint(x: box.midX, y: box.minY)
            let rx = box.width * 0.65
            let ry = box.height * 0.42
            ctx.translateBy(x: coreCenter.x, y: coreCenter.y)
            ctx.scaleBy(x: 1.0, y: ry / max(1.0, rx))
            ctx.drawRadialGradient(coreGrad, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: rx, options: [])
            ctx.restoreGState()
        }

        // Inner luminous ice-cyan Horizon Loop emblem
        let cx = box.midX
        let cy = box.midY + box.height * 0.03
        let ls = box.width * 0.64
        let loop = CGMutablePath()
        loop.move(to: CGPoint(x: cx - ls * 0.22, y: cy - ls * 0.30))
        loop.addCurve(
            to: CGPoint(x: cx - ls * 0.34, y: cy + ls * 0.10),
            control1: CGPoint(x: cx - ls * 0.36, y: cy - ls * 0.16),
            control2: CGPoint(x: cx - ls * 0.38, y: cy - ls * 0.02)
        )
        loop.addCurve(
            to: CGPoint(x: cx + ls * 0.10, y: cy + ls * 0.33),
            control1: CGPoint(x: cx - ls * 0.27, y: cy + ls * 0.29),
            control2: CGPoint(x: cx - ls * 0.08, y: cy + ls * 0.37)
        )
        loop.addCurve(
            to: CGPoint(x: cx + ls * 0.34, y: cy - ls * 0.08),
            control1: CGPoint(x: cx + ls * 0.30, y: cy + ls * 0.28),
            control2: CGPoint(x: cx + ls * 0.39, y: cy + ls * 0.11)
        )
        loop.addCurve(
            to: CGPoint(x: cx - ls * 0.05, y: cy - ls * 0.26),
            control1: CGPoint(x: cx + ls * 0.28, y: cy - ls * 0.24),
            control2: CGPoint(x: cx + ls * 0.11, y: cy - ls * 0.30)
        )
        let tip = CGPoint(x: cx + ls * 0.22, y: cy + ls * 0.18)
        loop.addCurve(
            to: tip,
            control1: CGPoint(x: cx - ls * 0.18, y: cy - ls * 0.22),
            control2: CGPoint(x: cx + ls * 0.06, y: cy + ls * 0.03)
        )

        ctx.saveGState()
        ctx.addPath(loop)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(max(1.3, s * 0.082))
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        let loopColors = [
            NSColor(red: 0.96, green: 0.99, blue: 1.00, alpha: 0.98).cgColor,
            NSColor(red: 0.36, green: 0.86, blue: 1.00, alpha: 0.95).cgColor,
            NSColor(red: 0.78, green: 0.86, blue: 0.96, alpha: 0.88).cgColor
        ] as CFArray
        if let loopGrad = CGGradient(colorsSpace: colorSpace, colors: loopColors, locations: [0.0, 0.55, 1.0]) {
            ctx.drawLinearGradient(
                loopGrad,
                start: CGPoint(x: cx, y: cy - ls * 0.36),
                end: CGPoint(x: cx, y: cy + ls * 0.36),
                options: []
            )
        }
        ctx.restoreGState()

        // Ice-white horizon spark at loop tip
        ctx.setFillColor(NSColor(red: 0.35, green: 0.88, blue: 1.00, alpha: 0.55).cgColor)
        ctx.fillEllipse(in: CGRect(x: tip.x - ls * 0.13, y: tip.y - ls * 0.13, width: ls * 0.26, height: ls * 0.26))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: tip.x - ls * 0.075, y: tip.y - ls * 0.075, width: ls * 0.15, height: ls * 0.15))

        ctx.restoreGState()

        // 2. Squircle Specular Rim (Silver-White Top -> Smoked Sides -> Incandescent White-Cyan Bottom Lip)
        let rimWidth = max(0.85, s * 0.042)
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.setLineWidth(rimWidth)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        let rimColors = [
            NSColor(red: 0.88, green: 0.91, blue: 0.96, alpha: 0.78).cgColor,
            NSColor(red: 0.26, green: 0.38, blue: 0.68, alpha: 0.28).cgColor,
            NSColor(red: 0.16, green: 0.78, blue: 1.00, alpha: 0.88).cgColor,
            NSColor(red: 0.95, green: 0.995, blue: 1.00, alpha: 1.00).cgColor
        ] as CFArray
        if let rimGrad = CGGradient(colorsSpace: colorSpace, colors: rimColors, locations: [0.0, 0.48, 0.82, 1.0]) {
            ctx.drawLinearGradient(
                rimGrad,
                start: CGPoint(x: box.midX, y: box.maxY),
                end: CGPoint(x: box.midX, y: box.minY),
                options: []
            )
        }
        ctx.restoreGState()
    }
}

typealias GeminiSparkIconView = LoopBrandLogoView

/// Minimalist, GPU-accelerated blue optical search centerpiece with breathing aura,
/// harmonic 3-wave sonar ripples, velvet conic scanner ring, and crisp obsidian glass core.
@MainActor
final class BlueSearchOpticalOrbView: NSView {
    private let orbSize: CGFloat = 96
    private let auraLayer = CAGradientLayer()
    private let outerHaloRingLayer = CAShapeLayer()
    private var rippleLayers: [CAShapeLayer] = []
    private let outerGlowConicLayer = CAGradientLayer()
    private let outerGlowMask = CAShapeLayer()
    private let outerConicLayer = CAGradientLayer()
    private let outerRingMask = CAShapeLayer()
    private let innerConicLayer = CAGradientLayer()
    private let innerRingMask = CAShapeLayer()
    private let coreContainer = CALayer()
    private let coreHorizonHighlight = CAGradientLayer()
    private let coreSheenLayer = CAGradientLayer()
    private let magnifierView = NSImageView()
    private var animationsStarted = false

    override init(frame frameRect: NSRect = CGRect(x: 0, y: 0, width: 96, height: 96)) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: orbSize).isActive = true
        heightAnchor.constraint(equalToConstant: orbSize).isActive = true
        setupLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncContentsScale()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncContentsScale()
    }

    private func syncContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        guard let root = layer else { return }
        func apply(_ target: CALayer) {
            target.contentsScale = scale
            target.mask?.contentsScale = scale
            target.sublayers?.forEach { apply($0) }
        }
        apply(root)
    }

    private func setupLayers() {
        guard let root = layer else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        root.contentsScale = scale

        let center = CGPoint(x: orbSize * 0.5, y: orbSize * 0.5)

        // 1. Deep sapphire atmospheric radial aura
        auraLayer.type = .radial
        auraLayer.bounds = CGRect(x: 0, y: 0, width: orbSize * 1.65, height: orbSize * 1.65)
        auraLayer.position = center
        auraLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        auraLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        auraLayer.colors = [
            NSColor(red: 0.14, green: 0.66, blue: 1.00, alpha: 0.42).cgColor,
            NSColor(red: 0.05, green: 0.36, blue: 0.94, alpha: 0.16).cgColor,
            NSColor.clear.cgColor
        ]
        auraLayer.locations = [0.0, 0.52, 1.0]
        auraLayer.contentsScale = scale
        root.addSublayer(auraLayer)

        // 2. Delicate outer concentric halo ring (76pt — matches optical double-ring silhouette)
        let haloD: CGFloat = 76
        let outerHaloGlowLayer = CAShapeLayer()
        outerHaloGlowLayer.bounds = CGRect(x: 0, y: 0, width: haloD, height: haloD)
        outerHaloGlowLayer.position = center
        outerHaloGlowLayer.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: haloD, height: haloD), transform: nil)
        outerHaloGlowLayer.fillColor = nil
        outerHaloGlowLayer.strokeColor = NSColor(red: 0.20, green: 0.72, blue: 1.00, alpha: 0.14).cgColor
        outerHaloGlowLayer.lineWidth = 4.5
        outerHaloGlowLayer.allowsEdgeAntialiasing = true
        outerHaloGlowLayer.contentsScale = scale
        root.addSublayer(outerHaloGlowLayer)

        outerHaloRingLayer.bounds = CGRect(x: 0, y: 0, width: haloD, height: haloD)
        outerHaloRingLayer.position = center
        outerHaloRingLayer.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: haloD, height: haloD), transform: nil)
        outerHaloRingLayer.fillColor = nil
        outerHaloRingLayer.strokeColor = NSColor(red: 0.24, green: 0.74, blue: 1.00, alpha: 0.30).cgColor
        outerHaloRingLayer.lineWidth = 1.05
        outerHaloRingLayer.opacity = 0.76
        outerHaloRingLayer.allowsEdgeAntialiasing = true
        outerHaloRingLayer.contentsScale = scale
        root.addSublayer(outerHaloRingLayer)

        // 3. Softly expanding harmonic sonar pulse rings
        let baseCircle = CGPath(ellipseIn: CGRect(x: -28, y: -28, width: 56, height: 56), transform: nil)
        for _ in 0..<2 {
            let ring = CAShapeLayer()
            ring.path = baseCircle
            ring.position = center
            ring.fillColor = nil
            ring.strokeColor = NSColor(red: 0.34, green: 0.84, blue: 1.00, alpha: 0.42).cgColor
            ring.lineWidth = 0.95
            ring.opacity = 0.0
            ring.allowsEdgeAntialiasing = true
            ring.contentsScale = scale
            root.addSublayer(ring)
            rippleLayers.append(ring)
        }

        // 4. Orbiting optical comet bloom behind main ring (follows white-cyan arc, zero offscreen shadow pass)
        let bloomD: CGFloat = 68
        outerGlowConicLayer.type = .conic
        outerGlowConicLayer.bounds = CGRect(x: 0, y: 0, width: bloomD, height: bloomD)
        outerGlowConicLayer.position = center
        outerGlowConicLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        outerGlowConicLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        outerGlowConicLayer.colors = [
            NSColor(red: 0.06, green: 0.42, blue: 0.96, alpha: 0.14).cgColor,
            NSColor(red: 0.10, green: 0.56, blue: 1.00, alpha: 0.28).cgColor,
            NSColor(red: 0.22, green: 0.78, blue: 1.00, alpha: 0.68).cgColor,
            NSColor(red: 0.78, green: 0.97, blue: 1.00, alpha: 0.88).cgColor,
            NSColor(red: 0.24, green: 0.76, blue: 1.00, alpha: 0.56).cgColor,
            NSColor(red: 0.06, green: 0.42, blue: 0.96, alpha: 0.14).cgColor
        ]
        outerGlowConicLayer.locations = [0.0, 0.36, 0.64, 0.82, 0.93, 1.0]
        outerGlowConicLayer.opacity = 0.62
        outerGlowConicLayer.allowsEdgeAntialiasing = true
        outerGlowConicLayer.contentsScale = scale

        outerGlowMask.frame = outerGlowConicLayer.bounds
        outerGlowMask.path = CGPath(
            ellipseIn: outerGlowConicLayer.bounds.insetBy(dx: 5.5, dy: 5.5),
            transform: nil
        )
        outerGlowMask.fillColor = nil
        outerGlowMask.strokeColor = NSColor.white.cgColor
        outerGlowMask.lineWidth = 7.5
        outerGlowMask.allowsEdgeAntialiasing = true
        outerGlowMask.contentsScale = scale
        outerGlowConicLayer.mask = outerGlowMask
        outerGlowConicLayer.transform = CATransform3DMakeRotation(CGFloat.pi * 0.28, 0, 0, 1)
        root.addSublayer(outerGlowConicLayer)

        // 5. Crisp primary luminous comet ring (58pt)
        let outerD: CGFloat = 58
        outerConicLayer.type = .conic
        outerConicLayer.bounds = CGRect(x: 0, y: 0, width: outerD, height: outerD)
        outerConicLayer.position = center
        outerConicLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        outerConicLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        outerConicLayer.colors = [
            NSColor(red: 0.08, green: 0.42, blue: 0.95, alpha: 0.26).cgColor,
            NSColor(red: 0.12, green: 0.54, blue: 1.00, alpha: 0.42).cgColor,
            NSColor(red: 0.26, green: 0.78, blue: 1.00, alpha: 0.82).cgColor,
            NSColor(red: 0.94, green: 0.99, blue: 1.00, alpha: 1.00).cgColor,
            NSColor(red: 0.42, green: 0.88, blue: 1.00, alpha: 0.86).cgColor,
            NSColor(red: 0.10, green: 0.48, blue: 0.98, alpha: 0.34).cgColor,
            NSColor(red: 0.08, green: 0.42, blue: 0.95, alpha: 0.26).cgColor
        ]
        outerConicLayer.locations = [0.0, 0.36, 0.68, 0.82, 0.91, 0.96, 1.0]
        outerConicLayer.allowsEdgeAntialiasing = true
        outerConicLayer.contentsScale = scale

        outerRingMask.frame = outerConicLayer.bounds
        outerRingMask.path = CGPath(
            ellipseIn: outerConicLayer.bounds.insetBy(dx: 1.6, dy: 1.6),
            transform: nil
        )
        outerRingMask.fillColor = nil
        outerRingMask.strokeColor = NSColor.white.cgColor
        outerRingMask.lineWidth = 2.0
        outerRingMask.allowsEdgeAntialiasing = true
        outerRingMask.contentsScale = scale
        outerConicLayer.mask = outerRingMask
        outerConicLayer.transform = CATransform3DMakeRotation(CGFloat.pi * 0.28, 0, 0, 1)
        root.addSublayer(outerConicLayer)

        // 6. Inner counter-rotating subtle accent shimmer (50pt)
        let innerD: CGFloat = 50
        innerConicLayer.type = .conic
        innerConicLayer.bounds = CGRect(x: 0, y: 0, width: innerD, height: innerD)
        innerConicLayer.position = center
        innerConicLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        innerConicLayer.endPoint = CGPoint(x: 0.0, y: 0.5)
        innerConicLayer.colors = [
            NSColor.clear.cgColor,
            NSColor(red: 0.22, green: 0.76, blue: 1.00, alpha: 0.08).cgColor,
            NSColor(red: 0.62, green: 0.93, blue: 1.00, alpha: 0.34).cgColor,
            NSColor(red: 0.22, green: 0.76, blue: 1.00, alpha: 0.10).cgColor,
            NSColor.clear.cgColor
        ]
        innerConicLayer.locations = [0.0, 0.45, 0.76, 0.90, 1.0]
        innerConicLayer.allowsEdgeAntialiasing = true
        innerConicLayer.contentsScale = scale

        innerRingMask.frame = innerConicLayer.bounds
        innerRingMask.path = CGPath(
            ellipseIn: innerConicLayer.bounds.insetBy(dx: 1.4, dy: 1.4),
            transform: nil
        )
        innerRingMask.fillColor = nil
        innerRingMask.strokeColor = NSColor.white.cgColor
        innerRingMask.lineWidth = 0.95
        innerRingMask.allowsEdgeAntialiasing = true
        innerRingMask.contentsScale = scale
        innerConicLayer.mask = innerRingMask
        root.addSublayer(innerConicLayer)

        // 7. Deep Obsidian-Navy Center Core with glowing azure inner rim
        let coreD: CGFloat = 44
        coreContainer.bounds = CGRect(x: 0, y: 0, width: coreD, height: coreD)
        coreContainer.position = center
        coreContainer.cornerRadius = coreD * 0.5
        coreContainer.masksToBounds = true
        coreContainer.backgroundColor = NSColor(red: 0.014, green: 0.030, blue: 0.086, alpha: 0.94).cgColor
        coreContainer.borderWidth = 1.0
        coreContainer.borderColor = NSColor(red: 0.24, green: 0.74, blue: 1.00, alpha: 0.52).cgColor
        coreContainer.allowsEdgeAntialiasing = true
        coreContainer.contentsScale = scale

        coreHorizonHighlight.type = .radial
        coreHorizonHighlight.frame = coreContainer.bounds
        coreHorizonHighlight.startPoint = CGPoint(x: 0.5, y: 0.5)
        coreHorizonHighlight.endPoint = CGPoint(x: 1.0, y: 1.0)
        coreHorizonHighlight.colors = [
            NSColor(red: 0.14, green: 0.62, blue: 1.00, alpha: 0.24).cgColor,
            NSColor(red: 0.04, green: 0.28, blue: 0.76, alpha: 0.10).cgColor,
            NSColor.clear.cgColor
        ]
        coreHorizonHighlight.locations = [0.0, 0.56, 1.0]
        coreHorizonHighlight.contentsScale = scale
        coreContainer.addSublayer(coreHorizonHighlight)

        coreSheenLayer.frame = CGRect(x: -coreD * 1.2, y: -coreD * 0.2, width: coreD * 1.4, height: coreD * 1.4)
        coreSheenLayer.colors = [
            NSColor.clear.cgColor,
            NSColor(red: 0.72, green: 0.94, blue: 1.00, alpha: 0.14).cgColor,
            NSColor.clear.cgColor
        ]
        coreSheenLayer.locations = [0.0, 0.5, 1.0]
        coreSheenLayer.startPoint = CGPoint(x: 0.0, y: 1.0)
        coreSheenLayer.endPoint = CGPoint(x: 1.0, y: 0.0)
        coreSheenLayer.contentsScale = scale
        coreContainer.addSublayer(coreSheenLayer)

        root.addSublayer(coreContainer)

        // 8. Crisp White Magnifying Glass SF Symbol (zero scale jitter)
        let cfg = NSImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold)
        magnifierView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Searching")?.withSymbolConfiguration(cfg)
        magnifierView.contentTintColor = NSColor(red: 0.95, green: 0.99, blue: 1.00, alpha: 1.0)
        magnifierView.wantsLayer = true
        magnifierView.layer?.shadowColor = NSColor(red: 0.42, green: 0.88, blue: 1.00, alpha: 1.0).cgColor
        magnifierView.layer?.shadowRadius = 5
        magnifierView.layer?.shadowOpacity = 0.55
        magnifierView.layer?.shadowOffset = .zero
        magnifierView.layer?.shouldRasterize = true
        magnifierView.layer?.rasterizationScale = scale
        magnifierView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(magnifierView)
        NSLayoutConstraint.activate([
            magnifierView.centerXAnchor.constraint(equalTo: centerXAnchor),
            magnifierView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func startAnimating() {
        guard !animationsStarted else { return }
        animationsStarted = true
        guard !AppSettings.shared.effectiveReduceMotion else { return }

        let smoothSine = CAMediaTimingFunction(controlPoints: 0.45, 0.05, 0.55, 0.95)

        // Breathing deep-blue radial aura
        if auraLayer.animation(forKey: "auraBreathe") == nil {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.94
            scale.toValue = 1.12
            scale.duration = 2.20
            scale.autoreverses = true
            scale.timingFunction = smoothSine
            scale.repeatCount = .infinity
            scale.isRemovedOnCompletion = false

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.62
            fade.toValue = 1.0
            fade.duration = 2.20
            fade.autoreverses = true
            fade.timingFunction = smoothSine
            fade.repeatCount = .infinity
            fade.isRemovedOnCompletion = false

            auraLayer.add(scale, forKey: "auraBreathe")
            auraLayer.add(fade, forKey: "auraFade")
        }

        // Delicate outer concentric halo ring breath
        if outerHaloRingLayer.animation(forKey: "haloBreathe") == nil {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.52
            fade.toValue = 0.92
            fade.duration = 2.20
            fade.autoreverses = true
            fade.timingFunction = smoothSine
            fade.repeatCount = .infinity
            fade.isRemovedOnCompletion = false
            outerHaloRingLayer.add(fade, forKey: "haloBreathe")
        }

        // Staggered sonar wave pulses
        let now = CACurrentMediaTime()
        let ringCount = max(1, rippleLayers.count)
        let ringDuration = 2.60
        let stagger = ringDuration / Double(ringCount)
        for (idx, ring) in rippleLayers.enumerated() where ring.animation(forKey: "sonarPulse") == nil {
            let expand = CABasicAnimation(keyPath: "transform.scale")
            expand.fromValue = 1.0
            expand.toValue = 1.78
            expand.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.80, 0.36, 1.0)

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.0, 0.24, 0.14, 0.0]
            fade.keyTimes = [0.0, 0.20, 0.56, 1.0]
            fade.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeIn)
            ]

            let group = CAAnimationGroup()
            group.animations = [expand, fade]
            group.duration = ringDuration
            group.beginTime = now + Double(idx) * stagger
            group.repeatCount = .infinity
            group.isRemovedOnCompletion = false
            ring.add(group, forKey: "sonarPulse")
        }

        // Synchronized comet arc + optical bloom clockwise rotation
        let initialAngle = Double.pi * 0.28
        if outerConicLayer.animation(forKey: "conicSpin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = initialAngle
            spin.toValue = initialAngle - (2.0 * Double.pi)
            spin.duration = 1.85
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            outerConicLayer.add(spin, forKey: "conicSpin")
        }
        if outerGlowConicLayer.animation(forKey: "conicBloomSpin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = initialAngle
            spin.toValue = initialAngle - (2.0 * Double.pi)
            spin.duration = 1.85
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            outerGlowConicLayer.add(spin, forKey: "conicBloomSpin")
        }

        // Inner counter-rotating subtle accent shimmer
        if innerConicLayer.animation(forKey: "innerSpin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0.0
            spin.toValue = 2.0 * Double.pi
            spin.duration = 3.40
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            innerConicLayer.add(spin, forKey: "innerSpin")
        }

        // Core center luminescence + periodic glass sheen sweep
        if coreHorizonHighlight.animation(forKey: "coreGlow") == nil {
            let glow = CABasicAnimation(keyPath: "opacity")
            glow.fromValue = 0.58
            glow.toValue = 1.0
            glow.duration = 1.85
            glow.autoreverses = true
            glow.timingFunction = smoothSine
            glow.repeatCount = .infinity
            glow.isRemovedOnCompletion = false
            coreHorizonHighlight.add(glow, forKey: "coreGlow")
        }

        if coreSheenLayer.animation(forKey: "coreSheenSweep") == nil {
            let sweep = CABasicAnimation(keyPath: "position.x")
            sweep.fromValue = -coreContainer.bounds.width * 0.9
            sweep.toValue = coreContainer.bounds.width * 1.9
            sweep.duration = 1.15
            sweep.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0.0, 0.25, 1.0)

            let group = CAAnimationGroup()
            group.animations = [sweep]
            group.duration = 2.40
            group.repeatCount = .infinity
            group.isRemovedOnCompletion = false
            coreSheenLayer.add(group, forKey: "coreSheenSweep")
        }

        if let iconLayer = magnifierView.layer, iconLayer.animation(forKey: "iconGlow") == nil {
            let breath = CABasicAnimation(keyPath: "opacity")
            breath.fromValue = 0.88
            breath.toValue = 1.0
            breath.duration = 1.85
            breath.autoreverses = true
            breath.timingFunction = smoothSine
            breath.repeatCount = .infinity
            breath.isRemovedOnCompletion = false
            iconLayer.add(breath, forKey: "iconGlow")
        }
    }

    func stopAnimating() {
        animationsStarted = false
        auraLayer.removeAllAnimations()
        outerHaloRingLayer.removeAllAnimations()
        rippleLayers.forEach { $0.removeAllAnimations() }
        outerGlowConicLayer.removeAllAnimations()
        outerConicLayer.removeAllAnimations()
        innerConicLayer.removeAllAnimations()
        coreHorizonHighlight.removeAllAnimations()
        coreSheenLayer.removeAllAnimations()
        magnifierView.layer?.removeAllAnimations()
    }
}
