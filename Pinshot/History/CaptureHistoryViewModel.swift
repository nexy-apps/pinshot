import AppKit

/// 履歴の一覧の選択と操作（浮かせる・コピー・保存・Finder・消す）。
/// 選んでいるものがあるときは、選んでいるものすべてに対して行う
@MainActor
final class CaptureHistoryViewModel: ObservableObject, HistoryListModel {
    let history: CaptureHistory
    /// 選んでいる履歴
    @Published private(set) var selection = ListSelection()
    /// マウスを乗せている 1 枚（乗せている間だけ、操作のボタンを出す）
    @Published var hovered: UUID?
    /// 操作したあとの短い知らせ（「コピーしました」など。文字の一覧と同じ所に出す）
    let notice: HistoryNotice
    /// 縮小画像（読み込んだものを覚えておく）
    private let thumbnails = NSCache<NSUUID, NSImage>()

    init(history: CaptureHistory, notice: HistoryNotice) {
        self.history = history
        self.notice = notice
    }

    var listedEntries: [CaptureHistoryEntry] { history.entries }

    func updateSelection(_ change: (inout ListSelection) -> Void) {
        change(&selection)
    }

    func thumbnail(for entry: CaptureHistoryEntry) -> NSImage? {
        if let cached = thumbnails.object(forKey: entry.id as NSUUID) { return cached }
        guard let image = history.thumbnailImage(for: entry) else { return nil }
        thumbnails.setObject(image, forKey: entry.id as NSUUID)
        return image
    }

    // MARK: - 操作

    /// 浮かせる（2 枚以上は、少しずつずらして重ねる）
    func pin(_ entries: [CaptureHistoryEntry]) {
        history.pin(entries)
    }

    func copy(_ entry: CaptureHistoryEntry) {
        if history.copy(entry) { show("コピーしました") }
    }

    /// 撮ったときの画像を上げて、共有リンクをコピーする（上げる先は設定の「共有」）
    func upload(_ entry: CaptureHistoryEntry) {
        guard let image = history.loadImage(for: entry) else { return NSSound.beep() }
        UploadCenter.shared.shareImage(image, pointSize: entry.pointSize) { [weak self] status in
            self?.notice.show(status.text, working: status.isWorking)
        }
    }

    /// 画像の文字を読み取ってコピーする
    func copyText(_ entry: CaptureHistoryEntry) {
        guard let image = history.loadImage(for: entry) else { return NSSound.beep() }
        show("文字を読み取っています…")
        Task { @MainActor [weak self] in
            let result = await TextRecognizer.copyText(in: image, pointSize: entry.pointSize)
            self?.show(TextRecognizer.resultMessage(copiedCount: result.text.count))
        }
    }

    /// 保存する（1 枚は保存の設定に合わせる。2 枚以上は、保存先のフォルダにまとめて書く）
    func save(_ entries: [CaptureHistoryEntry]) {
        let files = entries.compactMap { entry -> (data: Data, name: String)? in
            guard let data = try? Data(contentsOf: history.imageURL(for: entry)) else { return nil }
            return (data, ImageExporter.fileName(for: entry.date))
        }
        guard !files.isEmpty else { return NSSound.beep() }
        if files.count == 1 {
            ImageSaver.save(files[0].data, suggestedName: files[0].name) { [weak self] in self?.show("保存しました") }
        } else {
            ImageSaver.saveAll(files) { [weak self] count in self?.show("\(count) 枚を保存しました") }
        }
    }

    func revealInFinder(_ entries: [CaptureHistoryEntry]) {
        NSWorkspace.shared.activateFileViewerSelecting(entries.map { history.imageURL(for: $0) })
    }

    /// 履歴から消す（2 枚以上のときは確かめる）
    func remove(_ entries: [CaptureHistoryEntry]) {
        guard !entries.isEmpty else { return }
        guard entries.count > 1 else { return removeNow(entries) }
        AppAlert.confirm(
            "選んだ \(entries.count) 枚を履歴から削除しますか？",
            detail: "元に戻せません（浮かせている画像は削除されません）。",
            confirmTitle: "\(entries.count) 枚を削除",
            in: CaptureHistoryWindowController.shared.window
        ) { [weak self] in
            self?.removeNow(entries)
        }
    }

    private func removeNow(_ entries: [CaptureHistoryEntry]) {
        let ids = Set(entries.map(\.id))
        selection.remove(ids)
        history.remove(ids: ids)
        show(entries.count == 1 ? "履歴から削除しました" : "\(entries.count) 枚を履歴から削除しました")
    }

    private func show(_ text: String) {
        notice.show(text)
    }

    // MARK: - キー

    /// 一覧のキー操作。扱ったら true（リストのときだけ ↑ ↓ でも動かす。⌘C は先頭の 1 枚をコピー）
    func handleKey(_ event: NSEvent) -> Bool {
        handleListKey(
            event,
            horizontal: true,
            vertical: AppSettings.shared.historyLayout == .list,
            remove: { self.remove($0) },
            activate: { self.pin($0) },
            copy: { self.copy($0[0]) }
        )
    }
}
