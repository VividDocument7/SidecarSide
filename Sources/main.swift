import AppKit
import CoreGraphics
import ServiceManagement

enum Side: String {
    case left, right
}

enum Prefs {
    private static let d = UserDefaults.standard

    /// Last side the user picked (used as the default button, or applied silently).
    static var side: Side? {
        get { d.string(forKey: "side").flatMap(Side.init) }
        set { d.set(newValue?.rawValue, forKey: "side") }
    }

    /// When true, prompt on every connect. When false, apply `side` silently.
    static var askEachTime: Bool {
        get { d.object(forKey: "askEachTime") as? Bool ?? true }
        set { d.set(newValue, forKey: "askEachTime") }
    }
}

// MARK: - Display helpers

enum Displays {
    static func name(of id: CGDirectDisplayID) -> String {
        NSScreen.screens.first { screenID($0) == id }?.localizedName ?? ""
    }

    static func screenID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Sidecar displays report the iPad's name (e.g. "Oliver's iPad") or "Sidecar Display".
    static func isSidecar(_ id: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsBuiltin(id) == 0 else { return false }
        let n = name(of: id).lowercased()
        return n.contains("ipad") || n.contains("sidecar")
    }

    static func connectedSidecars() -> [CGDirectDisplayID] {
        NSScreen.screens.compactMap(screenID).filter(isSidecar)
    }

    /// Places `display` flush against the left or right edge of the main display, vertically centered.
    @discardableResult
    static func place(_ display: CGDirectDisplayID, on side: Side) -> Bool {
        let main = CGMainDisplayID()
        guard display != main, CGDisplayIsInMirrorSet(display) == 0 else { return false }

        let m = CGDisplayBounds(main)
        let p = CGDisplayBounds(display)
        let x = side == .right ? m.maxX : m.minX - p.width
        let y = m.midY - p.height / 2

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayOrigin(config, display, Int32(x.rounded()), Int32(y.rounded()))
        let result = CGCompleteDisplayConfiguration(config, .permanently)
        NSLog("SidecarSide: placed \"\(name(of: display))\" on \(side.rawValue) -> \(result.rawValue)")
        return result == .success
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var handled = Set<CGDirectDisplayID>()
    private let picker = SidePicker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--preview` shows the picker without touching any displays (no menu bar item).
        if CommandLine.arguments.contains("--preview") {
            picker.show(preselect: Prefs.side ?? .right) { side, remember in
                NSLog("SidecarSide preview: \(side?.rawValue ?? "dismissed"), remember=\(remember)")
            }
            if let path = ProcessInfo.processInfo.environment["SIDECARSIDE_SNAPSHOT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.picker.snapshot(to: path) }
            }
            return
        }

        // Only one copy should ever own the menu bar item.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current && !$0.isTerminated }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "ipad.landscape", accessibilityDescription: "SidecarSide")
        enableLaunchAtLoginOnFirstRun()
        rebuildMenu()

        let callback: CGDisplayReconfigurationCallBack = { display, flags, userInfo in
            guard let userInfo else { return }
            let app = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            if flags.contains(.addFlag) {
                // Give the system a moment to settle the new display's mode and bounds.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { app.displayAdded(display) }
            } else if flags.contains(.removeFlag) {
                DispatchQueue.main.async { app.handled.remove(display) }
            }
        }
        CGDisplayRegisterReconfigurationCallback(callback, Unmanaged.passUnretained(self).toOpaque())

        // Already connected at launch: treat as handled so we don't prompt, but honor a silent preference.
        for id in Displays.connectedSidecars() {
            handled.insert(id)
            if !Prefs.askEachTime, let side = Prefs.side { Displays.place(id, on: side) }
        }
    }

    private func displayAdded(_ id: CGDirectDisplayID) {
        NSLog("SidecarSide: display added \(id) \"\(Displays.name(of: id))\"")
        guard Displays.isSidecar(id), !handled.contains(id) else { return }
        handled.insert(id)

        if !Prefs.askEachTime, let side = Prefs.side {
            Displays.place(id, on: side)
        } else {
            prompt(for: id)
        }
    }

    private func prompt(for id: CGDirectDisplayID) {
        picker.show(preselect: Prefs.side ?? .right) { [weak self] side, remember in
            guard let self, let side else { return }
            Prefs.side = side
            if remember { Prefs.askEachTime = false }
            self.rebuildMenu()
            Displays.place(id, on: side)
        }
    }

    // MARK: Menu

    /// Behave like a built-in feature: once installed in /Applications, start at login by default.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "didSetUpLoginItem"
        guard !UserDefaults.standard.bool(forKey: key),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let left = NSMenuItem(title: "iPad on Left", action: #selector(chooseLeft), keyEquivalent: "")
        left.state = Prefs.side == .left ? .on : .off
        let right = NSMenuItem(title: "iPad on Right", action: #selector(chooseRight), keyEquivalent: "")
        right.state = Prefs.side == .right ? .on : .off
        menu.addItem(left)
        menu.addItem(right)
        menu.addItem(.separator())

        let ask = NSMenuItem(title: "Ask Each Time iPad Connects", action: #selector(toggleAsk), keyEquivalent: "")
        ask.state = Prefs.askEachTime ? .on : .off
        menu.addItem(ask)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "About SidecarSide", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit SidecarSide", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func chooseLeft() { choose(.left) }
    @objc private func chooseRight() { choose(.right) }

    /// Saves the side and moves any currently connected iPad there right away.
    private func choose(_ side: Side) {
        Prefs.side = side
        Displays.connectedSidecars().forEach { Displays.place($0, on: side) }
        rebuildMenu()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Places your Sidecar iPad on the correct side of your Mac.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11),
                                                      .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }

    @objc private func toggleAsk() {
        Prefs.askEachTime.toggle()
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("SidecarSide: launch-at-login change failed: \(error)")
        }
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
