import CoreGraphics
import Foundation

/// A piece of an on-screen layout that the player can move and resize.
public struct EditablePiece: Equatable, Sendable {
    public var id: String
    public var label: String
    public var rect: CGRect
    public var moved: Bool
    public init(id: String, label: String, rect: CGRect, moved: Bool) {
        self.id = id
        self.label = label
        self.rect = rect
        self.moved = moved
    }
}

/// A scheme whose controls can be dragged and resized by the player.
public protocol LayoutEditable: AnyObject {
    var editablePieces: [EditablePiece] { get }
    /// Live update while a piece is dragged (view coordinates).
    func setEditedFrame(_ rect: CGRect, for id: String)
    /// Puts one piece back where the style places it.
    func resetEditedFrame(for id: String)
    /// Called when a drag ends so the new layout can be saved.
    func commitEdits()
}

public final class RacingPad: ControlScheme, LayoutEditable {
    public static let schemeInfo = SchemeInfo(
        id: "racing",
        name: "Mario Kart 8",
        summary: "Made for Mario Kart 8: compact controls in the bottom corners. Steering on the left; Gas, Brake, Drift, Item, Look and Skill on the right. Every action can be remapped, and the buttons can be moved and resized here.")

    /// Which Wii U button each racing action sends.
    public struct Mapping: Equatable, Sendable {
        public var accelerate: PadButton
        public var brake: PadButton
        public var drift: PadButton
        public var item: PadButton
        public var look: PadButton
        public var skill: PadButton

        public init(accelerate: PadButton = .a, brake: PadButton = .b, drift: PadButton = .r,
                    item: PadButton = .l, look: PadButton = .x, skill: PadButton = .up) {
            self.accelerate = accelerate
            self.brake = brake
            self.drift = drift
            self.item = item
            self.look = look
            self.skill = skill
        }

        public static let standard = Mapping()

        public var all: [PadButton] { [accelerate, brake, drift, item, look, skill] }
    }

    /// Where the player put a control: centre as a fraction of the safe area, size in layout units.
    public struct Placement: Equatable, Sendable, Codable {
        public var cx: Double
        public var cy: Double
        public var w: Double
        public var h: Double
        public init(cx: Double, cy: Double, w: Double, h: Double) {
            self.cx = cx; self.cy = cy; self.w = w; self.h = h
        }
    }

    public static let pieceIDs = ["gas", "brake", "drift", "item", "look", "skill", "steer", "minus", "plus", "home", "recentre"]

