// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import TouchLabCore
import TouchLabUI

enum TouchLabSettings {
    static let schemeKey = "espressu.pad.touchlabScheme"
    /// Zone (always-on sticks and buttons) is what new players get. An empty value is the original pad, still
    /// offered as "EspressU (classic)". Anyone who already picked a style keeps it, because `@AppStorage` only
    /// falls back to this value when nothing is stored.
    static let defaultScheme = "zone"

    static let floatCameraKey = "espressu.touchlab.float.camera"
    static let defaultFloatCamera = FloatPad.Camera.stick.rawValue

    static let racingAutoAccelerateKey = "espressu.touchlab.racing.autoAccelerate"
    static let racingTiltKey = "espressu.touchlab.racing.tilt"
    static let racingLockKey = "espressu.touchlab.racing.accelerateLock"
    static let racingLockHoldKey = "espressu.touchlab.racing.lockHold"
    static let defaultRacingLockHold = RacingPad.defaultLockHold
    static let racingLockHoldRange = RacingPad.lockHoldRange
    /// JSON of the player's moved/resized Racing controls.
    static let racingPlacementsKey = "espressu.touchlab.racing.placements"

    static func resetRacingPlacements() {
        UserDefaults.standard.removeObject(forKey: racingPlacementsKey)
    }

    /// One remappable racing action and the key its Wii U button is stored under.
    struct RacingAction: Identifiable {
        let id: String
        let title: String
        let detail: String
        let fallback: PadButton
        var key: String { "espressu.touchlab.racing.map." + id }
    }

    static let racingActions: [RacingAction] = [
        RacingAction(id: "accelerate", title: "Accelerate (Gas)", detail: "Bottom-right pedal", fallback: .a),
        RacingAction(id: "brake", title: "Brake / Reverse", detail: "Pedal left of Gas", fallback: .b),
        RacingAction(id: "drift", title: "Drift / Hop", detail: "Button above Gas", fallback: .r),
        RacingAction(id: "item", title: "Item", detail: "Bottom, left of Brake", fallback: .l),
        RacingAction(id: "look", title: "Look behind", detail: "Left of Drift", fallback: .x),
        RacingAction(id: "skill", title: "Skill", detail: "Above Drift", fallback: .up),
    ]

    /// Buttons a racing action can be mapped to (Home is left out so it can't be pressed mid-race by accident).
    static let racingMappableButtons: [PadButton] = [.a, .b, .x, .y, .l, .r, .zl, .zr,
                                                      .up, .down, .left, .right, .plus, .minus, .stickL, .stickR]

    static func buttonName(_ b: PadButton) -> String {
        switch b {
        case .up: return "D-pad Up"
        case .down: return "D-pad Down"
        case .left: return "D-pad Left"
        case .right: return "D-pad Right"
        case .plus: return "+ (Plus)"
        case .minus: return "\u{2212} (Minus)"
        case .stickL: return "L-stick click"
        case .stickR: return "R-stick click"
        case .home: return "Home"
        default: return b.description
        }
    }

    static func racingButton(_ action: RacingAction, _ defaults: UserDefaults = .standard) -> PadButton {
        guard defaults.object(forKey: action.key) != nil,
              let b = PadButton(rawValue: defaults.integer(forKey: action.key)) else { return action.fallback }
        return b
    }

    static func racingMapping(_ defaults: UserDefaults = .standard) -> RacingPad.Mapping {
        func b(_ id: String) -> PadButton { racingButton(racingActions.first { $0.id == id }!, defaults) }
        return RacingPad.Mapping(accelerate: b("accelerate"), brake: b("brake"), drift: b("drift"),
                                 item: b("item"), look: b("look"), skill: b("skill"))
    }

    static func resetRacingMapping() {
        for a in racingActions { UserDefaults.standard.removeObject(forKey: a.key) }
    }

    static let aScaleKey = "espressu.touchlab.aScale"
    static let defaultAScale = 1.0
    static let aScaleRange = 1.0...1.8

    private static let legacyLargeAKey = "espressu.touchlab.zone.largeA"
    static func migrateLegacyLargeA() {
        let d = UserDefaults.standard
        guard d.object(forKey: aScaleKey) == nil else { return }
        if d.bool(forKey: legacyLargeAKey) { d.set(1.4, forKey: aScaleKey) }
    }

    static let adaptiveResetKey = "espressu.touchlab.adaptive.resetCount"

