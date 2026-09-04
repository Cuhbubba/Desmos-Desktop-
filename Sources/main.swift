import Cocoa
import WebKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Theme

enum Theme {
    static let text       = NSColor(calibratedWhite: 0.93, alpha: 1)
    static let secondary  = NSColor(calibratedWhite: 0.70, alpha: 1)
    static let tertiary   = NSColor(calibratedWhite: 0.50, alpha: 1)
    static let icon       = NSColor(calibratedWhite: 0.80, alpha: 1)
    static let hairline   = NSColor(calibratedWhite: 1.0, alpha: 0.10)
    static let border     = NSColor(calibratedWhite: 1.0, alpha: 0.14)
    static let fieldFill  = NSColor(calibratedWhite: 1.0, alpha: 0.08)
    static let fieldStroke = NSColor(calibratedWhite: 1.0, alpha: 0.22)
    static let webBackground = NSColor.white
}

// MARK: - Shortcut model

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var label: String          // e.g. "⌥⇧D" — shown in the settings UI
    var keyEquivalent: String  // single character for the menu item, or "" if none

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_D),
                                    carbonModifiers: UInt32(optionKey | shiftKey),
                                    label: "⌥⇧D", keyEquivalent: "d")

    private static let defaultsKey = "toggleShortcut"

    static func load() -> Shortcut {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let s = try? JSONDecoder().decode(Shortcut.self, from: data) { return s }
        return .default
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Shortcut.defaultsKey)
        }
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey)     != 0 { f.insert(.command) }
        if carbonModifiers & UInt32(optionKey)  != 0 { f.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if carbonModifiers & UInt32(shiftKey)   != 0 { f.insert(.shift) }
        return f
    }

    /// Builds a shortcut from a key event, or nil if the combo isn't usable as a global hotkey.
    static func from(event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)
        let isFunctionKey = functionKeyNames[code] != nil
        // Require ⌘/⌥/⌃ unless it's an F-key, so a plain letter can't hijack typing everywhere.
        guard isFunctionKey || !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }

        var carbon: UInt32 = 0
        var mods = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); mods += "⌃" }
        if flags.contains(.option)  { carbon |= UInt32(optionKey);  mods += "⌥" }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey);   mods += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey);     mods += "⌘" }

        let keyName: String
        let keyEquivalent: String
        if let fn = functionKeyNames[code] {
            keyName = fn; keyEquivalent = ""
        } else if let special = specialKeyNames[code] {
            keyName = special; keyEquivalent = ""
        } else {
            let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
            guard let c = chars.first, !c.isWhitespace || code == kVK_Space else { return nil }
            keyName = String(c).uppercased(); keyEquivalent = String(c)
        }
        return Shortcut(keyCode: UInt32(code), carbonModifiers: carbon,
                        label: mods + keyName, keyEquivalent: keyEquivalent)
    }

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]
    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]
}

// MARK: - Shortcut recorder control

/// Click it, press a key combo, done. Esc cancels.
final class ShortcutRecorder: NSView {
    var shortcut: Shortcut { didSet { needsDisplay = true } }
    var onChange: ((Shortcut) -> Void)?

    private var recording = false { didSet { needsDisplay = true } }
    private var monitor: Any?

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
        toolTip = "Click, then press the new shortcut"
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 28) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : Theme.fieldFill).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : Theme.fieldStroke).setStroke()
        path.lineWidth = recording ? 1.5 : 1
        path.stroke()

        let text = recording ? "Press shortcut…" : shortcut.label
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: recording ? .regular : .medium),
            .foregroundColor: recording ? Theme.secondary : Theme.text,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                  withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.recording else { return event }
            if Int(event.keyCode) == kVK_Escape { self.stopRecording(); return nil }
            if let s = Shortcut.from(event: event) {
                self.shortcut = s
                self.stopRecording()
                self.onChange?(s)
            } else {
                NSSound.beep()   // needs ⌘/⌥/⌃ (or an F-key)
            }
            return nil
        }
    }

    func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
    }

    override func resignFirstResponder() -> Bool { stopRecording(); return true }
}

// MARK: - Window pieces

