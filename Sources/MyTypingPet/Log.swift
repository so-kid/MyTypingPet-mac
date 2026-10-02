import Foundation

enum Log {
    /// 問題が起きたときの記録を error.log に追記する。ログが書けなくても本体は止めない。
    static func write(_ message: String, _ error: Error? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var line = "[\(formatter.string(from: Date()))] \(message)\n"
        if let error { line += "\(error)\n" }
        NSLog("%@", line)

        let url = Settings.dir.appendingPathComponent("error.log")
        try? FileManager.default.createDirectory(at: Settings.dir, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