    static func adaptiveKey(gameID: String?) -> String {
        "espressu.touchlab.adaptive." + (gameID ?? "default")
    }

    static let schemes: [SchemeInfo] = SchemeCatalog.all

    static func isTouchLab(_ id: String) -> Bool {
        schemes.contains { $0.id == id }
    }

    static func name(_ id: String) -> String {
        schemes.first { $0.id == id }?.name ?? "EspressU"
    }

    static func adoptAdaptiveKey(from oldID: String, to newID: String) {
        let d = UserDefaults.standard
        let old = adaptiveKey(gameID: oldID), new = adaptiveKey(gameID: newID)
        guard let learned = d.string(forKey: old), d.object(forKey: new) == nil else { return }
        d.set(learned, forKey: new)
        d.removeObject(forKey: old)
    }

    static func resetAdaptive(gameID: String?) {
        let d = UserDefaults.standard
        d.removeObject(forKey: adaptiveKey(gameID: gameID))
        d.set(d.integer(forKey: adaptiveResetKey) &+ 1, forKey: adaptiveResetKey)
    }

    static func resetAdaptiveAll() {
        let d = UserDefaults.standard
        let prefix = adaptiveKey(gameID: "")
        for key in d.dictionaryRepresentation().keys where key.hasPrefix(prefix) && key != adaptiveResetKey {
            d.removeObject(forKey: key)
        }
        d.set(d.integer(forKey: adaptiveResetKey) &+ 1, forKey: adaptiveResetKey)
    }

    struct Style: Identifiable {
        let id: String
        let name: String
        let summary: String
    }

    static let styles: [Style] = schemes.map { Style(id: $0.id, name: $0.name, summary: $0.summary) }

    static func summary(_ id: String) -> String {
        styles.first { $0.id == id }?.summary ?? ""
    }

    static let floatStyleID = FloatPad.schemeInfo.id
    static let adaptiveStyleID = AdaptivePad.schemeInfo.id
    static let zoneStyleID = ZonePad.schemeInfo.id
    static let racingStyleID = RacingPad.schemeInfo.id

    static func hasFixedSticks(_ id: String) -> Bool {
        id == zoneStyleID || id == adaptiveStyleID
    }

    static func hasMovableShoulders(_ id: String) -> Bool {
        id == zoneStyleID || id == adaptiveStyleID
    }

    static let cameraOptions: [(value: String, title: String)] = [
        (FloatPad.Camera.stick.rawValue, "Floating stick"),
        (FloatPad.Camera.swipe.rawValue, "Swipe"),
    ]
}

@MainActor
final class CemuBridgePadOutput: @preconcurrency PadOutput {
    static let shared = CemuBridgePadOutput()

    var gamepadViewSize: CGSize = .zero

    func setButton(_ button: PadButton, pressed: Bool) {
        PadDiagnostics.shared.recordInput(Self.label(button), pressed)
        if button == .home {
            HomeMenuRouter.shared.padHome(pressed: pressed)
            return
        }
        cemu_bridge_set_button_state(Self.bridgeButton(button), pressed)
    }

    func setStick(_ stick: PadStick, _ value: StickValue) {
        PadDiagnostics.shared.recordStick(stick.rawValue, CGPoint(x: value.x, y: value.y))
        cemu_bridge_set_stick_axis(stick == .left ? CEMU_BRIDGE_STICK_LEFT : CEMU_BRIDGE_STICK_RIGHT,
                                   Float(value.x), Float(value.y))
    }

    private var lastTouchPixel: (x: Double, y: Double)?

    func setTouchscreen(_ point: CGPoint?) {
        guard let point, gamepadViewSize.width > 0, gamepadViewSize.height > 0 else {
            if let last = lastTouchPixel {
                cemu_bridge_set_pad_touch(last.x, last.y, false)
                lastTouchPixel = nil
            } else {
                cemu_bridge_set_pad_touch(0, 0, false)
            }
            return
        }
        let scale = DisplayRouter.shared.padSurfaceScale
        let x = Double(point.x * gamepadViewSize.width) * scale
        let y = Double(point.y * gamepadViewSize.height) * scale
        lastTouchPixel = (x, y)
        cemu_bridge_set_pad_touch(x, y, true)
    }

    func releaseAll() {
        cemu_bridge_release_all_buttons()
        lastTouchPixel = nil
        cemu_bridge_set_pad_touch(0, 0, false)
    }

