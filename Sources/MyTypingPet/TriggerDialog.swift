import AppKit

/// パターンのキー・クリックを実際に押して登録するダイアログ。
@MainActor
final class TriggerDialog: NSObject, NSWindowDelegate {
    private let validate: (KeyTrigger) -> String?
    private let window: NSWindow
    private let preview = NSTextField(labelWithString: "…")
    private let anyKeyCheck = NSButton(checkboxWithTitle: "組み合わせるキーは何でもOK (修飾キー + 任意のキー)", target: nil, action: nil)
    private let errorText = NSTextField(wrappingLabelWithString: "")
    private var monitor: Any?

    private var held: Mods = []
    private var peak: Mods = []       // 修飾キーを押し始めてから全部離すまでに押されていたもの全部
    private var otherPressed = false  // その間に普通のキーやクリックがあったか
    private var result: KeyTrigger?

    /// - Parameter validate: 登録できないときはその理由を返す。
    init(validate: @escaping (KeyTrigger) -> String?) {
        self.validate = validate
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 10),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()

        window.title = "パターンの入力を登録"
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.delegate = self
        let content = buildContent()
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
    }

    /// 登録された入力。キャンセルなら nil。
    func run() -> KeyTrigger? {
        // キーはここで全部受け取って、ボタンやメニューのショートカットには渡さない
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type == .keyDown {
                self.keyDown(event)
            } else {
                self.flagsChanged(event)
            }
            return nil
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        App.activate()
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return result
    }

    private func buildContent() -> NSView {
        let title = NSTextField(wrappingLabelWithString: "登録したいキーを押すか、下の枠をクリックしてください")
        title.font = .boldSystemFont(ofSize: 14)

        let example = NSTextField(wrappingLabelWithString: "例: ⌘ + S / F5 / ⇧ Shift だけ押して離す / ⌃ Control を押しながら右クリック")
        example.textColor = .secondaryLabelColor

        preview.font = .systemFont(ofSize: 20)
        preview.alignment = .center
        let previewBox = NSBox()
        previewBox.boxType = .custom
        previewBox.cornerRadius = 6
        previewBox.borderWidth = 0
        previewBox.fillColor = .quaternaryLabelColor
        previewBox.contentViewMargins = NSSize(width: 12, height: 12)
        previewBox.contentView = preview

        // ボタン類はキー入力を奪わないようフォーカスを取らせない (操作はマウスで)
        anyKeyCheck.refusesFirstResponder = true
        let anyKeyHint = NSTextField(wrappingLabelWithString: "チェックすると、修飾キーを押して離すだけで登録できます")
        anyKeyHint.textColor = .secondaryLabelColor

        let clickArea = ClickArea { [weak self] trigger in
            self?.otherPressed = true // ⌃ + クリックの後に ⌃ 単独として登録されないように
            self?.submit(trigger)
        }

        errorText.textColor = .systemRed
        errorText.isHidden = true

        let cancel = NSButton(title: "キャンセル", target: self, action: #selector(cancel))
        cancel.refusesFirstResponder = true
        let buttonRow = NSStackView(views: [NSView(), cancel])

        let stack = NSStackView(views: [title, example, previewBox, anyKeyCheck, anyKeyHint, clickArea, errorText, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(16, after: example)
        stack.setCustomSpacing(14, after: previewBox)
        stack.setCustomSpacing(14, after: anyKeyHint)
        stack.setCustomSpacing(16, after: errorText)
        for view in [title, example, previewBox, anyKeyHint, clickArea, errorText, buttonRow] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        clickArea.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.widthAnchor.constraint(equalToConstant: 420).isActive = true
        return stack
    }

    private var anyKey: Bool { anyKeyCheck.state == .on }

    private func keyDown(_ event: NSEvent) {
        if event.isARepeat { return }
        otherPressed = true

        let mods = Mods(event.modifierFlags)
        if !anyKey {
            submit(KeyTrigger(mods: mods, keyCode: event.keyCode))
        } else if !mods.isEmpty {
            submit(KeyTrigger(mods: mods, keyCode: KeyTrigger.anyKey))
        } else {
            showError("「任意のキー」は修飾キー (⌃ ⌥ ⇧ ⌘) と一緒に押してください。")
        }
    }

    private func flagsChanged(_ event: NSEvent) {
        let keyCode = KeyTrigger.normalize(event.keyCode)
        let mod = KeyTrigger.modOf(keyCode)
        guard !mod.isEmpty else { return } // CapsLock, fn など

        let now = Mods(event.modifierFlags)
        if held.isEmpty && !now.isEmpty {
            // 押し始め
            peak = []
            otherPressed = false
        }
        let pressed = now.isStrictSuperset(of: held)
        held = now

        if pressed {
            peak.formUnion(now)
            preview.stringValue = anyKey
                ? KeyTrigger(mods: peak, keyCode: KeyTrigger.anyKey).description
                : (now.symbols + ["…"]).joined(separator: " + ")
            return
        }
        guard held.isEmpty, !otherPressed else { return }

        // 修飾キーだけを押して全部離した
        if anyKey {
            submit(KeyTrigger(mods: peak, keyCode: KeyTrigger.anyKey)) // 例: ⇧⌘ を押して離す → ⇧ + ⌘ + 任意のキー
        } else if peak == mod {
            submit(KeyTrigger(mods: [], keyCode: keyCode)) // 単独で押して離した
        } else {
            showError("修飾キー単独のパターンは 1 つずつ登録してください (\(peak.symbols.joined(separator: " + ")) が同時に押されていました)。")
        }
    }

    private func submit(_ trigger: KeyTrigger) {
        preview.stringValue = trigger.description
        if let error = validate(trigger) {
            showError(error)
            return
        }
        result = trigger
        NSApp.stopModal()
    }

    private func showError(_ message: String) {
        errorText.stringValue = message
        errorText.isHidden = false
    }

    @objc private func cancel() {
        NSApp.stopModal()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal()
    }
}

/// クリックしたボタンと、そのとき押されていた修飾キーを登録する枠。
private final class ClickArea: NSView {
    private let clicked: (KeyTrigger) -> Void

    init(clicked: @escaping (KeyTrigger) -> Void) {
        self.clicked = clicked
        super.init(frame: .zero)

        let label = NSTextField(labelWithString: "ここをクリック (左・右・中・サイドボタン)")
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.tertiaryLabelColor.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) { click(event) }
    override func rightMouseDown(with event: NSEvent) { click(event) }
    override func otherMouseDown(with event: NSEvent) { click(event) }

    private func click(_ event: NSEvent) {
        if let trigger = KeyTrigger.mouse(event.buttonNumber, mods: Mods(event.modifierFlags)) {
            clicked(trigger)
        }
    }
}
