#if canImport(UIKit)
import CoreMotion
import SwiftUI
import TouchLabCore
import UIKit

public final class TouchPadView: UIView {
    public let engine: PadEngine
    public var hapticsEnabled = true
    public var controlOpacity: CGFloat = 0.85 { didSet { setNeedsDisplay() } }
    public var onChange: (() -> Void)?
    public var touchscreenRect: CGRect? { didSet { relayout() } }
    public var videoRects: [CGRect] = [] { didSet { relayout() } }
    public var scale: CGFloat = 1 { didSet { relayout() } }
    public var stickSpacing: CGFloat = 0 { didSet { relayout() } }
    public var shoulderOffset: CGFloat = 0 { didSet { relayout() } }
    public var stickTuning = StickTuning() { didSet { relayout() } }
    public var rectSpace: RectSpace = .local { didSet { relayout() } }
    public var isInputEnabled = true {
        didSet {
            guard isInputEnabled != oldValue else { return }
            if !isInputEnabled { dropAll() }
            updateAmbient()
            setNeedsDisplay()
        }
    }

    public enum RectSpace: Equatable { case local, window }

    /// While true (and the scheme is `LayoutEditable`), touches move and resize controls instead of playing.
    public var isEditingLayout = false {
        didSet {
            guard isEditingLayout != oldValue else { return }
            endEdit(commit: true)
            selectedPiece = nil
            setNeedsDisplay()
        }
    }

    private enum EditMode { case move, resize, pinch }
    private var editing: LayoutEditable? { isEditingLayout ? engine.scheme as? LayoutEditable : nil }
    private var selectedPiece: String?
    private var editID: String?
    private var editMode: EditMode = .move
    private var editStartRect: CGRect = .zero
    private var editStartPoints: [ObjectIdentifier: CGPoint] = [:]
    private var editTouches: [ObjectIdentifier: CGPoint] = [:]
    private static let handleRadius: CGFloat = 13
    private static let minPieceSize: CGFloat = 28

    public var extraInsets = Insets() { didSet { relayout() } }

    private var displayLink: CADisplayLink?
    private var glowTimer: Timer?
    private let wheel = WheelAngleSource()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private var lastPressed: Set<PadButton> = []

