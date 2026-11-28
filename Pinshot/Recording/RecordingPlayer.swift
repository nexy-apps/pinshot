import AppKit
import AVKit
import Combine
import SwiftUI

/// 録画を浮かせて、くり返し再生する窓（画像を浮かせるのと同じく、ほかのウィンドウより前に出す）。
/// 見た目は浮かせた画像にそろえる：動画の左上の外側に閉じるボタン（×）、動画の下に操作バー（黒い半透明の台）。
/// 操作バーから、再生・一時停止・好きな所へ動かす・音を出す、コピー（ファイルとして貼り付けられる）・GIF にして上げて共有リンクをコピー、
/// MP4 で保存・GIF で保存・Finder で表示、ができる（並びは浮かせた画像の操作バーにそろえる）
@MainActor
final class RecordingPlayer: NSObject, NSWindowDelegate {
    /// 開いている窓（閉じたら手放す）
    private static var players: [RecordingPlayer] = []

    /// 浮かせて再生している録画（古い録画を削除するときに、再生中のものは残す）
    static var openURLs: Set<URL> { Set(players.map(\.model.url)) }

    /// url の録画を浮かせていれば、その窓を前に出す（出したら true）
    static func bringToFront(url: URL) -> Bool {
        guard let player = players.first(where: { $0.model.url == url }) else { return false }
        player.panel.makeKeyAndOrderFront(nil)
        return true
    }

    /// url の録画を浮かせている窓を閉じる（履歴から録画を削除するとき）
    static func close(url: URL) {
        players.filter { $0.model.url == url }.forEach { $0.panel.close() }
    }

    /// すべての窓を閉じる（録画をすべて削除するとき）
    static func closeAll() {
        players.forEach { $0.panel.close() }
    }

    private let panel: OverlayPanel
    private let model: RecordingPlayerModel

    /// url の録画を、録画した範囲 around のあたりに浮かせる（大きいときは画面の 7 割に縮める）。
    /// copiesToClipboard なら、録画のファイルをクリップボードにも入れる（設定の「撮ったら（録画は止めたら）、クリップボードにもコピーする」）
    static func show(url: URL, pointSize: CGSize, around rect: NSRect, on screen: NSScreen?, copiesToClipboard: Bool = false) {
        let player = RecordingPlayer(url: url, pointSize: pointSize, around: rect, on: screen)
        players.append(player)
        player.panel.makeKeyAndOrderFront(nil)
        if copiesToClipboard { player.model.copy() }
    }

    private init(url: URL, pointSize: CGSize, around rect: NSRect, on screen: NSScreen?) {
        model = RecordingPlayerModel(url: url)
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let zoom = min(1, visible.width * 0.7 / max(pointSize.width, 1), visible.height * 0.7 / max(pointSize.height, 1))
        let videoSize = NSSize(width: pointSize.width * zoom, height: pointSize.height * zoom)
        // 窓の大きさは中身（動画・閉じるボタンの分の余白・操作バー）から決める（窓の背景は透明で、何もない所のクリックは下に通る）
        let hosting = FirstMouseHostingView(rootView: RecordingPlayerView(model: model, videoSize: videoSize))
        let size = hosting.fittingSize
        // 動画を録画した範囲の真ん中に合わせる（閉じるボタンの分の余白を除いて考える）
        let videoCenter = NSPoint(x: rect.midX, y: rect.midY)
        var origin = NSPoint(
            x: videoCenter.x - size.width / 2,
            y: videoCenter.y - (size.height - RecordingPlayerView.closeInset) + videoSize.height / 2
        )
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)

        panel = OverlayPanel(contentRect: NSRect(origin: origin, size: size), level: AppSettings.shared.alwaysOnTop ? .floating : .normal, hasShadow: false)
        super.init()
        model.close = { [weak self] in self?.panel.close() }
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
        Self.players.removeAll { $0 === self }
    }
}

