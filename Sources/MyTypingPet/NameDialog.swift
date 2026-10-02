import AppKit

/// プリセット名を入力するダイアログ。
@MainActor
final class NameDialog: NSObject, NSTextFieldDelegate {
    private let alert = NSAlert()
    private let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))

    init(prompt: String, initial: String) {
        super.init()
        alert.messageText = "プリセット名"
        alert.informativeText = "\(prompt) (\(Preset.maxNameLength) 文字まで)"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")

        field.stringValue = String(initial.prefix(Preset.maxNameLength))
        field.delegate = self
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
    }

    private var name: String { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 入力された名前 (前後の空白を除く)。キャンセルなら nil。
    func run() -> String? {
        App.activate()
        updateOK()
        return alert.runModal() == .alertFirstButtonReturn ? name : nil
    }

    func controlTextDidChange(_ notification: Notification) {
        if field.stringValue.count > Preset.maxNameLength {
            field.stringValue = String(field.stringValue.prefix(Preset.maxNameLength))
        }
        updateOK()
    }

    private func updateOK() {
        alert.buttons[0].isEnabled = !name.isEmpty
    }
}