    public init(scheme: TouchScheme, output: PadOutput) {
        engine = PadEngine(scheme: scheme, output: output, context: LayoutContext(size: .zero))
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        NotificationCenter.default.addObserver(self, selector: #selector(dropAll),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        displayLink?.invalidate()
        glowTimer?.invalidate()
        wheel.stop()
    }

    public func setScheme(_ scheme: TouchScheme) {
        engine.setScheme(scheme)
        relayout(force: true)
        updateAmbient()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        relayout()
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        relayout()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        relayout()
        updateAmbient()
    }

    private func toLocal(_ r: CGRect) -> CGRect {
        guard rectSpace == .window, window != nil else { return r }
        return convert(r, from: nil)
    }

    private func relayout(force: Bool = false) {
        let i = safeAreaInsets
        let e = extraInsets
        let ctx = LayoutContext(size: bounds.size,
                                safeInsets: Insets(top: i.top + e.top, left: i.left + e.left,
                                                   bottom: i.bottom + e.bottom, right: i.right + e.right),
                                videoRects: videoRects.map(toLocal), touchscreenRect: touchscreenRect.map(toLocal),
                                scale: scale, stick: stickTuning, stickSpacing: stickSpacing,
                                shoulderOffset: shoulderOffset)
        if force || ctx != engine.context {
            engine.setContext(ctx)
            if force { engine.scheme.layout(ctx) }
            changed()
        }
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if editing != nil {
            guard !isHidden, self.point(inside: point, with: event) else { return nil }
            return editID != nil || pieceHit(point) != nil ? self : nil
        }
        guard isInputEnabled, isUserInteractionEnabled, !isHidden, alpha > 0.01,
              self.point(inside: point, with: event) else { return nil }
        return engine.claims(point) ? self : nil
    }

    private func id(_ t: UITouch) -> TouchID { ObjectIdentifier(t).hashValue }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if editing != nil { editBegan(touches); return }
        for t in touches { engine.began(id(t), at: t.location(in: self), time: t.timestamp) }
        changed()
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if editing != nil { editMoved(touches); return }
        for t in touches {
            for c in event?.coalescedTouches(for: t) ?? [t] {
                engine.moved(id(t), to: c.location(in: self), time: c.timestamp)
            }
        }
        changed()
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if editing != nil { editEnded(touches); return }
        for t in touches { engine.ended(id(t), at: t.location(in: self), time: t.timestamp) }
        changed()
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if editing != nil { editEnded(touches); return }
        for t in touches { engine.cancelled(id(t), time: t.timestamp) }
        changed()
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            engine.ambientEnabled = false
            dropAll()
            wheel.stop()
        }
    }

    @objc public func dropAll() {
        engine.ambientEnabled = false
        engine.cancelAll()
        changed()
    }

    @objc private func becameActive() { updateAmbient() }

    private func updateAmbient() {
        let live = isInputEnabled && window != nil && UIApplication.shared.applicationState == .active
        engine.ambientEnabled = live
        if live, engine.scheme.wantsMotion {
            wheel.start { [weak self] angle in
                guard let self else { return }
                self.engine.motion(angle: angle)
                self.changed(redraw: self.engine.scheme.wantsMotion)
            } orientation: { [weak self] in
                self?.window?.windowScene?.interfaceOrientation ?? .landscapeRight
            }
        } else {
            wheel.stop()
        }
        changed()
    }

    private func changed(redraw: Bool = true) {
        let pressed = engine.mixer.pressed
        if hapticsEnabled, !pressed.subtracting(lastPressed).isEmpty {
            impact.impactOccurred(intensity: 0.7)
        }
        lastPressed = pressed
        updateDisplayLink()
        if redraw { setNeedsDisplay() }
        scheduleGlowRedraw()
        onChange?()
    }

    private func scheduleGlowRedraw() {
        glowTimer?.invalidate()
        glowTimer = nil
        guard let expiry = engine.nextLitExpiry() else { return }
        let delay = max(0.005, expiry - engine.clock())
        glowTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.glowTimer = nil
            self?.setNeedsDisplay()
        }
    }

    private func updateDisplayLink() {
        if engine.needsTicks, displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !engine.needsTicks, let link = displayLink {
            link.invalidate()
            displayLink = nil
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        engine.tick(time: link.timestamp)
        changed()
    }

    public override func draw(_ rect: CGRect) {
        guard let g = UIGraphicsGetCurrentContext() else { return }
        let opacity = editing != nil ? max(controlOpacity, 0.7) : controlOpacity
        for e in engine.render() { PadDrawing.draw(e, in: g, opacity: opacity) }
        if let ed = editing { drawEditing(ed.editablePieces) }
    }

    // MARK: Layout editing

    private func handleCenter(_ r: CGRect) -> CGPoint { CGPoint(x: r.minX, y: r.minY) }

    private func pieceHit(_ p: CGPoint) -> (piece: EditablePiece, mode: EditMode)? {
        guard let ed = editing else { return nil }
        let pieces = ed.editablePieces
        if let sel = selectedPiece, let piece = pieces.first(where: { $0.id == sel }),
           handleCenter(piece.rect).distance(to: p) <= Self.handleRadius + 10 {
            return (piece, .resize)
        }
        let hits = pieces.filter { $0.rect.insetBy(dx: -8, dy: -8).contains(p) }
        guard let best = hits.min(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }) else { return nil }
        return (best, .move)
    }

    private func currentRect(_ id: String) -> CGRect? {
        editing?.editablePieces.first { $0.id == id }?.rect
    }

    private func editBegan(_ touches: Set<UITouch>) {
        for t in touches {
            let p = t.location(in: self), key = ObjectIdentifier(t)
            if editID == nil {
                guard let hit = pieceHit(p) else { continue }
                selectedPiece = hit.piece.id
                if t.tapCount >= 2, hit.mode == .move {
                    // Double-tap puts a control back where the style places it.
                    editing?.resetEditedFrame(for: hit.piece.id)
                    editing?.commitEdits()
                    continue
                }
                editID = hit.piece.id
                editMode = hit.mode
                editStartRect = hit.piece.rect
                editTouches = [key: p]
                editStartPoints = editTouches
            } else if editTouches.count == 1, let id = editID {
                // A second finger pinches the control being dragged.
                editTouches[key] = p
                editStartRect = currentRect(id) ?? editStartRect
                editStartPoints = editTouches
                editMode = .pinch
            }
        }
        setNeedsDisplay()
    }

    private func editMoved(_ touches: Set<UITouch>) {
        for t in touches where editTouches[ObjectIdentifier(t)] != nil {
            editTouches[ObjectIdentifier(t)] = t.location(in: self)
        }
        guard let id = editID, let ed = editing else { return }
        var r = editStartRect
        let minS = Self.minPieceSize
        switch editMode {
        case .move, .resize:
            guard let first = editStartPoints.first, let now = editTouches[first.key] else { return }
            let dx = now.x - first.value.x, dy = now.y - first.value.y
            if editMode == .move {
                r = r.offsetBy(dx: dx, dy: dy)
            } else {
                let x = min(r.minX + dx, r.maxX - minS), y = min(r.minY + dy, r.maxY - minS)
                r = CGRect(x: x, y: y, width: r.maxX - x, height: r.maxY - y)
            }
        case .pinch:
            let keys = Array(editStartPoints.keys)
            guard keys.count == 2, let a0 = editStartPoints[keys[0]], let b0 = editStartPoints[keys[1]],
                  let a1 = editTouches[keys[0]], let b1 = editTouches[keys[1]] else { return }
            let scale = min(max(a1.distance(to: b1) / max(a0.distance(to: b0), 1), 0.25), 5)
            let mid0 = CGPoint(x: (a0.x + b0.x) / 2, y: (a0.y + b0.y) / 2)
            let mid1 = CGPoint(x: (a1.x + b1.x) / 2, y: (a1.y + b1.y) / 2)
            let w = max(r.width * scale, minS), h = max(r.height * scale, minS)
            r = CGRect(center: CGPoint(x: r.midX + mid1.x - mid0.x, y: r.midY + mid1.y - mid0.y),
                       size: CGSize(width: w, height: h))
        }
        ed.setEditedFrame(r, for: id)
        setNeedsDisplay()
    }

    private func editEnded(_ touches: Set<UITouch>) {
        for t in touches { editTouches.removeValue(forKey: ObjectIdentifier(t)) }
        if editMode == .pinch, editTouches.count == 1, let id = editID {
            // Lifting one finger of a pinch carries on as a drag with the other.
            editMode = .move
            editStartRect = currentRect(id) ?? editStartRect
            editStartPoints = editTouches
            return
        }
        if editTouches.isEmpty { endEdit(commit: true) }
        setNeedsDisplay()
    }

    private func endEdit(commit: Bool) {
        let wasEditing = editID != nil
        editID = nil
        editTouches.removeAll()
        editStartPoints.removeAll()
        if commit, wasEditing { (engine.scheme as? LayoutEditable)?.commitEdits() }
    }

    private func drawEditing(_ pieces: [EditablePiece]) {
        for piece in pieces {
            let selected = piece.id == selectedPiece
            let path = UIBezierPath(roundedRect: piece.rect.insetBy(dx: -2, dy: -2), cornerRadius: 8)
            path.lineWidth = selected ? 3 : 1.5
            path.setLineDash([6, 4], count: 2, phase: 0)
            (selected ? UIColor(red: 0.35, green: 0.62, blue: 1, alpha: 1) : UIColor.white.withAlphaComponent(0.85)).setStroke()
            path.stroke()
            guard selected else { continue }
            let c = handleCenter(piece.rect)
            let r = Self.handleRadius
            let knob = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            UIColor(red: 0.35, green: 0.62, blue: 1, alpha: 1).setFill()
            knob.fill()
            UIColor.white.setStroke()
            knob.lineWidth = 2
            knob.stroke()
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: c.x - r * 0.45, y: c.y - r * 0.45))
            arrow.addLine(to: CGPoint(x: c.x + r * 0.45, y: c.y + r * 0.45))
            arrow.lineWidth = 2
            arrow.stroke()
        }
    }
}