/// 録画の窓の状態（再生・GIF を作っている途中・知らせ）
@MainActor
final class RecordingPlayerModel: ObservableObject {
    let url: URL
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper
    /// 再生しているか（開いたらすぐ再生し、最後まで行ったら頭に戻ってくり返す）
    @Published private(set) var isPlaying = true
    /// いまの位置と、録画の長さ（秒）
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    /// 録画に音が入っているか（読み込んでから決める。入っていなければ、音のボタンは押せない）
    @Published private(set) var hasAudio = false
    /// 音を消しているか（開いたらすぐ再生するので、初めは消しておく）
    @Published private(set) var isMuted = true
    /// GIF を作っている途中の進み具合（0〜1。作っていなければ nil）
    @Published private(set) var gifProgress: Double?
    /// GIF にして上げている途中か（終わるまで、上げるボタンは押せない）
    @Published private(set) var isUploading = false
    /// クリップボードに入れる GIF を作っている途中か
    @Published private(set) var isCopyingGIF = false
    /// 操作したあとの短い知らせ
    @Published private(set) var notice: String?
    /// 動画にマウスを乗せているか（乗せている間は、浮かせた画像と同じく細い白い枠を出す）
    @Published var isHoveringVideo = false
    var close: () -> Void = {}
    private var exportTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var statusObserver: AnyCancellable?
    /// 位置のつまみを動かしている間（いまの位置を、再生の位置で上書きしない）
    private var isScrubbing = false
    /// つまみを動かし始めたときに再生していたか（離したら、再生に戻す）
    private var resumesAfterScrub = false

