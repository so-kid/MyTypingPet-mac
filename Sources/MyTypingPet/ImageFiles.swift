import Foundation

/// Application Support にコピーした画像の置き場所。
/// images/ 直下は今の設定が使う画像、images/presets/<ID>/ はプリセットが持つ画像。
/// 今の設定とプリセットが同じファイルを共有しないようにして、片方の変更がもう片方を壊さないようにする。
enum ImageFiles {
    static let dir = Settings.dir.appendingPathComponent("images", isDirectory: true)
    static let presetsDir = dir.appendingPathComponent("presets", isDirectory: true)

    /// 今の設定用に、重ならない名前でコピーする (元ファイルを動かされても困らないように)。
    static func copyToCurrent(_ source: URL, prefix: String) throws -> String {
        try copy(source, to: dir, name: "\(prefix)-\(UUID().uuidString.lowercased())")
    }

    static func copy(_ source: URL, to dir: URL, name: String) throws -> String {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var dest = dir.appendingPathComponent(name)
        if !source.pathExtension.isEmpty {
            dest.appendPathExtension(source.pathExtension.lowercased())
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest.path
    }

    /// 今の設定用の画像を消す。プリセットの画像や images/ の外のファイルには触らない。
    static func deleteCurrent(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        let full = URL(fileURLWithPath: path).standardizedFileURL.path
        guard full.hasPrefix(dir.standardizedFileURL.path + "/"),
              !full.hasPrefix(presetsDir.standardizedFileURL.path + "/") else { return }
        do {
            try FileManager.default.removeItem(atPath: full)
        } catch {
            Log.write("古い画像を消せませんでした: \(full)", error)
        }
    }
}
