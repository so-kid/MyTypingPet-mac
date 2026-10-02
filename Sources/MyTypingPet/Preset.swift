import Foundation

/// 待機・左手・右手の画像とパターンの一式。画像は専用フォルダにコピーして持つ。
final class Preset: Codable {
    static let maxNameLength = 16

    var id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    var name: String
    var idleImage: String?
    var leftImage: String?
    var rightImage: String?
    var patterns: [Pattern] = []

    init(name: String) {
        self.name = name
    }

    private var folder: URL { ImageFiles.presetsDir.appendingPathComponent(id, isDirectory: true) }

    /// 今の画像とパターンをこのプリセットに写す (前の中身は捨てる)。
    func capture(from settings: Settings) {
        deleteFiles()
        idleImage = copyIn(settings.idleImage, name: "idle")
        leftImage = copyIn(settings.leftImage, name: "left")
        rightImage = copyIn(settings.rightImage, name: "right")
        patterns = settings.patterns.enumerated().map { i, p in
            Pattern(trigger: p.trigger, image: copyIn(p.image, name: "pattern\(i + 1)"))
        }
    }

    /// このプリセットの画像とパターンを今の設定にする。今まで使っていた画像は消す。
    func apply(to settings: Settings) {
        let oldImages = [settings.idleImage, settings.leftImage, settings.rightImage] + settings.patterns.map(\.image)

        settings.idleImage = Self.copyOut(idleImage, prefix: "idle")
        settings.leftImage = Self.copyOut(leftImage, prefix: "left")
        settings.rightImage = Self.copyOut(rightImage, prefix: "right")
        settings.patterns = patterns.map { Pattern(trigger: $0.trigger, image: Self.copyOut($0.image, prefix: "pattern")) }

        for path in oldImages {
            ImageFiles.deleteCurrent(path)
        }
    }

    func deleteFiles() {
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            Log.write("プリセットの画像を消せませんでした: \(folder.path)", error)
        }
    }

    // 画像が未設定 (既定の絵) や行方不明のときは nil のまま持つ
    private func copyIn(_ source: String?, name: String) -> String? {
        guard let source, FileManager.default.fileExists(atPath: source) else { return nil }
        do {
            return try ImageFiles.copy(URL(fileURLWithPath: source), to: folder, name: name)
        } catch {
            Log.write("プリセットへ画像をコピーできませんでした: \(source)", error)
            return nil
        }
    }

    private static func copyOut(_ source: String?, prefix: String) -> String? {
        guard let source, FileManager.default.fileExists(atPath: source) else { return nil }
        do {
            return try ImageFiles.copyToCurrent(URL(fileURLWithPath: source), prefix: prefix)
        } catch {
            Log.write("プリセットから画像をコピーできませんでした: \(source)", error)
            return nil
        }
    }
}