    static func bridgeButton(_ b: PadButton) -> CemuBridgeButton {
        switch b {
        case .a: return CEMU_BRIDGE_BUTTON_A
        case .b: return CEMU_BRIDGE_BUTTON_B
        case .x: return CEMU_BRIDGE_BUTTON_X
        case .y: return CEMU_BRIDGE_BUTTON_Y
        case .l: return CEMU_BRIDGE_BUTTON_L
        case .r: return CEMU_BRIDGE_BUTTON_R
        case .zl: return CEMU_BRIDGE_BUTTON_ZL
        case .zr: return CEMU_BRIDGE_BUTTON_ZR
        case .plus: return CEMU_BRIDGE_BUTTON_PLUS
        case .minus: return CEMU_BRIDGE_BUTTON_MINUS
        case .up: return CEMU_BRIDGE_BUTTON_UP
        case .down: return CEMU_BRIDGE_BUTTON_DOWN
        case .left: return CEMU_BRIDGE_BUTTON_LEFT
        case .right: return CEMU_BRIDGE_BUTTON_RIGHT
        case .stickL: return CEMU_BRIDGE_BUTTON_STICK_L
        case .stickR: return CEMU_BRIDGE_BUTTON_STICK_R
        case .home: return CEMU_BRIDGE_BUTTON_HOME
        }
    }

    static func label(_ b: PadButton) -> String {
        switch b {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .l: return "L"
        case .r: return "R"
        case .zl: return "ZL"
        case .zr: return "ZR"
        case .plus: return "plus"
        case .minus: return "minus"
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .stickL: return "L3"
        case .stickR: return "R3"
        case .home: return "HOME"
        }
    }
}

struct TouchLabPadOverlay: View {
    let schemeID: String
    let gameID: String?
    let screens: TouchLabScreenState
    let enabled: Bool
    var editing: Bool = false
    let topInset: CGFloat

    @AppStorage(ControllerLayoutSettings.scaleKey) private var scale = ControllerLayoutSettings.defaultScale
    @AppStorage(ControllerLayoutSettings.stickSpacingKey) private var stickSpacing = ControllerLayoutSettings.defaultStickSpacing
    @AppStorage(ControllerLayoutSettings.shoulderOffsetKey) private var shoulderOffset = ControllerLayoutSettings.defaultShoulderOffset
    @AppStorage(ControllerLayoutSettings.opacityKey) private var opacity = ControllerLayoutSettings.defaultOpacity
    @AppStorage(ControllerLayoutSettings.hapticsKey) private var haptics = ControllerLayoutSettings.defaultHaptics
    @AppStorage(ControllerLayoutSettings.deadzoneKey) private var deadzone = ControllerLayoutSettings.defaultDeadzone
    @AppStorage(ControllerLayoutSettings.stickCurveKey) private var curve = ControllerLayoutSettings.defaultStickCurve
    @AppStorage(ControllerLayoutSettings.stickGateKey) private var gateRaw = ControllerLayoutSettings.defaultStickGateRaw
    @AppStorage(TouchLabSettings.floatCameraKey) private var cameraRaw = TouchLabSettings.defaultFloatCamera
    @AppStorage(TouchLabSettings.adaptiveResetKey) private var adaptiveResets = 0
    @AppStorage(TouchLabSettings.racingAutoAccelerateKey) private var racingAuto = false
    @AppStorage(TouchLabSettings.racingTiltKey) private var racingTilt = false
    @AppStorage(TouchLabSettings.racingLockKey) private var racingLock = false
    @AppStorage(TouchLabSettings.racingLockHoldKey) private var racingLockHold = TouchLabSettings.defaultRacingLockHold
    @AppStorage("espressu.touchlab.racing.map.accelerate") private var mapAccelerate = PadButton.a.rawValue
    @AppStorage("espressu.touchlab.racing.map.brake") private var mapBrake = PadButton.b.rawValue
    @AppStorage("espressu.touchlab.racing.map.drift") private var mapDrift = PadButton.r.rawValue
    @AppStorage("espressu.touchlab.racing.map.item") private var mapItem = PadButton.l.rawValue
    @AppStorage("espressu.touchlab.racing.map.look") private var mapLook = PadButton.x.rawValue
    @AppStorage("espressu.touchlab.racing.map.skill") private var mapSkill = PadButton.up.rawValue
    @AppStorage(TouchLabSettings.aScaleKey) private var aScale = TouchLabSettings.defaultAScale
    @AppStorage(TouchLabSettings.racingPlacementsKey) private var racingPlacements = ""