enum PadDrawing {
    static func draw(_ e: RenderElement, in g: CGContext, opacity: CGFloat) {
        let path: UIBezierPath
        switch e.shape {
        case .circle(let c, let r):
            path = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        case .roundedRect(let rect, let cr):
            path = UIBezierPath(roundedRect: rect, cornerRadius: cr)
        }
        let alpha: CGFloat
        switch e.role {
        case .zone: alpha = e.lit ? 0.10 : 0.0
        case .touchscreen: alpha = 0
        case .area: alpha = (e.lit ? 0.34 : 0.2) * opacity
        case .pedal: alpha = 0.62 * opacity
        default: alpha = (e.ghost ? 0.3 : 1) * opacity
        }
        guard alpha > 0 else { return }

        let (fill, stroke, text) = colours(e)
        fill.withAlphaComponent(alpha * (e.lit ? 0.95 : 0.55)).setFill()
        path.fill()
        stroke.withAlphaComponent(alpha * 0.9).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        guard !e.label.isEmpty, e.role != .zone, e.role != .stickBase else { return }
        let box = e.shape.boundingBox
        let fitWidth = 0.9 * box.width / max(CGFloat(e.label.count) * 0.62, 1)
        let size = max(min(box.height * 0.42, 26, fitWidth), 8)
        let label = LabelCache.image(e.label, size: size, text: text, alpha: alpha)
        label.draw(at: CGPoint(x: box.midX - label.size.width / 2, y: box.midY - label.size.height / 2))
    }

