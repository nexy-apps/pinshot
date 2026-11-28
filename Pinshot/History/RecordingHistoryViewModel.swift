import AppKit

/// 録画の一覧（履歴のウィンドウの「録画」）の選択と操作。
/// 選び方は、ほかの一覧と同じ（クリック・⌘ + クリック・shift + クリック・⌘A・矢印キー）。
/// 録画からいつでも同じ GIF を作り直せるので、GIF はアプリの中に残さない。上げた GIF は、上げたものの履歴が覚えている
/// 元の録画の名前（sourceName）で結び付けて、印とリンクを出す
@MainActor
final class RecordingHistoryViewModel: ObservableObject {
    let store: RecordingStore
    @Published private(set) var selection = ListSelection()
    /// マウスを乗せている 1 本
    @Published var hovered: UUID?
    /// GIF を作って保存している録画（作っている間は、同じ録画でもう一度押せない）
    @Published private(set) var exporting: Set<UUID> = []
    /// 読み込んだ縮小画像と長さ（1 本につき 1 回読む）
    @Published private var thumbnails: [UUID: NSImage] = [:]
    @Published private var durations: [UUID: TimeInterval] = [:]
    private var loading: Set<UUID> = []
    let notice: HistoryNotice

    init(store: RecordingStore, notice: HistoryNotice) {
        self.store = store
        self.notice = notice
    }

    /// 選んでいるもの（新しい順）
    var selectedEntries: [RecordingHistoryEntry] {
        store.entries.filter { selection.contains($0.id) }
    }

    /// entry に対する操作の対象（entry を選んでいれば、選んでいるものすべて。そうでなければ entry だけ）
    func targets(for entry: RecordingHistoryEntry) -> [RecordingHistoryEntry] {
        selection.contains(entry.id) ? selectedEntries : [entry]
    }

    // MARK: - 縮小画像と長さ

    func thumbnail(for entry: RecordingHistoryEntry) -> NSImage? { thumbnails[entry.id] }

    /// 長さ（例: 「0:12」。読む前は nil）
    func durationText(for entry: RecordingHistoryEntry) -> String? {
        durations[entry.id].map(RecordingRules.elapsedText)
    }

    /// 縮小画像と長さを読む（まだなら。一覧に出たときに呼ぶ）
    func load(_ entry: RecordingHistoryEntry) {
        guard thumbnails[entry.id] == nil, !loading.contains(entry.id) else { return }
        loading.insert(entry.id)
        Task {
            async let frame = GIFExporter.firstFrame(of: entry.url)
            async let info = RecordingActions.info(of: entry.url)
            let (image, details) = await (frame, info)
            loading.remove(entry.id)
            if let image { thumbnails[entry.id] = NSImage(cgImage: image, size: .zero) }
            if let details { durations[entry.id] = details.duration }
        }
    }

    // MARK: - 上げた GIF

    /// この録画を GIF にして上げた、いちばん新しいもの（どの上げる先でも。なければ nil）
    func upload(for entry: RecordingHistoryEntry) -> UploadHistoryEntry? {
        UploadHistory.shared.entries.first { $0.sourceName == entry.name }
    }

    // MARK: - 選ぶ

    private var order: [UUID] { store.entries.map(\.id) }

    func click(_ entry: RecordingHistoryEntry, modifiers: NSEvent.ModifierFlags) {
        selection.click(entry.id, command: modifiers.contains(.command), shift: modifiers.contains(.shift), order: order)
    }

    /// url の録画だけを選ぶ（録画の窓の「履歴」から開いたとき）
    func reveal(url: URL) {
        guard let entry = store.entry(for: url) else { return }
        selection.click(entry.id, command: false, shift: false, order: order)
    }

    func selectAll() {
        selection.selectAll(order)
    }

    func clearSelection() {
        selection.clear()
    }

    // MARK: - 操作

    /// 浮かせて再生する（たくさん開きすぎないよう、5 本まで。もう浮かせていれば、前に出す）
    func play(_ entries: [RecordingHistoryEntry]) {
        let targets = Array(entries.prefix(5))
        guard !targets.isEmpty else { return }
        Task {
            var alreadyOpen = 0
            for entry in targets {
                if await !RecordingActions.play(entry.url) { alreadyOpen += 1 }
            }
            if alreadyOpen == targets.count { notice.show("すでに浮かせています") }
        }
    }