    public static func encode(_ p: [String: Placement]) -> String {
        guard !p.isEmpty, let d = try? JSONEncoder().encode(p) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    public static func decode(_ s: String) -> [String: Placement] {
        guard !s.isEmpty, let d = s.data(using: .utf8),
              let p = try? JSONDecoder().decode([String: Placement].self, from: d) else { return [:] }
        return p.filter { pieceIDs.contains($0.key) && $0.value.w > 0 && $0.value.h > 0 }
    }

    public struct Options: Equatable, Sendable {
        public var autoAccelerate: Bool
        public var tilt: Bool
        /// Hold Gas for `lockHold` seconds and let go: Gas stays held. Tap Gas to release it.
        public var accelerateLock: Bool
        public var mapping: Mapping
        /// Seconds Gas must be held before letting go locks it.
        public var lockHold: Double
        /// Draw symbols instead of words on the buttons.
        public var icons: Bool
        public init(autoAccelerate: Bool = false, tilt: Bool = false,
                    accelerateLock: Bool = false, mapping: Mapping = .standard,
                    lockHold: Double = RacingPad.defaultLockHold, icons: Bool = false) {
            self.icons = icons
            self.autoAccelerate = autoAccelerate
            self.tilt = tilt
            self.accelerateLock = accelerateLock
            self.mapping = mapping
            self.lockHold = lockHold
        }
    }

    public static let defaultLockHold: Double = 0.6
    public static let lockHoldRange: ClosedRange<Double> = 0.2...2.0
    public static let unlockTap: Double = 0.3
    public static let lockedLabel = "GAS \u{1F512}"

    /// True while the accelerate lock is holding Gas for you.
    public private(set) var accelerateLocked = false

    public let options: Options
    public let aScale: CGFloat
    /// The player's moved/resized controls.
    public private(set) var placements: [String: Placement]
    /// Called with the new placements when an edit is finished.
    public var onPlacementsChanged: (([String: Placement]) -> Void)?

    public static let tiltFullLock: Double = 35 * .pi / 180

    private var lastAngle: Double?
    private var centreAngle: Double?
    public private(set) var tiltValue: Double = 0

    public init(options: Options = Options(), aScale: CGFloat = 1, placements: [String: Placement] = [:]) {
        self.options = options
        self.aScale = aScale
        self.placements = placements
        super.init(info: Self.schemeInfo)
    }

    override public func makeControls(_ context: LayoutContext) -> [PadControl] {
        RacingPad.build(context, options: options, aScale: aScale, placements: placements)
    }

    public static func build(_ ctx: LayoutContext, options: Options = Options(), aScale: CGFloat = 1,
                             placements: [String: Placement] = [:]) -> [PadControl] {
        var u = ctx.unit
        if placements.isEmpty {
            for _ in 0..<12 {
                if let set = arrangement(ctx, u: u, options: options, aScale: aScale),
                   LayoutCheck.problems(set, in: ctx.safeBounds).isEmpty {
                    return set
                }
                u *= 0.92
            }
        }
        // With the player's own placements, overlaps are their call: lay out at full size.
        return arrangement(ctx, u: placements.isEmpty ? u : ctx.unit, options: options, aScale: aScale,
                           placements: placements, force: true) ?? []
    }

    static let pedalGroup = 31

    /// The editable piece a control belongs to, if any.
    public static func pieceID(_ c: PadControl) -> String? {
        if case .steer = c.kind { return "steer" }
        if case .recentre = c.kind { return "recentre" }
        if c.role == .system, let b = c.button {
            switch b {
            case .minus: return "minus"
            case .plus: return "plus"
            case .home: return "home"
            default: return nil
            }
        }
        switch c.label {
        case "GAS", lockedLabel: return "gas"
        case "BRAKE": return "brake"
        case "DRIFT": return "drift"
        case "ITEM": return "item"
        case "LOOK": return "look"
        case "SKILL": return "skill"
        default: return nil
        }
    }

    static func arrangement(_ ctx: LayoutContext, u: CGFloat, options: Options, aScale: CGFloat = 1,
                            placements: [String: Placement] = [:], force: Bool = false) -> [PadControl]? {
        let s = ctx.safeBounds
        guard s.width > 0, s.height > 0 else { return nil }
        let landscape = s.width >= s.height
        let bandHeight = landscape ? s.height : min(s.height, max(8.5 * u, 0.46 * s.height))
        let bandTop = s.maxY - bandHeight
        let gap = 0.05 * u
        let corner = 0.25 * u
        func inset(_ r: CGRect) -> CGRect { r.insetBy(dx: gap / 2, dy: gap / 2) }

        // Player placement, kept inside the safe area.
        func placed(_ id: String, _ r: CGRect) -> CGRect {
            guard let p = placements[id] else { return inset(r) }
            let w = min(max(CGFloat(p.w) * u, 24), s.width), h = min(max(CGFloat(p.h) * u, 24), s.height)
            var x = s.minX + CGFloat(p.cx) * s.width - w / 2
            var y = s.minY + CGFloat(p.cy) * s.height - h / 2
            x = min(max(x, s.minX), s.maxX - w)
            y = min(max(y, s.minY), s.maxY - h)
            return CGRect(x: x, y: y, width: w, height: h)
        }

        let a = PadParts.clampedAScale(aScale)
        // Compact corner layout tucked into the bottom corners so the middle stays clear.
        let wA = 1.35 * a * u, wB = 0.95 * u
        let hA = 1.25 * a * u
        let clear = 0.35 * u
        let xA = s.maxX - wA, xB = xA - wB
        let yA = s.maxY - hA
        let hD = 0.85 * u
        let yD = yA - clear - hD
        let smallH = 0.6 * u
        let itemW = 1.25 * u, itemH = 0.85 * u

        let m = options.mapping
        func pedal(_ buttons: Set<PadButton>, _ r: CGRect, _ label: String) -> PadControl {
            PadControl(.pedal(buttons), shape: .roundedRect(r, cornerRadius: corner), role: .pedal, label: label,
                       group: pedalGroup, reach: gap, chords: false)
        }
        func action(_ b: PadButton, _ r: CGRect, _ label: String) -> PadControl {
            PadControl(.button(b), shape: .roundedRect(r, cornerRadius: corner), role: .shoulder, label: label,
                       reach: 0.1 * u, priority: 2)
        }

        // Gas bottom-right with Brake beside it (slide between them). Drift is its own button above
        // Gas, so with the accelerate lock on your thumb is free for Drift, Item and Skill.
        var controls: [PadControl] = [
            pedal([m.accelerate], placed("gas", CGRect(x: xA, y: yA, width: wA, height: hA)), "GAS"),
            pedal([m.brake], placed("brake", CGRect(x: xB, y: yA, width: wB, height: hA)), "BRAKE"),
            action(m.drift, placed("drift", CGRect(x: xA, y: yD, width: wA, height: hD)), "DRIFT"),
            action(m.look, placed("look", CGRect(x: xB, y: yD, width: wB - clear, height: hD)), "LOOK"),
            action(m.skill, placed("skill", CGRect(x: xA, y: yD - clear - smallH, width: wA, height: smallH)), "SKILL"),
            action(m.item, placed("item", CGRect(x: xB - clear - itemW, y: s.maxY - itemH - 0.2 * u,
                                                 width: itemW, height: itemH)), "ITEM"),
        ]

        // Steering: a smaller area in the bottom-left corner.
        let itemLeft = xB - clear - itemW
        let steerRoom = itemLeft - s.minX - 0.5 * u
        let steerW = min(max(0.2 * s.width, 3.2 * u), steerRoom)
        let steerH = min(max(0.5 * bandHeight, 3.2 * u), bandHeight - 1.3 * u)
        let steerDefault = CGRect(x: s.minX, y: s.maxY - steerH, width: steerW, height: steerH)
        let steer = placed("steer", steerDefault)
        if placements["steer"] == nil, !force {
            guard steer.width >= 2.8 * u, steer.height >= 3 * u else { return nil }
        }
        let lockX = max(min(1.2 * u, 0.4 * steer.width), min(0.3 * steer.width, 2.2 * u))
        let lockY = 1.2 * lockX
        let spec = SteerSpec(stick: .left, lockX: lockX, lockY: lockY, deadY: 0.45, followPast: 1.3, tilt: options.tilt)
        controls.append(PadControl(.steer(spec), shape: .roundedRect(steer, cornerRadius: corner), role: .area,
                                   label: options.tilt ? "TILT" : "STEER", priority: 0))

        let rowY = bandTop + 0.2 * u + 0.4 * u
        let step = 1.3 * u
        // Menu buttons: circles, so a placed one uses the largest circle that fits its box.
        func circle(_ id: String, _ x: CGFloat) -> PadShape {
            let d = PadParts.systemDiameter * u
            let r = placed(id, CGRect(center: CGPoint(x: x, y: rowY), size: CGSize(width: d + gap, height: d + gap)))
            return .circle(center: r.center, radius: min(r.width, r.height) / 2)
        }
        func system(_ b: PadButton, _ id: String, _ x: CGFloat) -> PadControl {
            var c = PadParts.system(b, at: .zero, u: u)
            c.shape = circle(id, x)
            return c
        }
        var row: [PadControl] = [
            system(.minus, "minus", s.midX - step),
            system(.plus, "plus", s.midX),
            system(.home, "home", s.midX + step),
        ]
        if options.tilt {
            row.append(PadControl(.recentre, shape: circle("recentre", s.midX + 2 * step),
                                  role: .system, label: "C", reach: 0.25 * u, priority: 2))
        }
        for i in row.indices { row[i].priority = 2 }
        controls += row
        return controls
    }

    // MARK: Editing

    public var editablePieces: [EditablePiece] {
        controls.compactMap { c in
            guard let id = Self.pieceID(c) else { return nil }
            return EditablePiece(id: id, label: id == "gas" ? "GAS" : c.label, rect: c.shape.boundingBox,
                                 moved: placements[id] != nil)
        }
    }

    public func setEditedFrame(_ rect: CGRect, for id: String) {
        let s = context.safeBounds, u = context.unit
        guard s.width > 0, s.height > 0, u > 0 else { return }
        placements[id] = Placement(cx: Double((rect.midX - s.minX) / s.width), cy: Double((rect.midY - s.minY) / s.height),
                                   w: Double(rect.width / u), h: Double(rect.height / u))
        relayoutKeepingLock()
    }

    public func resetEditedFrame(for id: String) {
        placements[id] = nil
        relayoutKeepingLock()
    }

    public func resetAllEdits() {
        placements = [:]
        relayoutKeepingLock()
        commitEdits()
    }

    public func commitEdits() { onPlacementsChanged?(placements) }

    private func relayoutKeepingLock() {
        let locked = accelerateLocked
        layout(context)
        accelerateLocked = locked
    }

    override public var wantsMotion: Bool { options.tilt }

    public func recentre() {
        centreAngle = lastAngle
        applyTilt()
    }

    override public func recentreRequested() { recentre() }

    override public func motion(angle: Double) -> [TouchID: Contribution] {
        guard options.tilt else { return [:] }
        lastAngle = angle
        if centreAngle == nil { centreAngle = angle }
        applyTilt()
        var out: [TouchID: Contribution] = [:]
        for (id, t) in tracks {
            if case .steer = controls[t.control].kind {
                out[id] = contribution(for: &tracks[id]!, at: t.last, time: t.lastTime)
            }
        }
        return out
    }

    private func applyTilt() {
        guard options.tilt, let angle = lastAngle, let centre = centreAngle else {
            tiltValue = 0
            steerOverrideX = options.tilt ? 0 : nil
            return
        }
        var d = angle - centre
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        let dead = context.stick.deadzone
        let raw = abs(d) / Self.tiltFullLock
        var v = 0.0
        if raw > dead {
            let live = min((raw - dead) / max(1 - dead, 0.0001), 1)
            v = pow(live, context.stick.curve)
        }
        tiltValue = d < 0 ? -v : v
        steerOverrideX = tiltValue
    }

    private func isGas(_ index: Int) -> Bool {
        guard controls.indices.contains(index), case .pedal(let set) = controls[index].kind else { return false }
        return set == [options.mapping.accelerate]
    }

    override public func didEnd(control index: Int, start: CGPoint, end: CGPoint, duration: Double) {
        guard options.accelerateLock, isGas(index) else { return }
        if accelerateLocked {
            if duration < Self.unlockTap { accelerateLocked = false }
        } else if duration >= min(max(options.lockHold, Self.lockHoldRange.lowerBound), Self.lockHoldRange.upperBound) {
            accelerateLocked = true
        }
    }

    public func releaseAccelerateLock() { accelerateLocked = false }

    override public func render(pressed: Set<PadButton>, sticks: [PadStick: StickValue]) -> [RenderElement] {
        var out = super.render(pressed: pressed, sticks: sticks)
        if accelerateLocked, let i = out.firstIndex(where: { $0.role == .pedal && $0.label == "GAS" }) {
            out[i].label = Self.lockedLabel
            out[i].lit = true
        }
        if options.icons {
            for i in out.indices {
                if let name = Self.symbols[out[i].label] {
                    out[i].label = RenderElement.symbolLabel(name, fallback: out[i].label)
                }
            }
        }
        return out
    }

    /// SF Symbol drawn for each label when icons are on; the word is the fallback.
    public static let symbols: [String: String] = [
        "GAS": "pedal.accelerator.fill",
        lockedLabel: "lock.fill",
        "BRAKE": "pedal.brake.fill",
        "DRIFT": "car.rear.and.tire.marks",
        "ITEM": "gift.fill",
        "LOOK": "eye.fill",
        "SKILL": "sparkles",
        "STEER": "steeringwheel",
        "TILT": "steeringwheel",
    ]

    override public func ambient() -> Contribution? {
        var buttons: Set<PadButton> = []
        if options.autoAccelerate || accelerateLocked {
            let brake = options.mapping.brake
            let braking = tracks.values.contains { $0.buttons.contains(brake) }
            if !braking { buttons.insert(options.mapping.accelerate) }
        }
        var stick: PadStick?
        var value = StickValue.zero
        if options.tilt {
            let steering = tracks.values.contains { if case .steer = controls[$0.control].kind { return true }; return false }
            if !steering { stick = .left; value = StickValue(x: tiltValue, y: 0) }
        }
        if buttons.isEmpty && stick == nil { return nil }
        return Contribution(buttons: buttons, stick: stick, stickValue: value)
    }

    override public func layout(_ context: LayoutContext) {
        // The accelerate lock survives re-layouts (rotation, screen changes); only a tap on Gas,
        // or a new scheme when settings change, lets it go.
        super.layout(context)
        applyTilt()
    }
}
