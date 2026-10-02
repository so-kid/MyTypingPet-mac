import AppKit
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.load()
    private var pet: PetWindow!
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let input = InputMonitor()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Dock と Cmd+Tab に出さない

        pet = PetWindow(settings: settings)
        pet.menuRequested = { [weak self] event in
            guard let self, let view = self.pet.contentView else { return }
            NSMenu.popUpContextMenu(self.menu, with: event, for: view)
        }
        pet.orderFrontRegardless()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "MyTypingPet")
        statusItem.menu = menu

        input.keyPressed = { [weak self] key in self?.pet.keyPressed(key) }
        input.modifierTapped = { [weak self] key in self?.pet.showPatternIfAny(key) }
        input.mouseClicked = { [weak self] key in self?.pet.showPatternIfAny(key) } // クリックは登録したものにだけ反応する
        startInput()
    }

    // MARK: - メニュー

    /// 開くたびに作り直す (パターンの一覧やチェックを今の状態にするため)。
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menu.removeAllItems()

        if !input.isRunning {
            menu.addItem(ActionItem("入力監視を許可する...") { [weak self] in self?.openPermissionSettings() })
            menu.addItem(.separator())
        }

        let image = NSMenu()
        image.addItem(ActionItem("待機...") { [weak self] in self?.pickImage(.idle) })
        image.addItem(ActionItem("左手...") { [weak self] in self?.pickImage(.left) })
        image.addItem(ActionItem("右手...") { [weak self] in self?.pickImage(.right) })
        image.addItem(.separator())
        image.addItem(ActionItem("既定の絵に戻す") { [weak self] in self?.resetImages() })
        menu.addItem(submenu("画像を変更", image))

        menu.addItem(submenu("パターン", patternMenu()))

        let patternTime = NSMenu()
        for seconds in Settings.patternSecondsChoices {
            let title = seconds > 0 ? "\(seconds.formatted()) 秒" : "次の入力まで"
            let item = ActionItem(title) { [weak self] in
                self?.settings.patternSeconds = seconds
                self?.settings.save()
            }
            item.state = seconds == settings.patternSeconds ? .on : .off
            patternTime.addItem(item)
        }
        menu.addItem(submenu("パターンの表示時間", patternTime))

        menu.addItem(submenu("プリセット", presetMenu()))

        let size = NSMenu()
        for (index, name) in PetWindow.sizeNames.enumerated() {
            let item = ActionItem(name) { [weak self] in
                guard let self else { return }
                self.settings.sizeIndex = index
                self.pet.applySize()
                self.settings.save()
            }
            item.state = index == settings.sizeIndex ? .on : .off
            size.addItem(item)
        }
        menu.addItem(submenu("サイズ", size))

        let topmost = ActionItem("常に最前面") { [weak self] in
            guard let self else { return }
            self.settings.topmost.toggle()
            self.pet.applyTopmost()
            self.settings.save()
        }
        topmost.state = settings.topmost ? .on : .off
        menu.addItem(topmost)

        let locked = ActionItem("位置ロック (クリックを透過)") { [weak self] in
            guard let self else { return }
            self.settings.locked.toggle()
            self.pet.applyLocked()
            self.settings.save()
        }
        locked.state = settings.locked ? .on : .off
        menu.addItem(locked)

        menu.addItem(ActionItem("位置リセット") { [weak self] in self?.pet.resetPosition() })

        let loginItem = ActionItem("ログイン時に起動") { [weak self] in self?.toggleLoginItem() }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(ActionItem("終了") { NSApp.terminate(nil) })
    }

    private func patternMenu() -> NSMenu {
        let patterns = NSMenu()
        let add = ActionItem("パターンを追加... (\(settings.patterns.count)/\(Settings.maxPatterns))") { [weak self] in
            self?.addPattern()
        }
        add.isEnabled = settings.patterns.count < Settings.maxPatterns
        patterns.addItem(add)
        if !settings.patterns.isEmpty {
            patterns.addItem(.separator())
        }

        for pattern in settings.patterns {
            let actions = NSMenu()
            actions.addItem(ActionItem("キーを変更...") { [weak self] in
                guard let self, let trigger = self.askTrigger(except: pattern) else { return }
                pattern.trigger = trigger
                self.savePatterns()
            })
            actions.addItem(ActionItem("画像を変更...") { [weak self] in
                guard let self, let url = self.askImage("「\(pattern.trigger)」の画像を選択"),
                      let path = self.copyImage(url, prefix: "pattern") else { return }
                ImageFiles.deleteCurrent(pattern.image)
                pattern.image = path
                self.savePatterns()
            })
            actions.addItem(ActionItem("削除") { [weak self] in
                guard let self else { return }
                self.settings.patterns.removeAll { $0 === pattern }
                ImageFiles.deleteCurrent(pattern.image)
                self.savePatterns()
            })
            let item = submenu(pattern.trigger.description, actions)
            item.image = thumbnail(pattern.image)
            patterns.addItem(item)
        }
        return patterns
    }

    private func presetMenu() -> NSMenu {
        let presets = NSMenu()
        let save = ActionItem("現在の設定を保存... (\(settings.presets.count)/\(Settings.maxPresets))") { [weak self] in
            self?.savePreset()
        }
        save.isEnabled = settings.presets.count < Settings.maxPresets
        presets.addItem(save)
        if !settings.presets.isEmpty {
            presets.addItem(.separator())
        }

        for preset in settings.presets {
            let actions = NSMenu()
            actions.addItem(ActionItem("適用") { [weak self] in
                guard let self, App.confirm("「\(preset.name)」を適用します。\n今の画像とパターンは置き換わります。") else { return }
                preset.apply(to: self.settings)
                self.applyImages()
            })
            actions.addItem(ActionItem("今の設定で上書き") { [weak self] in
                guard let self, App.confirm("「\(preset.name)」を今の画像とパターンで上書きします。") else { return }
                preset.capture(from: self.settings)
                self.settings.save()
            })
            actions.addItem(ActionItem("名前を変更...") { [weak self] in
                guard let self, let name = NameDialog(prompt: "新しい名前", initial: preset.name).run() else { return }
                preset.name = name
                self.settings.save()
            })
            actions.addItem(ActionItem("削除") { [weak self] in
                guard let self, App.confirm("「\(preset.name)」を削除します。") else { return }
                self.settings.presets.removeAll { $0 === preset }
                preset.deleteFiles()
                self.settings.save()
            })
            let item = submenu(preset.name, actions)
            item.image = thumbnail(preset.idleImage)
            item.toolTip = "パターン \(preset.patterns.count) 個"
            presets.addItem(item)
        }
        return presets
    }

    private func savePreset() {
        guard let name = NameDialog(prompt: "保存するプリセットの名前", initial: "プリセット \(settings.presets.count + 1)").run() else { return }
        let preset = Preset(name: name)
        preset.capture(from: settings)
        settings.presets.append(preset)
        settings.save()
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.autoenablesItems = false
        item.submenu = menu
        return item
    }

    private func thumbnail(_ path: String?) -> NSImage? {
        guard let image = PetWindow.loadImage(path) else { return nil }
        let height: CGFloat = 20
        let width = min(48, max(1, image.size.width * height / image.size.height))
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }

    // MARK: - 画像

    private func pickImage(_ pose: Pose) {
        let name = switch pose {
        case .idle: "待機"
        case .left: "左手"
        case .right: "右手"
        }
        guard let url = askImage("\(name)の画像を選択 (推奨 800x500, 透過PNG)"),
              let path = copyImage(url, prefix: "\(pose)") else { return }

        switch pose {
        case .idle: ImageFiles.deleteCurrent(settings.idleImage); settings.idleImage = path
        case .left: ImageFiles.deleteCurrent(settings.leftImage); settings.leftImage = path
        case .right: ImageFiles.deleteCurrent(settings.rightImage); settings.rightImage = path
        }
        applyImages()
    }

    private func resetImages() {
        for path in [settings.idleImage, settings.leftImage, settings.rightImage] {
            ImageFiles.deleteCurrent(path)
        }
        settings.idleImage = nil
        settings.leftImage = nil
        settings.rightImage = nil
        applyImages()
    }

    private func applyImages() {
        settings.save()
        pet.reloadImages()
        pet.applySize() // 待機画像の縦横比が変わるかもしれない
    }

    private func askImage(_ message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.allowedContentTypes = [.png, .jpeg, .gif, .bmp]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        App.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 選んだ画像を Application Support にコピーする。読めない画像ならエラーを出して nil。
    private func copyImage(_ url: URL, prefix: String) -> String? {
        guard NSImage(contentsOf: url) != nil else {
            App.alert("画像を読み込めませんでした。\n\(url.lastPathComponent)")
            return nil
        }
        do {
            return try ImageFiles.copyToCurrent(url, prefix: prefix)
        } catch {
            Log.write("画像をコピーできませんでした: \(url.path)", error)
            App.alert("画像をコピーできませんでした。\n\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - パターン

    private func addPattern() {
        guard let trigger = askTrigger(except: nil),
              let url = askImage("「\(trigger)」で表示する画像を選択"),
              let path = copyImage(url, prefix: "pattern") else { return }
        settings.patterns.append(Pattern(trigger: trigger, image: path))
        savePatterns()
    }

    private func askTrigger(except: Pattern?) -> KeyTrigger? {
        TriggerDialog { [settings] trigger in
            if settings.patterns.contains(where: { $0 !== except && $0.trigger == trigger }) {
                return "「\(trigger)」は別のパターンで使っています。"
            }
            return nil
        }.run()
    }

    private func savePatterns() {
        settings.save()
        pet.reloadImages()
    }

    // MARK: - ログイン時に起動

    private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                return
            }
            try service.register()
            if service.status == .requiresApproval {
                App.alert("「システム設定 → 一般 → ログイン項目」で MyTypingPet をオンにしてください。")
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            Log.write("ログイン時の起動を切り替えられませんでした", error)
            App.alert("ログイン時の起動を設定できませんでした。\n\(error.localizedDescription)")
        }
    }

    // MARK: - 入力監視

    /// 入力監視を始める。許可がなければ許可を求め、許可されるまで数秒おきに試す。
    private func startInput() {
        if input.start() { return }
        InputMonitor.requestPermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.input.start() else { return }
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    private func openPermissionSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}

/// 押したときにクロージャを呼ぶメニュー項目。
@MainActor
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

@MainActor
enum App {
    /// Dock に出ないアプリなので、ダイアログを出す前に前面に出す。
    static func activate() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func confirm(_ message: String) -> Bool {
        activate()
        let alert = NSAlert()
        alert.messageText = "MyTypingPet"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func alert(_ message: String) {
        activate()
        let alert = NSAlert()
        alert.messageText = "MyTypingPet"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
