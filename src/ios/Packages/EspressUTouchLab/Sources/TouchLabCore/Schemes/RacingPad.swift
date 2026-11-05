import CoreGraphics
import Foundation

public final class RacingPad: ControlScheme {
    public static let schemeInfo = SchemeInfo(
        id: "racing",
        name: "Racing",
        summary: "Made for Mario Kart 8: a big steering area, Gas, Brake and Drift pedals where your thumb rests, a Gas+Drift zone, and Item, Look and Skill buttons. Every action can be remapped.")

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
        let wA = 2.7 * a * u, wB = 1.8 * u
        let hA = 2.3 * a * u, hC = 1.5 * u, hR = 1.3 * u
        let xA = s.maxX - wA, xB = xA - wB
        let yA = s.maxY - hA, yC = yA - hC, yR = yC - hR
        func inset(_ r: CGRect) -> CGRect { r.insetBy(dx: gap / 2, dy: gap / 2) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { inset(CGRect(x: x, y: y, width: w, height: h)) }
        let corner = 0.3 * u
        let reach = gap

        func pedal(_ buttons: Set<PadButton>, _ r: CGRect, _ role: RenderElement.Role, _ label: String) -> PadControl {
            PadControl(.pedal(buttons), shape: .roundedRect(r, cornerRadius: corner), role: role, label: label,
                       group: pedalGroup, reach: reach, chords: false)
        }
        let m = options.mapping
        var controls: [PadControl] = [
            pedal([m.accelerate], rect(xA, yA, wA, hA), .pedal, "GAS"),
            pedal([m.brake], rect(xB, yC, wB, hA + hC), .pedal, "BRAKE"),
            pedal([m.accelerate, m.drift], rect(xA, yC, wA, hC), .pedal, "GAS+DRIFT"),
            pedal([m.drift], rect(xB, yR, wB + wA, hR), .pedal, "DRIFT"),
        ]

        let steerMax = 0.36 * s.width
        let smallW = 1.6 * u, smallH = 1.1 * u, smallGap = 0.3 * u
        let itemW = 2 * smallW + smallGap, itemH = 1.25 * u
        let margin = 0.6 * u
        let centreRoom = xB - s.minX - steerMax
        var steerRight = s.minX + steerMax
        var steerTop = bandTop + (landscape ? 0.25 : 0.08) * bandHeight
        let itemRect: CGRect, lookRect: CGRect, skillRect: CGRect
        if centreRoom >= itemW + 2 * margin {
            // Item in the gap between steering and pedals; Look and Skill side by side just above it.
            let cx = (steerRight + xB) / 2
            itemRect = CGRect(x: cx - itemW / 2, y: yC - 0.2 * u, width: itemW, height: itemH)
            let rowY = itemRect.minY - smallGap - smallH
            lookRect = CGRect(x: itemRect.minX, y: rowY, width: smallW, height: smallH)
            skillRect = CGRect(x: itemRect.maxX - smallW, y: rowY, width: smallW, height: smallH)
        } else {
            // Narrow screens: Item top-left, Look and Skill under it, steering below them.
            itemRect = CGRect(x: s.minX + 0.3 * u, y: bandTop + 0.3 * u, width: itemW, height: itemH)
            let rowY = itemRect.maxY + 0.25 * u
            lookRect = CGRect(x: itemRect.minX, y: rowY, width: smallW, height: smallH)
            skillRect = CGRect(x: itemRect.maxX - smallW, y: rowY, width: smallW, height: smallH)
            steerTop = max(steerTop, lookRect.maxY + 0.35 * u)
            steerRight = min(steerRight, xB - 0.4 * u)
        }
        func action(_ b: PadButton, _ r: CGRect, _ label: String) -> PadControl {
            PadControl(.button(b), shape: .roundedRect(r, cornerRadius: corner), role: .shoulder, label: label,
                       reach: 0.2 * u, priority: 2)
        }
        controls.append(action(m.item, itemRect, "ITEM"))
        controls.append(action(m.look, lookRect, "LOOK"))
        controls.append(action(m.skill, skillRect, "SKILL"))

        let lockX = max(1.2 * u, min(0.3 * (steerRight - s.minX), 2.2 * u))
        let lockY = 1.2 * lockX
        let steer = CGRect(x: s.minX, y: steerTop, width: steerRight - s.minX, height: s.maxY - steerTop)
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