    static func colours(_ e: RenderElement) -> (UIColor, UIColor, UIColor) {
        if e.lit, e.role != .stickBase, e.role != .area {
            return (UIColor(red: 1, green: 0.79, blue: 0.24, alpha: 1), .white, UIColor(white: 0.1, alpha: 1))
        }
        switch e.role {
        case .face: return (UIColor(white: 0.93, alpha: 1), .white, UIColor(white: 0.12, alpha: 1))
        case .dpad: return (UIColor(white: 0.80, alpha: 1), .white, UIColor(white: 0.12, alpha: 1))
        case .shoulder: return (UIColor(white: 0.58, alpha: 1), UIColor(white: 0.8, alpha: 1), UIColor(white: 0.05, alpha: 1))
        case .system, .dot: return (UIColor(white: 0.40, alpha: 1), UIColor(white: 0.65, alpha: 1), .white)
        case .stickBase: return (UIColor(white: 0.22, alpha: 1), UIColor(white: 0.5, alpha: 1), .white)
        case .stickKnob: return (UIColor(white: 0.75, alpha: 1), .white, UIColor(white: 0.12, alpha: 1))
        case .zone, .touchscreen: return (UIColor(red: 0.5, green: 0.66, blue: 1, alpha: 1), .clear, .clear)
        case .area: return (UIColor(red: 0.5, green: 0.66, blue: 1, alpha: 1), UIColor(red: 0.6, green: 0.74, blue: 1, alpha: 1),
                            UIColor(red: 0.77, green: 0.84, blue: 1, alpha: 1))
        case .pedal: return (UIColor(white: 0.85, alpha: 1), .white, UIColor(white: 0.1, alpha: 1))
        }
    }
}

public struct TouchPad: UIViewRepresentable {
    public var schemeID: String
    public var revision: Int
    public var makeScheme: (String) -> TouchScheme
    public var output: PadOutput
    public var touchscreenRect: CGRect?
    public var videoRects: [CGRect]
    public var scale: CGFloat
    public var stickSpacing: CGFloat
    public var shoulderOffset: CGFloat
    public var opacity: CGFloat
    public var haptics: Bool
    public var enabled: Bool
    public var editing: Bool = false
    public var stickTuning: StickTuning
    public var rectSpace: TouchPadView.RectSpace
    public var extraInsets: Insets
    public var onChange: ((PadEngine) -> Void)?

    public init(schemeID: String, output: PadOutput, touchscreenRect: CGRect? = nil, videoRects: [CGRect] = [],
                scale: CGFloat = 1, stickSpacing: CGFloat = 0, shoulderOffset: CGFloat = 0, opacity: CGFloat = 0.85, haptics: Bool = true, revision: Int = 0,
                enabled: Bool = true, stickTuning: StickTuning = StickTuning(),
                rectSpace: TouchPadView.RectSpace = .local, extraInsets: Insets = Insets(),
                makeScheme: @escaping (String) -> TouchScheme = SchemeCatalog.make,
                onChange: ((PadEngine) -> Void)? = nil) {
        self.enabled = enabled
        self.stickTuning = stickTuning
        self.rectSpace = rectSpace
        self.extraInsets = extraInsets
        self.schemeID = schemeID
        self.revision = revision
        self.makeScheme = makeScheme
        self.output = output
        self.touchscreenRect = touchscreenRect
        self.videoRects = videoRects
        self.scale = scale
        self.stickSpacing = stickSpacing
        self.shoulderOffset = shoulderOffset
        self.opacity = opacity
        self.haptics = haptics
        self.onChange = onChange
    }