    init(url: URL) {
        self.url = url
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: item)
        // 再生している位置を、操作バーの時間とつまみに出す（1 秒に 20 回）
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds.isFinite ? max(0, time.seconds) : 0
            }
        }
        statusObserver = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.isPlaying = status != .paused }
        Task { [weak self] in
            let asset = AVURLAsset(url: url)
            let hasAudio = (try? await asset.loadTracks(withMediaType: .audio).isEmpty == false) ?? false
            self?.hasAudio = hasAudio
            let duration = try? await asset.load(.duration)
            guard let seconds = duration?.seconds, seconds.isFinite else { return }
            self?.duration = seconds
        }
        player.play()
    }

    // MARK: - 再生

    /// 再生・一時停止を切り替える
    func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
    }

    /// 音を出す・消すを切り替える
    func toggleMute() {
        guard hasAudio else { return }
        isMuted.toggle()
        player.isMuted = isMuted
    }

    /// 位置のつまみを動かし始めた（動かしている間は止めておく）
    func beginScrub() {
        isScrubbing = true
        resumesAfterScrub = isPlaying
        player.pause()
    }

    /// seconds の位置を出す（つまみを動かしている間、動かすたびに呼ぶ）
    func scrub(to seconds: Double) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 位置のつまみを離した（動かし始める前に再生していたら、再生に戻す）
    func endScrub() {
        isScrubbing = false
        if resumesAfterScrub { player.play() }
    }

    /// 窓を閉じたとき（再生・GIF 作り・位置の見張りを止める）
    func stop() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObserver = nil
        exportTask?.cancel()
    }

    /// 動画（MP4）を、ファイルとしてクリップボードに入れる（Finder・チャットなどに貼り付けられる）
    func copy() {
        RecordingActions.copyFiles([url])
        show("動画（MP4）をコピーしました")
    }

    /// GIF を作って、クリップボードに入れる（GIF の画像としても、ファイルとしても貼り付けられる。同じ録画の GIF は作り直さない）
    func copyGIF() {
        guard !isCopyingGIF else { return }
        isCopyingGIF = true
        show(RecordingRules.gifMakingText(), sticky: true)
        exportTask = RecordingActions.copyGIF(
            url,
            progress: { [weak self] value in self?.show(RecordingRules.gifMakingText(progress: value), sticky: true) },
            done: { [weak self] copied in
                self?.isCopyingGIF = false
                self?.show(copied ? "GIF をコピーしました" : "GIF をコピーできませんでした")
            }
        )
    }

    func saveMovie() {
        RecordingActions.saveMovie(url) { [weak self] in self?.show("保存しました") }
    }

    /// GIF を作って保存する（作っている間は、進み具合を出す）
    func saveGIF() {
        guard gifProgress == nil else { return }
        gifProgress = 0
        show(RecordingRules.gifMakingText(), sticky: true)
        exportTask = RecordingActions.saveGIF(
            url,
            progress: { [weak self] value in
                self?.gifProgress = value
                self?.show(RecordingRules.gifMakingText(progress: value), sticky: true)
            },
            finished: { [weak self] in
                self?.gifProgress = nil
                self?.show("GIF を作りました（保存先を選んでください）")
            },
            onSaved: { [weak self] in self?.show("GIF を保存しました") }
        )
    }

    /// GIF にして上げ、共有リンクをコピーする（上げる先は設定の「共有」）。
    /// 大きすぎたら小さくして作り直す・上げられなかったら知らせるのは、UploadCenter が行う
    func uploadGIF() {
        guard !isUploading else { return }
        isUploading = true
        UploadCenter.shared.shareGIF(fromMovieAt: url) { [weak self] status in
            guard let self else { return }
            self.show(status.displayText, sticky: status.isWorking)
            if !status.isWorking { self.isUploading = false }
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 履歴のウィンドウの「録画」を開き、この録画を選ぶ（浮かせた画像の操作バーの「履歴」と同じ考え方）
    func openHistory() {
        CaptureHistoryWindowController.shared.show(tab: .recordings, selectingRecording: url)
    }

    /// 右クリックのメニュー（操作バーと同じ操作を、同じまとまりで並べる）
    func makeContextMenu() -> NSMenu {
        let symbol = MenuEntry.symbol
        let audioEntry: MenuEntry = hasAudio
            ? .item(title: isMuted ? "音を出す" : "音を消す", image: symbol(isMuted ? "speaker.wave.2" : "speaker.slash")) { [weak self] in self?.toggleMute() }
            : .disabled(title: "この録画には音が入っていません")
        let label = UploadDestinations.current?.id.label ?? "上げる先"
        // 上げてあれば、作り直さずに前のリンクをコピーする（UploadCenter.shareGIF）ので、そう書く
        let uploaded = UploadDestinations.current.flatMap { UploadHistory.shared.latestEntry(forSource: url.lastPathComponent, destination: $0.id) } != nil
        let uploadTitle = uploaded ? "前に \(label) に上げた GIF のリンクをコピー" : "GIF にして \(label) に上げ、リンクをコピー"
        return PopupMenu.makeMenu([
            .item(title: isPlaying ? "一時停止" : "再生", image: symbol(isPlaying ? "pause" : "play")) { [weak self] in self?.togglePlay() },
            audioEntry,
            .separator,
            // 録画そのものをクリップボードに入れる（MP4・GIF）と、上げて作る共有リンクを、見出しで分ける
            .header("クリップボードにコピー"),
            .item(title: "動画（MP4）をコピー", image: symbol("film")) { [weak self] in self?.copy() },
            isCopyingGIF
                ? .disabled(title: "GIF をコピー（作っています）")
                : .item(title: "GIF をコピー", image: symbol("photo.on.rectangle")) { [weak self] in self?.copyGIF() },
            .separator,
            .header("共有リンク（\(label)）"),
            isUploading
                ? .disabled(title: "\(uploadTitle)（上げています）")
                : .item(title: uploadTitle, image: symbol("link")) { [weak self] in self?.uploadGIF() },
            .separator,
            .header("保存"),
            .item(title: "MP4 で保存…", image: symbol("square.and.arrow.down")) { [weak self] in self?.saveMovie() },
            gifProgress == nil
                ? .item(title: "GIF で保存…", image: symbol("photo.on.rectangle")) { [weak self] in self?.saveGIF() }
                : .disabled(title: "GIF で保存…（作っています）"),
            .item(title: "Finder で表示", image: symbol("folder")) { [weak self] in self?.revealInFinder() },
            .separator,
            .item(title: "履歴…", image: symbol("clock.arrow.circlepath")) { [weak self] in self?.openHistory() },
            .separator,
            .item(title: "閉じる", image: symbol("xmark")) { [weak self] in self?.close() },
        ] + AccessibilityPermission.menuCaptureHint)
    }

    /// 短い知らせを出す（sticky なら、次の知らせを出すまで消さない。上げている途中など）
    private func show(_ text: String, sticky: Bool = false) {
        notice = text
        noticeTask?.cancel()
        guard !sticky else { return }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}

/// 録画の窓の中身。浮かせた画像と同じ見た目にする：動画の左上の外側に閉じるボタン（×）、
/// 動画の下（間 6pt）に黒い半透明の台の操作バー、乗せている間は動画に細い白い枠、知らせは動画の真ん中
private struct RecordingPlayerView: View {
    /// 閉じるボタン（直径 20）を、丸の縁が動画の角にほぼ触れるところに出すための余白（浮かせた画像と同じ置き方）
    static let closeInset: CGFloat = 18
    /// 動画と操作バーの間（浮かせた画像と同じ）
    static let barGap: CGFloat = 6

    @ObservedObject var model: RecordingPlayerModel
    let videoSize: NSSize

    var body: some View {
        VStack(spacing: Self.barGap) {
            video
            bar
        }
        // 閉じるボタンを、動画の左上の外側に出す分の余白（左右は同じにして、操作バーを動画の真ん中にそろえる）
        .padding(.top, Self.closeInset)
        .padding(.horizontal, Self.closeInset)
    }

    /// 動画（上をドラッグすると窓ごと動く。乗せている間は細い白い枠）
    private var video: some View {
        PlayerLayerView(player: model.player)
            .frame(width: videoSize.width, height: videoSize.height)
            .background(Color.black)
            // 浮かせた画像と同じく、動画にだけ影を付ける（操作バーには付けない）
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            // 動画の上をドラッグすると、窓ごと動く（動画の部品がマウスを受け取ってしまうため、上に重ねる）
            .overlay(dragArea.hoverRole(.movable))
            .overlay(Rectangle().strokeBorder(Color.white.opacity(model.isHoveringVideo ? 0.8 : 0), lineWidth: 1))
            .overlay { noticeView }
            .overlay(alignment: .topLeading) {
                RecordingCloseButton(action: model.close)
                    .frame(width: 20, height: 20)
                    .offset(x: -Self.closeInset, y: -Self.closeInset)
            }
            .onHover { model.isHoveringVideo = $0 }
    }

    /// 下の操作バー（浮かせた画像の操作バーと同じ色の台・同じボタン）。ボタンが多いので 2 行にする（1 行目は見る、2 行目は渡す）。
    /// 台の何もない所をドラッグしても、窓ごと動く
    private var bar: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 3) {
            playbackRow
            // 2 行の間のうすい線（台の端から端まで）
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 4)
            actionRow
        }
        .padding(3)
        .background(shape.fill(Color.black.opacity(0.6)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.25)))
        // 2 行目（渡す操作）の長さに合わせ、1 行目は再生の位置のつまみを伸ばして同じ幅にする
        .fixedSize()
        // 台の何もない所（縁まで）をドラッグしても、窓ごと動く（ボタン・つまみは、その上で押せる）
        .background(dragArea.clipShape(shape).hoverRole(.movable))
    }

    /// 1 行目（見る）: 動かすつまみ・再生 / 一時停止・時間・位置のつまみ・音
    private var playbackRow: some View {
        HStack(spacing: 2) {
            moveHandle
            QuickActionDivider()
            QuickActionButton(
                symbol: model.isPlaying ? "pause.fill" : "play.fill",
                help: model.isPlaying ? "一時停止" : "再生（最後まで行ったら、頭に戻ってくり返す）",
                action: model.togglePlay
            )
            Text("\(RecordingRules.elapsedText(model.currentTime)) / \(RecordingRules.elapsedText(model.duration))")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                // 長さが 10 分（上限）になっても、バーの幅が変わらないように
                .frame(width: 80)
            Slider(
                value: Binding(get: { model.currentTime }, set: { model.scrub(to: $0) }),
                in: 0...max(model.duration, 0.01),
                onEditingChanged: { editing in editing ? model.beginScrub() : model.endScrub() }
            )
            .controlSize(.mini)
            .tint(.white)
            // 2 行目の幅まで伸ばす（短くても 120）
            .frame(minWidth: 120, idealWidth: 120, maxWidth: .infinity)
            .padding(.horizontal, 4)
            .hoverHint("ドラッグで、見たい所へ動かす")
            .hoverRole()
            muteButton
        }
    }

    /// 2 行目（渡す）: コピー（MP4 | GIF）・保存（MP4 | GIF）・共有リンク・Finder で表示・履歴
    private var actionRow: some View {
        HStack(spacing: 2) {
            // 録画そのものを渡す（コピー・保存）は、どちらも「印 + MP4 | GIF」の枠だけの台にそろえる。
            // 共有リンクも、同じ枠だけの台にそろえる（リンクの印と、上げる先の名前で見分ける）
            formatPair(
                symbol: "doc.on.doc",
                mp4: ("動画（MP4）をクリップボードにコピー（ファイルとして貼り付けられる）", model.copy),
                gif: ("GIF を作ってクリップボードにコピー（GIF の画像としても、ファイルとしても貼り付けられる。音は入らない）", model.copyGIF),
                gifBusy: model.isCopyingGIF
            )
            formatPair(
                symbol: "square.and.arrow.down",
                mp4: ("動画（MP4）で保存（保存の設定に合わせる）", model.saveMovie),
                gif: ("GIF を作って保存（音は入らない。長い録画は、コマを減らして軽くする）", model.saveGIF),
                gifBusy: model.gifProgress != nil
            )
            linkButton
            QuickActionDivider()
            QuickActionButton(symbol: "folder", help: "Finder で表示", action: model.revealInFinder)
            QuickActionDivider()
            // 浮かせた画像の操作バーと同じく、右端に履歴を置く
            QuickActionButton(symbol: "clock.arrow.circlepath", help: "履歴（録画の一覧を開き、この録画を選ぶ）", action: model.openHistory)
        }
    }

    /// 動かすつまみ ✙（浮かせた画像の操作バーと同じく、左端に置く）。動画の上・バーの何もない所をドラッグしても動く
    private var moveHandle: some View {
        QuickActionMoveIcon()
            .overlay(dragArea)
            .hoverHint("ドラッグで録画の窓を移動（動画の上やバーの何もない所をドラッグしても動く）")
            .hoverRole(.movable)
    }

    /// ドラッグで窓ごと動かす部品（動画の上・バーの何もない所・✙ に重ねる）。右クリックで、操作バーと同じ操作のメニューを出す
    private var dragArea: WindowDragArea {
        WindowDragArea(menu: { model.makeContextMenu() })
    }

    /// 録画を MP4 か GIF で渡す台（枠だけの台に、何をするかの印と「MP4 | GIF」を並べる。コピーと保存で同じ形）。
    /// GIF は作るのに時間がかかるので、作っている間は「…」にして押せなくする（進み具合は、動画の上の知らせに出す）
    private func formatPair(
        symbol: String,
        mp4: (help: String, action: () -> Void),
        gif: (help: String, action: () -> Void),
        gifBusy: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.leading, 8)
                .padding(.trailing, 2)
            formatSegment("MP4", help: mp4.help, action: mp4.action)
            Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 12)
            formatSegment(gifBusy ? "…" : "GIF", help: gif.help, action: gif.action)
                .disabled(gifBusy)
        }
        .frame(height: 22)
        .background(Capsule().strokeBorder(Color.white.opacity(0.4)))
    }

    private func formatSegment(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHint(help)
        .hoverRole()
    }

    /// 上げる先（Gyazo）に GIF を上げて、共有リンクをコピー（コピー・保存と同じ枠だけの台に、リンクの印と上げる先の名前）
    private var linkButton: some View {
        let label = UploadDestinations.current?.id.label ?? "リンク"
        return Button(action: model.uploadGIF) {
            Label(label, systemImage: "link")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().strokeBorder(Color.white.opacity(0.4)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isUploading)
        .opacity(model.isUploading ? 0.5 : 1)
        .hoverHint("GIF にして \(UploadDestinations.current?.id.label ?? "上げる先") に上げ、共有リンク（URL）をコピー（上げる先は設定の「共有」。大きいときは小さくして上げる。音は入らない。2 回目からは、前に上げたリンクをコピー）")
        .hoverRole()
    }

    /// 音を出す・消す（音の入っていない録画では押せない。録画ごとにバーの幅が変わらないよう、いつも出しておく）
    private var muteButton: some View {
        QuickActionButton(
            symbol: model.hasAudio && !model.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
            help: model.hasAudio ? (model.isMuted ? "音を出す" : "音を消す") : "この録画には音が入っていません（録画の音は、範囲を選ぶ画面の下のバーか、メニューバーの「録画の音」で選ぶ）",
            action: model.toggleMute
        )
        .opacity(model.hasAudio ? 1 : 0.4)
    }

    /// 操作したあとの短い知らせ（浮かせた画像のお知らせと同じく、動画の真ん中に出す）
    @ViewBuilder
    private var noticeView: some View {
        if let notice = model.notice {
            Text(notice)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.7)))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

/// 閉じるボタン（浮かせた画像の左上の外側の × と同じ部品）
private struct RecordingCloseButton: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> PinCloseButton {
        let button = PinCloseButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        button.hint = "閉じる（録画は ~/Library/Application Support/Pinshot/Recordings に残る）"
        button.onClick = action
        return button
    }

    func updateNSView(_ button: PinCloseButton, context: Context) {
        button.onClick = action
    }
}

/// 動画だけを映す（再生の操作は出さない。くり返し再生する）
private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}
