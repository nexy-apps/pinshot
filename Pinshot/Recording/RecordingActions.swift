import AppKit
import AVFoundation

/// 録画のファイルに対する操作（録画の窓と、履歴のウィンドウの「録画」の一覧で同じものを使う）
@MainActor
enum RecordingActions {
    /// ファイルとしてクリップボードに入れる（Finder・チャットなどに貼り付けられる）
    static func copyFiles(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    /// GIF を作ってクリップボードに入れる（GIF の画像としても、ファイルとしても貼り付けられる）。
    /// 作った GIF は、貼り付けるまで消えないよう、キャッシュのフォルダに録画ごとに置き、同じ録画ならそれを使い回す
    /// （古いものから消し、ClipboardGIF.keep 個まで残す）。progress に作っている進み具合（0〜1）を、
    /// 終えたら done に、入れられたか（false は失敗。知らせは呼ぶ側）を渡す
    @discardableResult
    static func copyGIF(
        _ url: URL,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
        done: @escaping (Bool) -> Void
    ) -> Task<Void, Never> {
        Task {
            do {
                let gif = try await ClipboardGIF.file(for: url, progress: progress)
                let data = try Data(contentsOf: gif)
                let item = NSPasteboardItem()
                item.setString(gif.absoluteString, forType: .fileURL)
                item.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([item])
                done(true)
            } catch {
                done(false)
                if !(error is CancellationError) {
                    AppAlert.inform("GIF を作れませんでした", detail: error.localizedDescription)
                }
            }
        }
    }

    /// MP4 で保存する（保存の設定に合わせる）
    static func saveMovie(_ url: URL, onSaved: @escaping () -> Void) {
        ImageSaver.saveFile(copying: url, suggestedName: url.lastPathComponent, kind: .movie, onSaved: onSaved)
    }

    /// GIF を作って保存する。progress に作っている進み具合（0〜1）を、作り終えたら（失敗・やめたときも）finished を渡す。
    /// 返す Task をやめると、作るのをやめる
    @discardableResult
    static func saveGIF(
        _ url: URL,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
        finished: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) -> Task<Void, Never> {
        let name = (url.deletingPathExtension().lastPathComponent as NSString).appendingPathExtension("gif") ?? "Pinshot.gif"
        return Task {
            do {
                let temporary = try await GIFExporter.exportToTemporaryFile(videoAt: url, progress: progress)
                finished()
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: temporary)
                    return
                }
                // 保存し終えたら（やめたときも）、作った一時ファイルを片付ける
                ImageSaver.saveFile(
                    copying: temporary,
                    suggestedName: name,
                    kind: .gif,
                    onSaved: onSaved,
                    onFinish: { try? FileManager.default.removeItem(at: temporary) }
                )
            } catch {
                finished()
                if !(error is CancellationError) {
                    AppAlert.inform("GIF を作れませんでした", detail: error.localizedDescription)
                }
            }
        }
    }

    /// 録画の大きさ（ポイント。画素の大きさを、いまの画面の倍率で割る）と長さ（秒）。読めなければ nil
    static func info(of url: URL) async -> (pointSize: CGSize, duration: TimeInterval)? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let duration = try? await asset.load(.duration) else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let seconds = duration.seconds.isFinite ? duration.seconds : 0
        return (CGSize(width: abs(natural.width) / scale, height: abs(natural.height) / scale), seconds)
    }

    /// 履歴から浮かせる（画面の真ん中に出す。もう浮かせていれば、前に出すだけ）。浮かせたら true、もう浮いていたら false
    static func play(_ url: URL) async -> Bool {
        if RecordingPlayer.bringToFront(url: url) { return false }
        let screen = NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = await info(of: url)?.pointSize ?? CGSize(width: 640, height: 400)
        // 読み込んでいる間に、ほかから浮かせていたら、増やさない
        if RecordingPlayer.bringToFront(url: url) { return false }
        RecordingPlayer.show(url: url, pointSize: size, around: NSRect(x: visible.midX, y: visible.midY, width: 0, height: 0), on: screen)
        return true
    }
}

/// クリップボードに入れる GIF の置き場所（~/Library/Caches/<アプリの ID>/ClipboardGIF）。
/// 貼り付けるまでファイルが要るので、一時フォルダではなくキャッシュに置く。同じ録画の GIF は作り直さずに使い回す
@MainActor
enum ClipboardGIF {
    /// 残しておく数（古いものから消す）
    static let keep = 10

    static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "app.nexy.Pinshot", isDirectory: true)
            .appendingPathComponent("ClipboardGIF", isDirectory: true)
    }

    /// url の録画の GIF（あれば使い回し、なければ作る）
    static func file(for url: URL, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> URL {
        let target = folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension("gif")
        if FileManager.default.fileExists(atPath: target.path) {
            // 使ったものを新しくしておく（古いものから消すため）
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
            return target
        }
        let temporary = try await GIFExporter.exportToTemporaryFile(videoAt: url, progress: progress)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        prune()
        return target
    }

    /// 古いものから消して、keep 個までにする
    private static func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
        for (file, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(keep) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
