import Foundation

final class Settings: Codable {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MyTypingPet", isDirectory: true)

    private static var fileURL: URL { dir.appendingPathComponent("settings.json") }

    /// ウィンドウ左下の位置 (macOS のスクリーン座標)。
    var x: Double?
    var y: Double?
    var sizeIndex = 1
    var topmost = true
    var locked = false

    // nil のときは既定の絵を使う
    var idleImage: String?
    var leftImage: String?
    var rightImage: String?

    static let maxPatterns = 10

    /// パターンの絵を出しておく秒数。0 なら次の入力まで。
    var patternSeconds = 1.5
    static let patternSecondsChoices: [Double] = [1, 1.5, 2, 3, 0]

    var patterns: [Pattern] = []

    static let maxPresets = 10
    var presets: [Preset] = []

    init() {}

    /// 項目が足りない (古いバージョンで保存した) ファイルも読めるように、ない項目は初期値のままにする。
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x)
        y = try c.decodeIfPresent(Double.self, forKey: .y)
        sizeIndex = try c.decodeIfPresent(Int.self, forKey: .sizeIndex) ?? sizeIndex
        topmost = try c.decodeIfPresent(Bool.self, forKey: .topmost) ?? topmost
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? locked
        idleImage = try c.decodeIfPresent(String.self, forKey: .idleImage)
        leftImage = try c.decodeIfPresent(String.self, forKey: .leftImage)
        rightImage = try c.decodeIfPresent(String.self, forKey: .rightImage)
        patternSeconds = try c.decodeIfPresent(Double.self, forKey: .patternSeconds) ?? patternSeconds
        patterns = try c.decodeIfPresent([Pattern].self, forKey: .patterns) ?? []
        presets = try c.decodeIfPresent([Preset].self, forKey: .presets) ?? []
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else { return Settings() }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            Log.write("settings.json の読み込みに失敗したので初期設定で起動します", error)
            return Settings()
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: Self.fileURL, options: .atomic)
        } catch {
            Log.write("settings.json を保存できませんでした", error)
        }
    }
}
