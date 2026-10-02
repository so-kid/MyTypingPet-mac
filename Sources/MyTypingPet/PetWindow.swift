import AppKit

/// 透明で枠のないペットのウィンドウ。フォーカスを奪わず、全てのデスクトップ (Spaces) に出る。
@MainActor
final class PetWindow: NSPanel {
    static let sizeNames = ["小", "中", "大", "特大"]
    private static let sizeWidths: [CGFloat] = [160, 240, 320, 440]

    private static let bounceRatio: CGFloat = 0.08 // 跳ねる高さ (画像の高さに対する割合)
    private static let handHoldTime: TimeInterval = 0.3 // 手を上げたまま待つ時間

    private let settings: Settings
    private let petView = PetView()
    private var images: [Pose: NSImage] = [:]
    private var patternImages: [KeyTrigger: NSImage] = [:]
    private var idleTimer: Timer?
    private var nextLeft = true
    private var bounceHeight: CGFloat = 0

    /// ペットが右クリックされたとき (メニュー表示は AppDelegate 側で行う)。
    var menuRequested: ((NSEvent) -> Void)?

    init(settings: Settings) {
        self.settings = settings
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        applyTopmost()
        applyLocked()
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = petView

        petView.rightClicked = { [weak self] event in self?.menuRequested?(event) }

        reloadImages()
        applySize()

        if let x = settings.x, let y = settings.y, Self.isOnScreen(NSPoint(x: x, y: y)) {
            setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            resetPosition()
        }

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePosition() }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func keyPressed(_ key: KeyTrigger) {
        // 修飾キー単独のパターンは離したときに判定する (⌘S の ⌘ で発動させないため)
        if !key.isModifierOnly, let pattern = findKeyPattern(key) {
            showPattern(pattern)
            return
        }

        petView.setImage(images[nextLeft ? .left : .right]!)
        nextLeft.toggle()
        startIdleTimer(after: Self.handHoldTime)
        petView.bounce(height: bounceHeight)
    }

    /// 修飾キー単独・クリックは、登録したパターンにだけ反応する。
    func showPatternIfAny(_ key: KeyTrigger) {
        if let pattern = patternImages[key] {
            showPattern(pattern)
        }
    }

    /// パターンの絵を設定の秒数だけ出す。0 秒なら次の入力まで出しっぱなし。
    private func showPattern(_ image: NSImage) {
        petView.setImage(image)
        if settings.patternSeconds > 0 {
            startIdleTimer(after: settings.patternSeconds)
        } else {
            idleTimer?.invalidate()
        }
        petView.bounce(height: bounceHeight)
    }

    /// 特定のキーのパターンを優先し、なければ「修飾キー + 任意のキー」を探す。
    private func findKeyPattern(_ key: KeyTrigger) -> NSImage? {
        if let exact = patternImages[key] { return exact }
        if !key.mods.isEmpty, let any = patternImages[KeyTrigger(mods: key.mods, keyCode: KeyTrigger.anyKey)] { return any }
        return nil
    }

    private func startIdleTimer(after interval: TimeInterval) {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.petView.setImage(self.images[.idle]!)
            }
        }
        // メニューやダイアログを開いている間も待機の絵に戻す
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    func resetPosition() {
        guard let area = (screen ?? NSScreen.main)?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: area.maxX - frame.width - 16, y: area.minY))
    }

    /// 常に最前面。オフのときは普通のウィンドウと同じ重なり順になる。
    func applyTopmost() {
        level = settings.topmost ? .floating : .normal
    }

    /// 位置ロック。クリックがペットを通り抜ける (解除はメニューバーから)。
    func applyLocked() {
        ignoresMouseEvents = settings.locked
    }

    func savePosition() {
        settings.x = frame.minX
        settings.y = frame.minY
        settings.save()
    }

    private static func isOnScreen(_ origin: NSPoint) -> Bool {
        NSScreen.screens.contains { $0.frame.insetBy(dx: -50, dy: -50).contains(origin) }
    }

    /// 表示サイズと縦横比は待機画像を基準に決める。
    func applySize() {
        let index = min(max(settings.sizeIndex, 0), Self.sizeWidths.count - 1)
        let idle = images[.idle]!
        let width = Self.sizeWidths[index]
        let imageHeight = width * idle.size.height / idle.size.width
        bounceHeight = imageHeight * Self.bounceRatio

        // 足元 (左下) の位置を保ったままサイズを変える
        setContentSize(NSSize(width: width, height: imageHeight + bounceHeight))
        petView.imageHeight = imageHeight
    }

    func reloadImages() {
        images[.idle] = Self.loadImage(settings.idleImage) ?? DefaultArt.render(.idle)
        images[.left] = Self.loadImage(settings.leftImage) ?? DefaultArt.render(.left)
        images[.right] = Self.loadImage(settings.rightImage) ?? DefaultArt.render(.right)

        patternImages.removeAll()
        for pattern in settings.patterns {
            if let image = Self.loadImage(pattern.image) {
                patternImages[pattern.trigger] = image
            }
        }

        idleTimer?.invalidate()
        petView.setImage(images[.idle]!)
    }

    static func loadImage(_ path: String?) -> NSImage? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        guard let image = NSImage(contentsOfFile: path), image.size.width > 0, image.size.height > 0 else {
            Log.write("画像を読み込めませんでした: \(path)")
            return nil
        }
        return image
    }
}

/// ペットの絵を描くビュー。下端に画像を置き、上に跳ねる分の余白を持つ。
@MainActor
private final class PetView: NSView {
    private let imageLayer = CALayer()
    var rightClicked: ((NSEvent) -> Void)?

    var imageHeight: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        withoutAnimation { imageLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: imageHeight) }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let image = currentImage { setImage(image) }
    }

    private var currentImage: NSImage?

    func setImage(_ image: NSImage) {
        currentImage = image
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        withoutAnimation {
            imageLayer.contentsScale = scale
            imageLayer.contents = image.layerContents(forContentsScale: scale)
        }
    }

    /// 一瞬で持ち上げて、落ちてくる。
    func bounce(height: CGFloat) {
        let fall = CABasicAnimation(keyPath: "transform.translation.y")
        fall.fromValue = height
        fall.toValue = 0
        fall.duration = 0.14
        fall.timingFunction = CAMediaTimingFunction(name: .easeIn)
        imageLayer.add(fall, forKey: "bounce")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        rightClicked?(event)
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
