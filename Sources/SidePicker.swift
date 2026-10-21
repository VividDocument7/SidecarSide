import AppKit

/// A small floating glass panel, styled like a system HUD, that asks which side the iPad is on.
/// Keyboard: ← / → pick a side, Return picks the highlighted one, Esc dismisses.
final class SidePicker: NSObject {
    typealias Completion = (_ side: Side?, _ remember: Bool) -> Void

    private var panel: PickerPanel?
    private var tiles: [Side: ChoiceTile] = [:]
    private var highlighted: Side = .right
    private var completion: Completion?
    private var keyMonitor: Any?
    private var timeout: DispatchWorkItem?
    private let remember = NSButton(checkboxWithTitle: "Don’t ask again", target: nil, action: nil)

    var isShowing: Bool { panel != nil }

    func show(preselect: Side, completion: @escaping Completion) {
        guard panel == nil else { return }
        self.completion = completion
        highlighted = preselect
        remember.state = .off

        let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = makeContent()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
        self.panel = panel

        if let screen = NSScreen.screens.first(where: { Displays.screenID($0) == CGMainDisplayID() }) ?? NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.midX - panel.frame.width / 2,
                                         y: v.maxY - panel.frame.height - v.height * 0.16))
        }

        updateHighlight()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 123: self.finish(.left)
            case 124: self.finish(.right)
            case 36, 76: self.finish(self.highlighted)
            case 53: self.finish(nil)
            default: return event
            }
            return nil
        }

        // Leave the layout untouched if the prompt is ignored.
        let work = DispatchWorkItem { [weak self] in self?.finish(nil) }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    /// Debug aid for `--preview`: writes the panel's current contents to a PNG.
    func snapshot(to path: String) {
        guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func makeContent() -> NSView {
        let title = NSTextField(labelWithString: "Where’s your iPad?")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Choose which side of your Mac it sits on.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        for side in [Side.left, .right] {
            let tile = ChoiceTile(side: side)
            tile.onHover = { [weak self] in self?.highlighted = $0; self?.updateHighlight() }
            tile.onClick = { [weak self] in self?.finish($0) }
            tiles[side] = tile
        }
        let row = NSStackView(views: [tiles[.left]!, tiles[.right]!])
        row.spacing = 10
        row.distribution = .fillEqually

        remember.controlSize = .small
        remember.font = .systemFont(ofSize: 11)
        remember.contentTintColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, subtitle, row, remember])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setCustomSpacing(14, after: subtitle)
        stack.setCustomSpacing(12, after: row)
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 14, right: 18)

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 26
            glass.contentView = stack
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 20
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            stack.topAnchor.constraint(equalTo: blur.topAnchor),
            stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        return blur
    }

    private func updateHighlight() {
        for (side, tile) in tiles { tile.isHighlighted = side == highlighted }
    }

    private func finish(_ side: Side?) {
        guard let panel else { return }
        timeout?.cancel()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        let remember = self.remember.state == .on
        let completion = self.completion
        self.panel = nil
        self.completion = nil
        tiles.removeAll()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
        completion?(side, remember)
    }
}

/// Lets a non-activating panel take keyboard focus without bringing the app forward.
private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// One clickable option showing a tiny Mac + iPad arrangement.
private final class ChoiceTile: NSView {
    let side: Side
    var onHover: ((Side) -> Void)?
    var onClick: ((Side) -> Void)?
    var isHighlighted = false { didSet { updateLook() } }
    private var pressed = false { didSet { updateLook() } }

    init(side: Side) {
        self.side = side
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous

        let mac = Self.symbol("laptopcomputer", size: 34, color: .labelColor)
        let pad = Self.symbol("ipad.landscape", size: 24, color: .controlAccentColor)
        let devices = NSStackView(views: side == .left ? [pad, mac] : [mac, pad])
        devices.spacing = 6
        devices.alignment = .centerY

        let name = NSTextField(labelWithString: side == .left ? "Left" : "Right")
        name.font = .systemFont(ofSize: 13, weight: .medium)
        let key = NSTextField(labelWithString: side == .left ? "←" : "→")
        key.font = .systemFont(ofSize: 12, weight: .medium)
        key.textColor = .tertiaryLabelColor
        let caption = NSStackView(views: side == .left ? [key, name] : [name, key])
        caption.spacing = 4

        let stack = NSStackView(views: [devices, caption])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 142),
            heightAnchor.constraint(equalToConstant: 92),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("iPad on the \(side.rawValue)")
        updateLook()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImageView {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
        let view = NSImageView(image: image ?? NSImage())
        view.contentTintColor = color
        return view
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?(side) }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?(side) }
    }
    override func accessibilityPerformPress() -> Bool { onClick?(side); return true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLook()
    }

    private func updateLook() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor.controlAccentColor
            let fill: NSColor = isHighlighted
                ? accent.withAlphaComponent(pressed ? 0.32 : 0.2)
                : NSColor.labelColor.withAlphaComponent(pressed ? 0.12 : 0.06)
            layer?.backgroundColor = fill.cgColor
            layer?.borderWidth = isHighlighted ? 1.5 : 0
            layer?.borderColor = accent.withAlphaComponent(0.7).cgColor
        }
    }
}
