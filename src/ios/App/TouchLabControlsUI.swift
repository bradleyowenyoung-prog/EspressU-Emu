// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import TouchLabCore

func touchLabStyleLabel(_ id: String) -> String {
    let isDefault = id == TouchLabSettings.defaultScheme
    if id.isEmpty { return isDefault ? "EspressU (default)" : "EspressU (classic)" }
    let name = TouchLabSettings.styles.first { $0.id == id }?.name ?? id
    return isDefault ? name + " (default)" : name
}

private var touchLabStyleIDs: [String] { [""] + TouchLabSettings.styles.map(\.id) }

struct TouchLabStyleSettingsRows: View {
    @AppStorage(TouchLabSettings.schemeKey) private var scheme = TouchLabSettings.defaultScheme
    @AppStorage(TouchLabSettings.floatCameraKey) private var floatCamera = TouchLabSettings.defaultFloatCamera
    @AppStorage(TouchLabSettings.racingAutoAccelerateKey) private var racingAuto = false
    @AppStorage(TouchLabSettings.racingTiltKey) private var racingTilt = false
    @AppStorage(TouchLabSettings.racingLockKey) private var racingLock = false
    @AppStorage(TouchLabSettings.racingLockHoldKey) private var racingLockHold = TouchLabSettings.defaultRacingLockHold
    @AppStorage(TouchLabSettings.aScaleKey) private var aScale = TouchLabSettings.defaultAScale
    @State private var showingAdaptiveReset = false

