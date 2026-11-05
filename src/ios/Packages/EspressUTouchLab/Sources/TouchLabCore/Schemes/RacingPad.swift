import CoreGraphics
import Foundation

public final class RacingPad: ControlScheme {
    public static let schemeInfo = SchemeInfo(
        id: "racing",
        name: "Racing",
        summary: "Made for Mario Kart 8: compact controls in the bottom corners. Steering on the left; Gas, Brake and a Drift pedal above Gas (slide up to drift) on the right, with Item, Look and Skill. Every action can be remapped.")

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

    public struct Options: Equatable, Sendable {
        public var autoAccelerate: Bool
        public var tilt: Bool
        /// Hold Gas for `lockHold` seconds and let go: Gas stays held. Tap Gas to release it.
        public var accelerateLock: Bool
        public var mapping: Mapping
        /// Seconds Gas must be held before letting go locks it.
        public var lockHold: Double
        public init(autoAccelerate: Bool = false, tilt: Bool = false,
                    accelerateLock: Bool = false, mapping: Mapping = .standard,
                    lockHold: Double = RacingPad.defaultLockHold) {
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

    public static let tiltFullLock: Double = 35 * .pi / 180

    private var lastAngle: Double?
    private var centreAngle: Double?
    public private(set) var tiltValue: Double = 0

    public init(options: Options = Options(), aScale: CGFloat = 1) {
        self.options = options
        self.aScale = aScale
        super.init(info: Self.schemeInfo)
    }

    override public func makeControls(_ context: LayoutContext) -> [PadControl] {
        RacingPad.build(context, options: options, aScale: aScale)
    }

    public static func build(_ ctx: LayoutContext, options: Options = Options(), aScale: CGFloat = 1) -> [PadControl] {
        var u = ctx.unit
        for _ in 0..<12 {
            if let set = arrangement(ctx, u: u, options: options, aScale: aScale),
               LayoutCheck.problems(set, in: ctx.safeBounds).isEmpty {
                return set
            }
            u *= 0.92
        }
        return arrangement(ctx, u: u, options: options, aScale: aScale, force: true) ?? []
    }

    static let pedalGroup = 31

    static func arrangement(_ ctx: LayoutContext, u: CGFloat, options: Options, aScale: CGFloat = 1, force: Bool = false) -> [PadControl]? {
        let s = ctx.safeBounds
        guard s.width > 0, s.height > 0 else { return nil }
        let landscape = s.width >= s.height
        let bandHeight = landscape ? s.height : min(s.height, max(8.5 * u, 0.46 * s.height))
        let bandTop = s.maxY - bandHeight
        let gap = 0.05 * u

        let a = PadParts.clampedAScale(aScale)
        // Compact corner layout: everything about half the old size, tucked into the
        // bottom corners so the middle of the screen stays clear.
        let wA = 1.35 * a * u, wB = 0.95 * u
        let hA = 1.25 * a * u, hC = 0.8 * u
        let xA = s.maxX - wA, xB = xA - wB
        let yA = s.maxY - hA, yC = yA - hC
        let brakeTop = yC + 0.35 * u
        func inset(_ r: CGRect) -> CGRect { r.insetBy(dx: gap / 2, dy: gap / 2) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { inset(CGRect(x: x, y: y, width: w, height: h)) }
        let corner = 0.25 * u
        let reach = gap

        func pedal(_ buttons: Set<PadButton>, _ r: CGRect, _ role: RenderElement.Role, _ label: String) -> PadControl {
            PadControl(.pedal(buttons), shape: .roundedRect(r, cornerRadius: corner), role: role, label: label,
                       group: pedalGroup, reach: reach, chords: false)
        }
        let m = options.mapping
        // Gas at the bottom-right edge, Drift (Gas + Drift together) straight above it so you
        // can slide up into a drift, Brake to the left. There is no separate drift-only pedal.
        var controls: [PadControl] = [
            pedal([m.accelerate], rect(xA, yA, wA, hA), .pedal, "GAS"),
            pedal([m.brake], rect(xB, brakeTop, wB, s.maxY - brakeTop), .pedal, "BRAKE"),
            pedal([m.accelerate, m.drift], rect(xA, yC, wA, hC), .pedal, "DRIFT"),
        ]

        // Item to the left of Brake; Look and Skill in a small row above the pedals.
        // A clear gap and a short reach keep them from stealing touches meant for a pedal.
        let clear = 0.35 * u
        let small: CGFloat = 0.2 * u
        let itemW = 1.25 * u, itemH = 0.85 * u
        let itemRect = CGRect(x: xB - clear - itemW, y: brakeTop, width: itemW, height: itemH)
        let smallH = 0.6 * u
        let rowTop = yC - clear - smallH
        let lookRect = CGRect(x: xB, y: rowTop, width: wB, height: smallH)
        let skillRect = CGRect(x: xA + gap, y: rowTop, width: wA - gap, height: smallH)
        func action(_ b: PadButton, _ r: CGRect, _ label: String) -> PadControl {
            PadControl(.button(b), shape: .roundedRect(inset(r), cornerRadius: corner), role: .shoulder, label: label,
                       reach: small / 2, priority: 2)
        }
        controls.append(action(m.item, itemRect, "ITEM"))
        controls.append(action(m.look, lookRect, "LOOK"))
        controls.append(action(m.skill, skillRect, "SKILL"))

        // Steering: a smaller area in the bottom-left corner.
        let steerRoom = itemRect.minX - s.minX - 0.5 * u
        let steerW = min(max(0.2 * s.width, 3.2 * u), steerRoom)
        let steerH = min(max(0.5 * bandHeight, 3.2 * u), bandHeight - 1.3 * u)
        let steer = CGRect(x: s.minX, y: s.maxY - steerH, width: steerW, height: steerH)
        let lockX = max(1.2 * u, min(0.3 * steerW, 2.2 * u))
        let lockY = 1.2 * lockX
        guard steer.width >= 2.8 * u, steer.height >= 3 * u || force else { return force ? controls : nil }
        let spec = SteerSpec(stick: .left, lockX: lockX, lockY: lockY, deadY: 0.45, followPast: 1.3, tilt: options.tilt)
        controls.append(PadControl(.steer(spec), shape: .roundedRect(inset(steer), cornerRadius: corner), role: .area,
                                   label: options.tilt ? "TILT" : "STEER", priority: 0))

        let rowY = bandTop + 0.2 * u + 0.4 * u
        let step = 1.3 * u
        var row: [PadControl] = [
            PadParts.system(.minus, at: CGPoint(x: s.midX - step, y: rowY), u: u),
            PadParts.system(.plus, at: CGPoint(x: s.midX, y: rowY), u: u),
            PadParts.system(.home, at: CGPoint(x: s.midX + step, y: rowY), u: u),
        ]
        if options.tilt {
            row.append(PadControl(.recentre, shape: .circle(center: CGPoint(x: s.midX + 2 * step, y: rowY), radius: PadParts.systemDiameter / 2 * u),
                                  role: .system, label: "C", reach: 0.25 * u, priority: 2))
        }
        for i in row.indices { row[i].priority = 2 }
        controls += row
        return controls
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
        return out
    }

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
        accelerateLocked = false
        super.layout(context)
        applyTilt()
    }
}