/// Non-activating floating panel. `canBecomeKey` lets it receive typing
/// while some other app stays the active app (Spotlight/Alfred-style).
final class CalculatorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// First click lands inside the web content (e.g. a specific expression box)
/// instead of only focusing the window.
final class CalcWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Bluebook-style title bar: white, hairline bottom border, drags the window.
final class HeaderView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func draw(_ dirtyRect: NSRect) {
        Theme.hairline.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    static var shared: AppDelegate!

    private var panel: CalculatorPanel!
    private var webView: CalcWebView!
    private var statusItem: NSStatusItem!
    private var toggleMenuItem: NSMenuItem!
    private var hotKeyRef: EventHotKeyRef?
    private var expandButton: NSButton!
    private var modeControl: NSSegmentedControl!
    private var expanded = false

    private var settingsPanel: CalculatorPanel?
    private var recorder: ShortcutRecorder?
    private var loginCheckbox: NSButton?
    private var shortcut = Shortcut.load()

    private let headerHeight: CGFloat = 44
    private let compactSize  = NSSize(width: 660, height: 540)
    private let expandedSize = NSSize(width: 1000, height: 740)
    private let settingsSize = NSSize(width: 280, height: 172)

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
        buildPanel()
        buildStatusItem()
        installHotKeyHandler()
        registerHotKey(shortcut)
        if !launchedAsLoginItem { showPanel() }   // stay hidden when macOS auto-launches us
    }

    /// Double-clicking the app in Finder while it's already running brings the calculator back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    /// True when launchd started us as a login item rather than the user opening the app.
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass, event.eventID == kAEOpenApplication,
              let prop = event.paramDescriptor(forKeyword: keyAEPropData) else { return false }
        return prop.enumCodeValue == keyAELaunchedAsLogInItem
    }

    // MARK: Launch at login (SMAppService, macOS 13+)

    private var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch-at-login change failed: \(error)")
        }
        sender.state = launchAtLogin ? .on : .off
        if sender.state == .off && SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    // MARK: Panel

    private func buildPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - compactSize.width - 24,
                             y: screen.maxY - compactSize.height - 24)

        panel = CalculatorPanel(contentRect: NSRect(origin: origin, size: compactSize),
                                styleMask: [.borderless, .nonactivatingPanel, .resizable],
                                backing: .buffered, defer: false)
        panel.level = .floating
        // canJoinAllSpaces + fullScreenAuxiliary = shows on top of fullscreen apps too.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = NSSize(width: 440, height: 380)
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.title = "Desmos Desktop"
        panel.appearance = NSAppearance(named: .darkAqua)

        let container = roundedContainer(size: compactSize)
        panel.contentView = container

        // Header
        let header = HeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        let title = NSTextField(labelWithString: "Desmos Desktop")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        title.textColor = Theme.text
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)

        // Graphing / Scientific switcher
        modeControl = NSSegmentedControl(labels: ["Graphing", "Scientific"],
                                         trackingMode: .selectOne,
                                         target: self, action: #selector(modeChanged))
        modeControl.selectedSegment = 0
        modeControl.segmentStyle = .rounded
        modeControl.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(modeControl)

        let settingsButton = headerButton("gearshape", size: 11, tip: "Settings", action: #selector(toggleSettings))
        expandButton = headerButton("arrow.up.left.and.arrow.down.right", tip: "Expand", action: #selector(toggleExpand))
        let closeButton = headerButton("xmark", tip: "Close", action: #selector(hidePanel))
        header.addSubview(settingsButton)
        header.addSubview(expandButton)
        header.addSubview(closeButton)

        // Desmos web view
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = CalcWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        let webBackdrop = NSView()
        webBackdrop.wantsLayer = true
        webBackdrop.layer?.backgroundColor = Theme.webBackground.cgColor
        webBackdrop.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webBackdrop)
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: headerHeight),

            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            modeControl.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            modeControl.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            expandButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            expandButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: 30),
            expandButton.heightAnchor.constraint(equalToConstant: 30),

            settingsButton.trailingAnchor.constraint(equalTo: expandButton.leadingAnchor, constant: -2),
            settingsButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 22),
            settingsButton.heightAnchor.constraint(equalToConstant: 22),

            webBackdrop.topAnchor.constraint(equalTo: webView.topAnchor),
            webBackdrop.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            webBackdrop.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            webBackdrop.bottomAnchor.constraint(equalTo: webView.bottomAnchor),

            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(mainPanelChanged),
                                               name: NSWindow.didResizeNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(mainPanelChanged),
                                               name: NSWindow.didMoveNotification, object: panel)

        loadCalculator()
    }

    /// Slightly translucent dark HUD surface with rounded corners and a faint edge.
    private func roundedContainer(size: NSSize, tint: CGFloat = 0) -> NSView {
        let v = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        v.layer?.masksToBounds = true
        v.layer?.borderWidth = 1
        v.layer?.borderColor = Theme.border.cgColor
        if tint > 0 {   // darken the blur so text stays readable over busy backgrounds
            let shade = NSView(frame: v.bounds)
            shade.autoresizingMask = [.width, .height]
            shade.wantsLayer = true
            shade.layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: tint).cgColor
            v.addSubview(shade)
        }
        return v
    }

    private func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: name) ?? NSImage()
        return img.withSymbolConfiguration(.init(pointSize: size, weight: weight)) ?? img
    }

    private func headerButton(_ symbolName: String, size: CGFloat = 13, tip: String, action: Selector) -> NSButton {
        let b = NSButton(image: symbol(symbolName, size: size, weight: .semibold), target: self, action: action)
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.contentTintColor = Theme.icon
        b.toolTip = tip
        b.focusRingType = .none
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func loadCalculator() {
        if let url = Bundle.main.url(forResource: "calculator", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: URL(string: "https://www.desmos.com/calculator")!))
        }
    }

    // MARK: Settings panel

    @objc func toggleSettings() {
        if let s = settingsPanel, s.isVisible { closeSettings(); return }
        if settingsPanel == nil { buildSettingsPanel() }
        loginCheckbox?.state = launchAtLogin ? .on : .off
        positionSettings()
        panel.addChildWindow(settingsPanel!, ordered: .above)
        settingsPanel!.orderFrontRegardless()
        settingsPanel!.makeKey()
    }

    private func closeSettings() {
        guard let s = settingsPanel else { return }
        recorder?.stopRecording()
        panel.removeChildWindow(s)
        s.orderOut(nil)
    }

    private func buildSettingsPanel() {
        let s = CalculatorPanel(contentRect: NSRect(origin: .zero, size: settingsSize),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        s.level = panel.level
        s.collectionBehavior = panel.collectionBehavior
        s.isFloatingPanel = true
        s.hidesOnDeactivate = false
        s.isOpaque = false
        s.backgroundColor = .clear
        s.hasShadow = true
        s.isReleasedWhenClosed = false
        s.appearance = NSAppearance(named: .darkAqua)

        let container = roundedContainer(size: settingsSize, tint: 0.55)
        s.contentView = container

        let title = NSTextField(labelWithString: "Settings")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = Theme.text
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        let close = headerButton("xmark", size: 10, tip: "Close", action: #selector(toggleSettings))
        container.addSubview(close)

        let label = NSTextField(labelWithString: "Show / hide Desmos")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = Theme.secondary
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let rec = ShortcutRecorder(shortcut: shortcut)
        rec.translatesAutoresizingMaskIntoConstraints = false
        rec.onChange = { [weak self] new in self?.applyShortcut(new) }
        container.addSubview(rec)
        recorder = rec

        let reset = NSButton(title: "Reset", target: self, action: #selector(resetShortcut))
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        reset.focusRingType = .none
        reset.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        reset.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(reset)

        let hint = NSTextField(wrappingLabelWithString: "Click the box, then press a key combo (needs ⌘, ⌥ or ⌃). Esc cancels.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = Theme.tertiary
        hint.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hint)

        let loginBox = NSButton(checkboxWithTitle: "Launch at login (keeps the shortcut working)",
                                target: self, action: #selector(launchAtLoginToggled(_:)))
        loginBox.font = NSFont.systemFont(ofSize: 12)
        loginBox.contentTintColor = Theme.text
        loginBox.focusRingType = .none
        loginBox.state = launchAtLogin ? .on : .off
        loginBox.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(loginBox)
        loginCheckbox = loginBox

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),

            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            close.widthAnchor.constraint(equalToConstant: 20),
            close.heightAnchor.constraint(equalToConstant: 20),

            label.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            rec.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            rec.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            rec.widthAnchor.constraint(equalToConstant: 150),
            rec.heightAnchor.constraint(equalToConstant: 28),

            reset.centerYAnchor.constraint(equalTo: rec.centerYAnchor),
            reset.leadingAnchor.constraint(equalTo: rec.trailingAnchor, constant: 8),

            hint.topAnchor.constraint(equalTo: rec.bottomAnchor, constant: 8),
            hint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            loginBox.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            loginBox.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            loginBox.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),
        ])

        settingsPanel = s
    }

    /// Tucks the settings panel just under the header, inset from the calculator's right edge
    /// so it always sits fully inside the main window.
    private func positionSettings() {
        guard let s = settingsPanel else { return }
        let f = panel.frame
        let inset: CGFloat = 36
        var x = f.maxX - settingsSize.width - inset
        x = max(x, f.minX + inset)                       // never poke out the left side on narrow windows
        let y = f.maxY - headerHeight - 8 - settingsSize.height
        s.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func mainPanelChanged() {
        if settingsPanel?.isVisible == true { positionSettings() }
    }

    @objc func resetShortcut() {
        recorder?.shortcut = .default
        applyShortcut(.default)
    }

    private func applyShortcut(_ new: Shortcut) {
        shortcut = new
        shortcut.save()
        registerHotKey(new)
        toggleMenuItem.keyEquivalent = new.keyEquivalent
        toggleMenuItem.keyEquivalentModifierMask = new.cocoaModifiers
    }

    // MARK: Actions

    @objc func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    @objc func showPanel() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    @objc func hidePanel() {
        closeSettings()
        panel.orderOut(nil)
    }

    @objc func toggleExpand() {
        expanded.toggle()
        let size = expanded ? expandedSize : compactSize
        var frame = panel.frame
        // keep the top-right corner anchored
        frame.origin.x = frame.maxX - size.width
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        if let screen = panel.screen?.visibleFrame {
            frame.origin.x = max(screen.minX, min(frame.origin.x, screen.maxX - size.width))
            frame.origin.y = max(screen.minY, min(frame.origin.y, screen.maxY - size.height))
        }
        panel.setFrame(frame, display: true, animate: true)
        expandButton.image = symbol(expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                    size: 13, weight: .semibold)
        expandButton.toolTip = expanded ? "Collapse" : "Expand"
    }

    @objc func modeChanged() {
        let mode = modeControl.selectedSegment == 0 ? "graphing" : "scientific"
        webView.evaluateJavaScript("window.showMode && showMode('\(mode)')", completionHandler: nil)
        panel.makeKey()
    }

    @objc func resetCalculator() {
        loadCalculator()
        modeControl.selectedSegment = 0
    }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = symbol("function", size: 14, weight: .medium)
        let menu = NSMenu()
        toggleMenuItem = NSMenuItem(title: "Show / Hide Desmos", action: #selector(togglePanel),
                                    keyEquivalent: shortcut.keyEquivalent)
        toggleMenuItem.keyEquivalentModifierMask = shortcut.cocoaModifiers
        menu.addItem(toggleMenuItem)
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reload Desmos", action: #selector(resetCalculator), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func openSettingsFromMenu() {
        showPanel()
        if settingsPanel?.isVisible != true { toggleSettings() }
    }

    // MARK: Global hotkey via Carbon — no Accessibility prompt needed

    private func installHotKeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { AppDelegate.shared.togglePanel() }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    private func registerHotKey(_ s: Shortcut) {
        if let old = hotKeyRef { UnregisterEventHotKey(old); hotKeyRef = nil }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4444_534B) /* "DDSK" */, id: 1)
        let status = RegisterEventHotKey(s.keyCode, s.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("Failed to register hotkey \(s.label) (status \(status))")
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Calculator failed to load: \(error.localizedDescription)")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