    var body: some View {
        pad
            .ignoresSafeArea()
            .onAppear {
                TouchLabSettings.migrateLegacyLargeA()
                syncGamepadSize()
            }
            .onChange(of: screens) { _ in syncGamepadSize() }
    }

    private var pad: TouchPad {
        var pad = TouchPad(schemeID: schemeID,
                 output: CemuBridgePadOutput.shared,
                 touchscreenRect: screens.screens.touchscreenRect,
                 videoRects: screens.screens.videoRects,
                 scale: scale,
                 stickSpacing: stickSpacing,
                 shoulderOffset: CGFloat(ControllerLayoutSettings.effectiveShoulderOffset(shoulderOffset)),
                 opacity: opacity,
                 haptics: haptics,
                 revision: revision,
                 enabled: enabled,
                 stickTuning: StickTuning(deadzone: deadzone, curve: curve,
                                          gate: StickTuning.Gate(rawValue: gateRaw) ?? .octagon),
                 rectSpace: .window,
                 extraInsets: Insets(top: topInset),
                 makeScheme: makeScheme)
        pad.editing = editing && schemeID == RacingPad.schemeInfo.id
        return pad
    }

    private var revision: Int {
        var h = Hasher()
        h.combine(cameraRaw)
        h.combine(gameID)
        h.combine(adaptiveResets)
        h.combine(racingAuto)
        h.combine(racingTilt)
        h.combine(racingLock)
        h.combine(racingLockHold)
        for m in [mapAccelerate, mapBrake, mapDrift, mapItem, mapLook, mapSkill] { h.combine(m) }
        h.combine(aScale)
        h.combine(racingPlacements)
        return h.finalize()
    }

    private func syncGamepadSize() {
        CemuBridgePadOutput.shared.gamepadViewSize = screens.screens.touchscreenRect?.size ?? .zero
    }

    private func makeScheme(_ id: String) -> TouchScheme {
        switch id {
        case FloatPad.schemeInfo.id:
            return FloatPad(camera: FloatPad.Camera(rawValue: cameraRaw) ?? .stick, aScale: CGFloat(aScale))
        case AdaptivePad.schemeInfo.id:
            let key = TouchLabSettings.adaptiveKey(gameID: gameID)
            let pad = AdaptivePad(learned: AdaptivePad.decode(UserDefaults.standard.string(forKey: key) ?? "{}"),
                                aScale: CGFloat(aScale))
            pad.onLearned = { UserDefaults.standard.set(AdaptivePad.encode($0), forKey: key) }
            return pad
        case ZonePad.schemeInfo.id:
            return ZonePad(aScale: CGFloat(aScale))
        case RacingPad.schemeInfo.id:
            let pad = RacingPad(options: RacingPad.Options(autoAccelerate: racingAuto && !racingLock, tilt: racingTilt,
                                                           accelerateLock: racingLock,
                                                           mapping: TouchLabSettings.racingMapping(),
                                                           lockHold: racingLockHold),
                                aScale: CGFloat(aScale),
                                placements: RacingPad.decode(racingPlacements))
            pad.onPlacementsChanged = { placements in
                let encoded = RacingPad.encode(placements)
                // Defer so the view isn't rebuilt in the middle of handling the touch that ended.
                DispatchQueue.main.async {
                    if encoded.isEmpty {
                        UserDefaults.standard.removeObject(forKey: TouchLabSettings.racingPlacementsKey)
                    } else {
                        UserDefaults.standard.set(encoded, forKey: TouchLabSettings.racingPlacementsKey)
                    }
                }
            }
            return pad
        default:
            return SchemeCatalog.make(id, aScale: CGFloat(aScale))
        }
    }
}

struct TouchLabScreenState: Equatable {
    fileprivate var screens = TouchLabScreens(frames: [:])
    init() {}
}

extension View {
    func touchLabTVScreen() -> some View { touchLabScreenFrame(.tv) }

    func touchLabGamePadScreen() -> some View { touchLabScreenFrame(.gamepad) }

    func trackTouchLabScreens(_ screens: Binding<TouchLabScreenState>,
                              imageIsAspectFit: @escaping () -> Bool) -> some View {
        onPreferenceChange(TouchLabScreenFramesKey.self) { frames in
            var next = TouchLabScreenState()
            next.screens = TouchLabScreens(frames: frames, imageIsAspectFit: imageIsAspectFit())
            if next != screens.wrappedValue { screens.wrappedValue = next }
        }
    }
}