    public final class Coordinator {
        var revision = 0
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> TouchPadView {
        let view = TouchPadView(scheme: makeScheme(schemeID), output: output)
        context.coordinator.revision = revision
        apply(to: view)
        return view
    }

    public func updateUIView(_ view: TouchPadView, context: Context) {
        if view.engine.scheme.info.id != schemeID || context.coordinator.revision != revision {
            context.coordinator.revision = revision
            view.setScheme(makeScheme(schemeID))
        }
        apply(to: view)
    }

    private func apply(to view: TouchPadView) {
        if view.rectSpace != rectSpace { view.rectSpace = rectSpace }
        if view.extraInsets != extraInsets { view.extraInsets = extraInsets }
        if view.stickTuning != stickTuning { view.stickTuning = stickTuning }
        if view.isInputEnabled != enabled { view.isInputEnabled = enabled }
        if view.isEditingLayout != editing { view.isEditingLayout = editing }
        if view.touchscreenRect != touchscreenRect { view.touchscreenRect = touchscreenRect }
        if view.videoRects != videoRects { view.videoRects = videoRects }
        if view.scale != scale { view.scale = scale }
        if view.stickSpacing != stickSpacing { view.stickSpacing = stickSpacing }
        if view.shoulderOffset != shoulderOffset { view.shoulderOffset = shoulderOffset }
        if view.controlOpacity != opacity { view.controlOpacity = opacity }
        view.hapticsEnabled = haptics
        let engine = view.engine
        view.onChange = onChange.map { f in { f(engine) } }
    }

    public static func dismantleUIView(_ view: TouchPadView, coordinator: Coordinator) {
        view.dropAll()
    }
}
final class WheelAngleSource {
    private let manager = CMMotionManager()
    private var running = false

    func start(handler: @escaping (Double) -> Void, orientation: @escaping () -> UIInterfaceOrientation) {
        guard !running, manager.isDeviceMotionAvailable else { return }
        running = true
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let g = motion?.gravity else { return }
            let right: (Double, Double), down: (Double, Double)
            switch orientation() {
            case .portraitUpsideDown: right = (-1, 0); down = (0, 1)
            case .landscapeRight: right = (0, -1); down = (-1, 0)
            case .landscapeLeft: right = (0, 1); down = (1, 0)
            default: right = (1, 0); down = (0, -1)
            }
            let toRight = g.x * right.0 + g.y * right.1
            let toDown = g.x * down.0 + g.y * down.1
            guard (toRight * toRight + toDown * toDown).squareRoot() > 0.35 else { return }
            handler(atan2(toRight, toDown))
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopDeviceMotionUpdates()
    }
}

enum LabelCache {
    private struct Key: Hashable {
        let label: String
        let size: CGFloat
        let rgba: [CGFloat]
        let alpha: CGFloat
    }

    private static var images: [Key: UIImage] = [:]
    private static let limit = 256

    static func image(_ label: String, size: CGFloat, text: UIColor, alpha: CGFloat) -> UIImage {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !text.getRed(&r, green: &g, blue: &b, alpha: &a) {
            text.getWhite(&r, alpha: &a)
            g = r; b = r
        }
        let key = Key(label: label, size: size, rgba: [r, g, b, a], alpha: alpha)
        if let cached = images[key] { return cached }

        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let halo = NSShadow()
        halo.shadowColor = (luminance < 0.5 ? UIColor.white : UIColor.black).withAlphaComponent(alpha * 0.7)
        halo.shadowBlurRadius = max(1.5, size * 0.12)
        halo.shadowOffset = .zero
        let str = NSAttributedString(string: label, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: text.withAlphaComponent(alpha),
            .shadow: halo,
        ])
        let pad = ceil(halo.shadowBlurRadius * 2)
        let textSize = str.size()
        let canvas = CGSize(width: ceil(textSize.width) + 2 * pad, height: ceil(textSize.height) + 2 * pad)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            str.draw(at: CGPoint(x: pad, y: pad))
        }
        if images.count >= limit { images.removeAll(keepingCapacity: true) }
        images[key] = image
        return image
    }
}
#endif