    var body: some View {
        let selection = Binding<String>(
            get: { scheme },
            set: { newValue in scheme = newValue }
        )

        Group {
            Picker(selection: selection) {
                ForEach(touchLabStyleIDs, id: \.self) { id in
                    Text(touchLabStyleLabel(id)).tag(id)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Control style")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if TouchLabSettings.isTouchLab(scheme) {

                if scheme == TouchLabSettings.floatStyleID {
                    Picker("Camera", selection: $floatCamera) {
                        ForEach(TouchLabSettings.cameraOptions, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("A button size")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Button(action: { aScale = TouchLabSettings.defaultAScale }) {
                            Text("\(Int((aScale * 100).rounded()))%")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset A button size")
                        .accessibilityValue("\(Int((aScale * 100).rounded())) percent")
                    }
                    HStack(spacing: 8) {
                        Text("100%").font(.system(size: 12)).foregroundColor(.secondary)
                        Slider(value: $aScale, in: TouchLabSettings.aScaleRange, step: 0.01)
                            .tint(EspressUTheme.pixelBlue)
                            .accessibilityLabel("A button size")
                        Text("180%").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    Text("Makes A bigger and easier to hit. The buttons around it shrink a little. Tap the percentage to reset.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                if scheme == TouchLabSettings.racingStyleID {
                    Toggle(isOn: $racingAuto) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-accelerate (always on)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("Holds A all the time, even in menus. Touching Brake lets it go. Turned off by Hold Gas to lock.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(EspressUTheme.pixelBlue)
                    .onChange(of: racingAuto) { on in if on { racingLock = false } }

                    Toggle(isOn: $racingLock) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hold Gas to lock accelerate")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("Hold Gas, then let go: it stays held (\u{1F512}) so your thumb is free for Drift and Item. Tap Gas to release. Brake still works while locked.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(EspressUTheme.pixelBlue)

                    .onChange(of: racingLock) { on in if on { racingAuto = false } }

                    if racingLock {
                        RacingLockHoldRow(value: $racingLockHold)
                    }

                    RacingMappingRows()

                    Toggle(isOn: $racingTilt) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tilt steering")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("Turn the device like a wheel. Tap C at the top to set straight ahead.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(EspressUTheme.pixelBlue)
                }

                if scheme == TouchLabSettings.adaptiveStyleID {
                    Button(role: .destructive, action: { showingAdaptiveReset = true }) {
                        DestructiveSettingsLabel(title: "Reset learned layouts", systemImage: "arrow.uturn.backward")
                    }
                }

                Text(scheme == TouchLabSettings.racingStyleID
                     ? "To move or resize Racing buttons, open the controls panel in game (Move controls) and drag them."
                     : "These styles don't support dragging individual buttons. Size, opacity, haptics and the stick options below apply to them.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { TouchLabSettings.migrateLegacyLargeA() }
        .confirmationDialog("Reset learned layouts?", isPresented: $showingAdaptiveReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { TouchLabSettings.resetAdaptiveAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Adaptive forgets where your thumbs land, in every game, and starts from its home positions again.")
        }
    }

    private var summary: String {
        TouchLabSettings.isTouchLab(scheme)
            ? TouchLabSettings.summary(scheme)
            : "EspressU's measured GamePad layout, which you can also drag around."
    }
}

struct TouchLabStylePicker: View {
    @AppStorage(TouchLabSettings.schemeKey) private var scheme = TouchLabSettings.defaultScheme

    var body: some View {
        Picker("Control style", selection: $scheme) {
            ForEach(touchLabStyleIDs, id: \.self) { id in
                Text(id.isEmpty ? "EspressU" : (TouchLabSettings.styles.first { $0.id == id }?.name ?? id))
                    .tag(id)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct TouchLabLayoutPanel: View {
    let gameID: String?
    let onDone: () -> Void

    @AppStorage(TouchLabSettings.schemeKey) private var scheme = TouchLabSettings.defaultScheme
    @AppStorage(TouchLabSettings.floatCameraKey) private var floatCamera = TouchLabSettings.defaultFloatCamera
    @AppStorage(ControllerLayoutSettings.scaleKey) private var controlScale = ControllerLayoutSettings.defaultScale
    @AppStorage(ControllerLayoutSettings.opacityKey) private var controlOpacity = ControllerLayoutSettings.defaultOpacity
    @AppStorage(ControllerLayoutSettings.stickSpacingKey) private var stickSpacing = ControllerLayoutSettings.defaultStickSpacing
    @AppStorage(ControllerLayoutSettings.shoulderOffsetKey) private var shoulderOffset = ControllerLayoutSettings.defaultShoulderOffset

    @AppStorage(TouchLabSettings.racingAutoAccelerateKey) private var racingAuto = false
    @AppStorage(TouchLabSettings.racingLockKey) private var racingLock = false
    @AppStorage(TouchLabSettings.racingLockHoldKey) private var racingLockHold = TouchLabSettings.defaultRacingLockHold
    @AppStorage(TouchLabSettings.racingPlacementsKey) private var racingPlacements = ""
    @State private var collapsed = false
    @State private var confirmingPlacementReset = false

    private var isAdaptive: Bool { scheme == TouchLabSettings.adaptiveStyleID }
    private var isRacing: Bool { scheme == TouchLabSettings.racingStyleID }

    var body: some View {
        if collapsed && isRacing {
            // Small bar so the whole screen is free for dragging buttons.
            VStack {
                HStack(spacing: 10) {
                    Button("Show settings") { collapsed = false }
                        .buttonStyle(EspressUSecondaryButtonStyle())
                    Button("Done", action: onDone)
                        .buttonStyle(EspressUSecondaryButtonStyle())
                }
                .padding(8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        } else {
            card
        }
    }

    private var card: some View {
        LayoutPanelCard(rows: { rows }, footer: {
            LayoutPanelFooter(
                resetMessage: isAdaptive
                    ? "Size, opacity, stick spacing and shoulder height go back to how EspressU ships in every game, and Adaptive forgets where your thumbs land in this game only."
                    : "Size, opacity, stick spacing and shoulder height go back to how EspressU ships, in every game.",
                onReset: resetToDefault,
                onDone: onDone)
        })
    }

    @ViewBuilder private var rows: some View {
        TouchLabStylePicker()

        if isRacing {
            PanelCaption(text: "Drag a button to move it. Drag its blue corner dot, or pinch, to resize. Double-tap a button to put it back. Nothing here reaches the game.")

            HStack(spacing: 10) {
                Button("Hide panel") { withAnimation(.easeInOut(duration: 0.15)) { collapsed = true } }
                    .buttonStyle(EspressUSecondaryButtonStyle())
                Button("Reset positions") { confirmingPlacementReset = true }
                    .buttonStyle(EspressUSecondaryButtonStyle())
                    .disabled(racingPlacements.isEmpty)
                    .confirmationDialog("Put every Racing button back?", isPresented: $confirmingPlacementReset,
                                        titleVisibility: .visible) {
                        Button("Reset positions", role: .destructive) { TouchLabSettings.resetRacingPlacements() }
                        Button("Cancel", role: .cancel) { }
                    }
            }

            PanelToggle(title: "Hold Gas to lock accelerate", isOn: $racingLock)
                .onChange(of: racingLock) { on in if on { racingAuto = false } }
            if racingLock {
                PanelCaption(text: "Hold Gas, then let go: it stays pressed (\u{1F512}) so your thumb is free for Drift, Item and Skill. Tap Gas to let go of it, e.g. for menus. Brake still works.",
                             prominent: false)
                PanelLockHoldRow(value: $racingLockHold)
            }
            PanelToggle(title: "Auto-accelerate (always on)", isOn: $racingAuto)
                .onChange(of: racingAuto) { on in if on { racingLock = false } }
        } else {
            PanelCaption(text: "\(TouchLabSettings.summary(scheme)) These styles don't support dragging individual buttons. Nothing here reaches the game.")
        }

        PanelSliderRow("Button size", leadingIcon: "minus.magnifyingglass", trailingIcon: "plus.magnifyingglass",
                       value: $controlScale,
                       range: ControllerLayoutSettings.minScale...ControllerLayoutSettings.maxScale)

        PanelSliderRow("Opacity", leadingIcon: "circle.lefthalf.filled", trailingIcon: "circle.fill",
                       value: $controlOpacity, range: 0.2...1.0)

        if TouchLabSettings.hasFixedSticks(scheme) {
            PanelSliderRow("Stick spacing",
                           leadingIcon: "arrow.right.and.line.vertical.and.arrow.left",
                           trailingIcon: "arrow.left.and.line.vertical.and.arrow.right",
                           value: $stickSpacing,
                           range: ControllerLayoutSettings.minStickSpacing...ControllerLayoutSettings.maxStickSpacing,
                           step: ControllerLayoutSettings.stickSpacingStep,
                           spokenValue: ControllerLayoutSettings.stickSpacingLabel(stickSpacing))
        }

        if ControllerLayoutSettings.supportsShoulderOffset && TouchLabSettings.hasMovableShoulders(scheme) {
            PanelSliderRow("Shoulder button height", title: "L/R", leadingIcon: "arrow.up.and.down",
                           value: $shoulderOffset,
                           range: ControllerLayoutSettings.shoulderOffsetRange(touchLab: true),
                           step: ControllerLayoutSettings.shoulderOffsetStep,
                           spokenValue: ControllerLayoutSettings.shoulderOffsetLabel(max(0, shoulderOffset)))
        }

        if scheme == TouchLabSettings.floatStyleID {
            Picker("Camera", selection: $floatCamera) {
                ForEach(TouchLabSettings.cameraOptions, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
        }

        PanelCaption(text: isAdaptive
                     ? "These settings apply to every game, except that Adaptive remembers where your thumbs land separately for each game."
                     : "These settings apply to every game.",
                     prominent: false)
    }

    private func resetToDefault() {
        controlScale = ControllerLayoutSettings.defaultScale
        controlOpacity = ControllerLayoutSettings.defaultOpacity
        stickSpacing = ControllerLayoutSettings.defaultStickSpacing
        shoulderOffset = ControllerLayoutSettings.defaultShoulderOffset
        if isAdaptive {
            TouchLabSettings.resetAdaptive(gameID: gameID)
        }
    }
}


struct RacingLockHoldRow: View {
    @Binding var value: Double
    @State private var text = ""
    @FocusState private var editing: Bool

    private var range: ClosedRange<Double> { TouchLabSettings.racingLockHoldRange }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hold time to lock")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                TextField("0.60", text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.done)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .font(.system(size: 14, design: .monospaced))
                    .focused($editing)
                    .onSubmit(commit)
                    .accessibilityLabel("Hold time in seconds")
                Text("s").font(.system(size: 13)).foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                Text(String(format: "%.1fs", range.lowerBound)).font(.system(size: 12)).foregroundColor(.secondary)
                Slider(value: $value, in: range, step: 0.05)
                    .tint(EspressUTheme.pixelBlue)
                    .accessibilityLabel("Hold time to lock")
                    .accessibilityValue(String(format: "%.2f seconds", value))
                Text(String(format: "%.1fs", range.upperBound)).font(.system(size: 12)).foregroundColor(.secondary)
            }
            Text("How long you hold Gas before letting go locks it. Shorter locks sooner; longer avoids locking by accident.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { text = format(value) }
        .onChange(of: value) { v in if !editing { text = format(v) } }
        .onChange(of: editing) { focused in if !focused { commit() } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editing = false }
            }
        }
    }

    private func format(_ v: Double) -> String { String(format: "%.2f", v) }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(cleaned), v.isFinite {
            value = min(max((v * 100).rounded() / 100, range.lowerBound), range.upperBound)
        }
        text = format(value)
    }
}

struct RacingMappingRows: View {
    @AppStorage("espressu.touchlab.racing.map.accelerate") private var accelerate = PadButton.a.rawValue
    @AppStorage("espressu.touchlab.racing.map.brake") private var brake = PadButton.b.rawValue
    @AppStorage("espressu.touchlab.racing.map.drift") private var drift = PadButton.r.rawValue
    @AppStorage("espressu.touchlab.racing.map.item") private var item = PadButton.l.rawValue
    @AppStorage("espressu.touchlab.racing.map.look") private var look = PadButton.x.rawValue
    @AppStorage("espressu.touchlab.racing.map.skill") private var skill = PadButton.up.rawValue

    private func binding(_ id: String) -> Binding<Int> {
        switch id {
        case "accelerate": return $accelerate
        case "brake": return $brake
        case "drift": return $drift
        case "item": return $item
        case "look": return $look
        default: return $skill
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Button mapping")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("Pick which Wii U button each racing control sends. Steering is the left stick; \u{2212}, + and Home stay at the top for menus.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(TouchLabSettings.racingActions) { action in
            Picker(selection: binding(action.id)) {
                ForEach(TouchLabSettings.racingMappableButtons, id: \.rawValue) { b in
                    Text(TouchLabSettings.buttonName(b)).tag(b.rawValue)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title).font(.system(size: 15, design: .rounded))
                    Text(action.detail).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
        Button(action: {
            accelerate = PadButton.a.rawValue; brake = PadButton.b.rawValue; drift = PadButton.r.rawValue
            item = PadButton.l.rawValue; look = PadButton.x.rawValue; skill = PadButton.up.rawValue
        }) {
            Text("Reset to Mario Kart 8 defaults")
                .font(.system(size: 14))
        }
    }
}


/// Hold-time slider with a typed value, styled for the dark in-game panel.
struct PanelLockHoldRow: View {
    @Binding var value: Double
    @State private var text = ""
    @FocusState private var editing: Bool

    private var range: ClosedRange<Double> { TouchLabSettings.racingLockHoldRange }

    var body: some View {
        HStack(spacing: 8) {
            Text("Hold")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
            Slider(value: $value, in: range, step: 0.05)
                .tint(EspressUTheme.pixelBlue)
                .accessibilityLabel("Hold time to lock")
                .accessibilityValue(String(format: "%.2f seconds", value))
            TextField("0.60", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(.done)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(Color.white.opacity(0.12))
                .cornerRadius(6)
                .focused($editing)
                .onSubmit { editing = false; commit() }
                .accessibilityLabel("Hold time in seconds")
            Text("s")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
        }
        .onAppear { text = format(value) }
        .onChange(of: value) { v in if !editing { text = format(v) } }
        .onChange(of: editing) { focused in if !focused { commit() } }
    }

    private func format(_ v: Double) -> String { String(format: "%.2f", v) }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(cleaned), v.isFinite {
            value = min(max((v * 100).rounded() / 100, range.lowerBound), range.upperBound)
        }
        text = format(value)
    }
}
