import AppKit

/// CGEventTap (listen-only) でシステム全体のキー押下とマウスボタンを検知する。
/// どのキー・ボタンかはオートリピートの判定とパターンとの照合にしか使わず、保存も送信もしない。
/// 使うには「入力監視」の許可が必要。
@MainActor
final class InputMonitor {
    /// キーが押された (修飾キーを含む)。
    var keyPressed: ((KeyTrigger) -> Void)?
    /// 修飾キーが他のキーと組み合わされずに押して離された。
    var modifierTapped: ((KeyTrigger) -> Void)?
    /// マウスボタンが押された。
    var mouseClicked: ((KeyTrigger) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var soloModifier: UInt16? // 単独で押されている修飾キー。他のキーやクリックがあったら nil に戻す

    static var isPermitted: Bool { CGPreflightListenEventAccess() }

    /// 入力監視の許可ダイアログを出す (出るのは初回だけ)。
    static func requestPermission() { CGRequestListenEventAccess() }

    var isRunning: Bool { tap != nil }

    /// 監視を始める。許可がないときは false。
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }

        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                // main の RunLoop に載せているので、ここはメインスレッド
                MainActor.assumeIsolated { monitor.handle(type, event) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 応答が遅れると OS に止められるので、つなぎ直す
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .keyDown:
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
            soloModifier = nil
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            keyPressed?(KeyTrigger(mods: Mods(event.flags), keyCode: keyCode))

        case .flagsChanged:
            // 修飾キーは押しても離しても flagsChanged になるので、左右別のフラグで押したかどうかを見る
            let rawKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard let (mod, deviceFlag) = KeyTrigger.modifierKeys[rawKeyCode] else { return } // CapsLock, fn など
            let keyCode = KeyTrigger.normalize(rawKeyCode)

            if event.flags.rawValue & deviceFlag != 0 {
                var others = Mods(event.flags)
                others.remove(mod)
                soloModifier = others.isEmpty ? keyCode : nil
                keyPressed?(KeyTrigger(mods: others, keyCode: keyCode))
            } else if soloModifier == keyCode {
                soloModifier = nil
                modifierTapped?(KeyTrigger(mods: [], keyCode: keyCode))
            }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            soloModifier = nil // ⌘ + クリックの後に ⌘ 単独のパターンが出ないように
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if let trigger = KeyTrigger.mouse(button, mods: Mods(event.flags)) {
                mouseClicked?(trigger)
            }

        default:
            break
        }
    }
}
