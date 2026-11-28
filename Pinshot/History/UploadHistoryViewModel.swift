import AppKit

/// 上げたものの一覧の選択と操作（リンクをコピー・ブラウザで開く・削除）。
/// 選び方は、撮った画像・読み取った文字の一覧と同じ（クリック・⌘ + クリック・shift + クリック・⌘A・矢印キー）。
/// 選んでいるものがあるときは、選んでいるものすべてに対して行う
@MainActor
final class UploadHistoryViewModel: ObservableObject {
    let history: UploadHistory
    @Published private(set) var selection = ListSelection()
    /// マウスを乗せている 1 件
    @Published var hovered: UUID?
    let notice: HistoryNotice
    /// 縮小画像（読み込んだものを覚えておく）
    private let thumbnails = NSCache<NSUUID, NSImage>()

    init(history: UploadHistory, notice: HistoryNotice) {
        self.history = history
        self.notice = notice
    }

    /// 選んでいるもの（新しい順）
    var selectedEntries: [UploadHistoryEntry] {
        history.entries.filter { selection.contains($0.id) }
    }

    /// entry に対する操作の対象（entry を選んでいれば、選んでいるものすべて。そうでなければ entry だけ）
    func targets(for entry: UploadHistoryEntry) -> [UploadHistoryEntry] {
        selection.contains(entry.id) ? selectedEntries : [entry]
    }

    func thumbnail(for entry: UploadHistoryEntry) -> NSImage? {
        if let cached = thumbnails.object(forKey: entry.id as NSUUID) { return cached }
        guard let image = history.thumbnail(for: entry) else { return nil }
        thumbnails.setObject(image, forKey: entry.id as NSUUID)
        return image
    }

    // MARK: - 選ぶ

    private var order: [UUID] { history.entries.map(\.id) }

    func click(_ entry: UploadHistoryEntry, modifiers: NSEvent.ModifierFlags) {
        selection.click(entry.id, command: modifiers.contains(.command), shift: modifiers.contains(.shift), order: order)
    }

    func selectAll() {
        selection.selectAll(order)
    }

    func clearSelection() {
        selection.clear()
    }

    // MARK: - 操作

    /// リンクを format の形でコピーする（2 件以上は、1 行に 1 つずつ並べる）
    func copyLinks(_ entries: [UploadHistoryEntry], format: ShareLinkFormat) {
        guard !entries.isEmpty else { return }
        history.copyLinks(of: entries, format: format)
        notice.show(entries.count == 1 ? "コピーしました" : "\(entries.count) 件のリンクをコピーしました")
    }

    /// 手元に残っている元のファイル（録画を GIF にして上げたものの、元の録画。まだ残っていれば）。
    /// 画像は上げるときに元のファイルを残していないので、いつも nil
    func localFile(for entry: UploadHistoryEntry) -> URL? {
        entry.sourceName.flatMap(RecordingStore.shared.file(named:))
    }

    /// 元のファイルが手元に残っているものがあるか（下の帯・右クリックに Finder を出すか）
    func hasLocalFile(_ entries: [UploadHistoryEntry]) -> Bool {
        entries.contains { localFile(for: $0) != nil }
    }

    /// 元のファイル（元の録画）を Finder で見せる（残っているものだけ）
    func revealInFinder(_ entries: [UploadHistoryEntry]) {
        let urls = entries.compactMap(localFile(for:))
        guard !urls.isEmpty else {
            notice.show("Finder で見せられるファイルがありません（画像は、手元に元のファイルを残していません）")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// ブラウザで開く（たくさん開きすぎないよう、10 件まで）
    func openInBrowser(_ entries: [UploadHistoryEntry]) {
        entries.prefix(10).forEach(history.openInBrowser)
    }

    /// 削除する。上げる先からも消すか、一覧から外すだけかを選んでもらう
    func remove(_ entries: [UploadHistoryEntry]) {
        guard !entries.isEmpty else { return }
        let labels = Array(Set(entries.map(\.destination.label))).sorted().joined(separator: "・")
        let deletable = entries.filter { UploadDestinations.destination(for: $0.destination)?.capabilities.canDelete ?? false }
        let count = entries.count == 1 ? "このリンク" : "\(entries.count) 件のリンク"

        // ほかのダイアログと同じ見た目にする（AppAlert。最初の選択肢が青い決定ボタン、キャンセルは esc）
        let detail = deletable.isEmpty
            ? "この一覧から外します（\(labels) の画像は、そのまま残ります）。"
            : "「\(labels) からも削除」を選ぶと、\(labels) の画像も消え、リンクを開いても見られなくなります。元に戻せません。\n「一覧から外すだけ」なら、\(labels) の画像は残ります。"
        let choices = deletable.isEmpty ? ["一覧から外す"] : ["\(labels) からも削除", "一覧から外すだけ"]
        AppAlert.choose(
            "\(count)を削除しますか？",
            detail: detail,
            choices: choices,
            in: CaptureHistoryWindowController.shared.window
        ) { [weak self] index in
            let fromDestination = !deletable.isEmpty && index == 0
            self?.removeNow(entries, fromDestination: fromDestination, labels: labels)
        }
    }

    private func removeNow(_ entries: [UploadHistoryEntry], fromDestination: Bool, labels: String) {
        if fromDestination { notice.show("\(labels) から削除しています…") }
        Task {
            do {
                try await history.remove(entries, fromDestination: fromDestination)
                selection.remove(Set(entries.map(\.id)))
                notice.show(fromDestination ? "\(labels) からも削除しました" : "一覧から外しました")
            } catch {
                // 消せたものは一覧から外れ、消せなかったものは残る
                selection.remove(Set(entries.map(\.id)).subtracting(history.entries.map(\.id)))
                AppAlert.inform("\(labels) から削除できなかったものがあります", detail: error.localizedDescription)
            }
        }
    }

    // MARK: - キー

    /// 一覧のキー操作。扱ったら true（どのキーで何をするかは ListKeys。リストのときだけ ↑ ↓ でも動かす）
    func handleKey(_ event: NSEvent) -> Bool {
        let isList = AppSettings.shared.uploadHistoryLayout == .list
        guard let action = ListKeys.action(for: event, horizontal: true, vertical: isList) else { return false }
        let selected = selectedEntries
        switch action {
        case .selectAll:
            selectAll()
        case .move(let step, let extending):
            selection.move(by: step, extending: extending, order: order)
        case .clearSelection:
            guard !selection.isEmpty else { return false }
            clearSelection()
        case .remove:
            guard !selected.isEmpty else { return false }
            remove(selected)
        case .activate:
            guard !selected.isEmpty else { return false }
            openInBrowser(selected)
        case .copy:
            guard !selected.isEmpty else { return false }
            copyLinks(selected, format: AppSettings.shared.shareLinkFormat)
        }
        return true
    }
}