    /// 動画（MP4）を、ファイルとしてクリップボードに入れる（Finder・チャットなどに貼り付けられる）
    func copyFiles(_ entries: [RecordingHistoryEntry]) {
        guard !entries.isEmpty else { return }
        RecordingActions.copyFiles(entries.map(\.url))
        notice.show(entries.count == 1 ? "動画（MP4）をコピーしました" : "\(entries.count) 本の動画（MP4）をコピーしました")
    }

    /// GIF を作って、クリップボードに入れる（1 本ずつ。同じ録画の GIF は作り直さない）
    func copyGIF(_ entries: [RecordingHistoryEntry]) {
        guard let entry = oneOf(entries, action: "GIF をコピー"), !exporting.contains(entry.id) else { return }
        exporting.insert(entry.id)
        notice.show("GIF を作っています…", working: true)
        RecordingActions.copyGIF(
            entry.url,
            progress: { [weak self] value in self?.notice.show("GIF を作っています…（\(Int(value * 100))%）", working: true) },
            done: { [weak self] copied in
                self?.exporting.remove(entry.id)
                self?.notice.show(copied ? "GIF をコピーしました" : "GIF をコピーできませんでした")
            }
        )
    }

    /// GIF にして上げ、共有リンクをコピーする（上げてあれば、作り直さずに前のリンク。1 本ずつ）
    func copyLink(_ entries: [RecordingHistoryEntry]) {
        guard let entry = oneOf(entries, action: "共有リンクをコピー") else { return }
        UploadCenter.shared.shareGIF(fromMovieAt: entry.url) { [weak self] status in
            self?.notice.show(status.displayText, working: status.isWorking)
        }
    }

    /// MP4 で保存する（1 本ずつ）
    func saveMovie(_ entries: [RecordingHistoryEntry]) {
        guard let entry = oneOf(entries, action: "保存") else { return }
        RecordingActions.saveMovie(entry.url) { [weak self] in self?.notice.show("保存しました") }
    }

    /// GIF を作って保存する（1 本ずつ。作っている間は、下に進み具合を出す）
    func saveGIF(_ entries: [RecordingHistoryEntry]) {
        guard let entry = oneOf(entries, action: "GIF で保存"), !exporting.contains(entry.id) else { return }
        exporting.insert(entry.id)
        notice.show("GIF を作っています…", working: true)
        RecordingActions.saveGIF(
            entry.url,
            progress: { [weak self] value in self?.notice.show("GIF を作っています…（\(Int(value * 100))%）", working: true) },
            finished: { [weak self] in
                self?.exporting.remove(entry.id)
                self?.notice.show("GIF を作りました")
            },
            onSaved: { [weak self] in self?.notice.show("GIF を保存しました") }
        )
    }

    func reveal(_ entries: [RecordingHistoryEntry]) {
        guard !entries.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(entries.map(\.url))
    }

    /// 削除する（確かめてから。浮かせている録画の窓も閉じる。保存した MP4・GIF・上げた GIF は消えない）
    func remove(_ entries: [RecordingHistoryEntry]) {
        guard !entries.isEmpty else { return }
        let count = entries.count == 1 ? "この録画" : "選んだ \(entries.count) 本の録画"
        AppAlert.confirm(
            "\(count)を削除しますか？",
            detail: "元に戻せません。浮かせている録画は閉じます（保存した MP4・GIF と、上げた GIF は削除されません）。",
            confirmTitle: entries.count == 1 ? "削除" : "\(entries.count) 本を削除",
            in: CaptureHistoryWindowController.shared.window
        ) { [weak self] in
            guard let self else { return }
            self.selection.remove(Set(entries.map(\.id)))
            self.store.remove(entries)
            self.notice.show(entries.count == 1 ? "録画を削除しました" : "\(entries.count) 本の録画を削除しました")
        }
    }

    /// 1 本ずつの操作で、2 本以上を選んでいるときは知らせて nil（1 本なら、その 1 本）
    private func oneOf(_ entries: [RecordingHistoryEntry], action: String) -> RecordingHistoryEntry? {
        guard entries.count <= 1 else {
            notice.show("「\(action)」は、1 本ずつ選んでください")
            return nil
        }
        return entries.first
    }

    // MARK: - キー

    /// 一覧のキー操作。扱ったら true（どのキーで何をするかは ListKeys。リストのときだけ ↑ ↓ でも動かす）
    func handleKey(_ event: NSEvent) -> Bool {
        let isList = AppSettings.shared.recordingHistoryLayout == .list
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
            play(selected)
        case .copy:
            guard !selected.isEmpty else { return false }
            copyFiles(selected)
        }
        return true
    }
}
