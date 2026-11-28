import AppKit
import SwiftUI

/// 録画の一覧（履歴のウィンドウの「録画」）。日付ごとに並べる。
/// 表示方法は、撮った画像の一覧と同じ 3 つ（大きいサムネイル・小さいサムネイル・リスト。切り替えはウィンドウの上の帯）。
/// 選び方と下の帯は、ほかの一覧と同じ。GIF にして上げた録画には、印を出す
struct RecordingHistoryView: View {
    @ObservedObject var store: RecordingStore
    @ObservedObject var model: RecordingHistoryViewModel
    @ObservedObject var uploads = UploadHistory.shared
    @ObservedObject var settings = AppSettings.shared

    private var layout: HistoryLayout { settings.recordingHistoryLayout }

    var body: some View {
        if store.entries.isEmpty {
            HistoryEmptyState(
                symbol: "record.circle",
                title: "まだ録画はありません",
                message: "メニューバーの「録画」から録画すると、止めたときにここに並びます。残す期間・本数・容量は、設定の「履歴」で決められます。"
            )
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    content
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                }
                // 何もない所を押したら、選ぶのをやめる
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.clearSelection() })
                Divider()
                footer
            }
        }
    }

    // MARK: - 表示方法ごとの並べ方

    private var groups: [(day: Date, entries: [RecordingHistoryEntry])] {
        CaptureHistoryRules.groupedByDay(store.entries)
    }

    private var content: some View {
        HistoryDayGroupedList(groups: groups, layout: layout, unit: "本") { entry, compact in
            RecordingHistoryCell(entry: entry, model: model, compact: compact)
        } row: { entry in
            RecordingHistoryRow(entry: entry, model: model)
        }
    }

    // MARK: - 下の帯

    private var footer: some View {
        let selected = model.selectedEntries
        return HistoryFooter(
            selectedCount: selected.count,
            unit: "本",
            summary: store.summaryText,
            hint: "クリックで選ぶ（⌘・shift で複数）・ダブルクリックで浮かせて再生",
            removeAll: { store.confirmRemoveAll() },
            clearSelection: { model.clearSelection() }
        ) {
            HistoryFooterButton(title: "浮かせる", symbol: "play.rectangle") { model.play(selected) }
            // 録画の窓の操作バーと同じ並び（コピー・保存・共有リンク）。共有リンクは名前と印で見分ける
            HistoryFooterButton(title: "MP4 コピー", symbol: "film") { model.copyFiles(selected) }
                .help("動画（MP4）をクリップボードにコピー（ファイルとして貼り付けられる）")
            HistoryFooterButton(title: "GIF コピー", symbol: "photo.on.rectangle") { model.copyGIF(selected) }
                .help("GIF を作ってクリップボードにコピー（GIF の画像としても、ファイルとしても貼り付けられる）")
            HistoryFooterButton(title: "GIF 保存", symbol: "photo.on.rectangle") { model.saveGIF(selected) }
            HistoryFooterButton(title: UploadDestinations.current.map { "\($0.id.label) のリンク" } ?? "共有リンク", symbol: "link") { model.copyLink(selected) }
                .help("GIF にして上げ、共有リンク（URL）をコピー（上げてあれば、前のリンク）")
            HistoryFooterButton(title: "Finder", symbol: "folder") { model.revealInFinder(selected) }
            HistoryFooterButton(title: "削除…", symbol: "trash", role: .destructive) { model.remove(selected) }
        }
    }
}

// MARK: - 1 本

/// サムネイルで並べるときの 1 本。compact は小さいサムネイル（長さ・容量の表示を省く）
private struct RecordingHistoryCell: View {
    let entry: RecordingHistoryEntry
    @ObservedObject var model: RecordingHistoryViewModel
    var compact = false

    private var isSelected: Bool { model.selection.contains(entry.id) }
    private var isHovered: Bool { model.hovered == entry.id }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HistoryGridThumbnail(image: model.thumbnail(for: entry), compact: compact, isSelected: isSelected, isHovered: isHovered) {
                RecordingItemButtons(entry: entry, model: model, onImage: true)
            }
            .overlay(alignment: .bottomTrailing) { RecordingBadges(entry: entry, model: model).padding(6) }
            HStack(spacing: 6) {
                Text(CaptureHistoryRules.timeText(entry.date))
                    .font((compact ? Font.caption : Font.callout).monospacedDigit())
                Spacer(minLength: 4)
                if !compact {
                    Text(CaptureHistoryRules.byteText(Int(entry.bytes)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
        .modifier(RecordingItemInteractions(entry: entry, model: model))
        .help("\(entry.name)・ダブルクリックで浮かせて再生")
        .onAppear { model.load(entry) }
    }
}

/// リストで並べるときの 1 行（小さい縮小画像・時刻・長さ・容量・GIF の印・ボタン）
private struct RecordingHistoryRow: View {
    let entry: RecordingHistoryEntry
    @ObservedObject var model: RecordingHistoryViewModel

    private var isSelected: Bool { model.selection.contains(entry.id) }
    private var isHovered: Bool { model.hovered == entry.id }

    var body: some View {
        HStack(spacing: 12) {
            HistoryThumbnail(image: model.thumbnail(for: entry), size: CGSize(width: 72, height: 46), placeholder: "record.circle")
            Text(CaptureHistoryRules.timeText(entry.date))
                .font(.body.monospacedDigit())
                .frame(width: 48, alignment: .leading)
            Text(model.durationText(for: entry) ?? "—")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(CaptureHistoryRules.byteText(Int(entry.bytes)))
                .font(.caption)
                .foregroundStyle(.secondary)
            RecordingBadges(entry: entry, model: model, onImage: false)
            Spacer(minLength: 8)
            // 選んでいてもいつも出す（この行を選んでいれば、選んでいるものすべてに効く）
            RecordingItemButtons(entry: entry, model: model)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .historyRowBackground(isSelected: isSelected, isHovered: isHovered)
        .modifier(RecordingItemInteractions(entry: entry, model: model))
        .onAppear { model.load(entry) }
    }
}

/// 縮小画像の右下に出す印（長さと、GIF にして上げた印）
private struct RecordingBadges: View {
    let entry: RecordingHistoryEntry
    @ObservedObject var model: RecordingHistoryViewModel
    @ObservedObject var uploads = UploadHistory.shared
    var onImage = true

    var body: some View {
        HStack(spacing: 4) {
            if let upload = model.upload(for: entry) {
                badge(Label("GIF", systemImage: "link"))
                    .help("GIF にして \(upload.destination.label) に上げました（\(upload.link.pageURL.absoluteString)）。「リンク」で、このリンクをコピーできます")
            }
            if onImage, let duration = model.durationText(for: entry) {
                badge(Text(duration).monospacedDigit())
            }
        }
    }

    private func badge(_ content: some View) -> some View {
        content
            .font(.caption2.weight(.semibold))
            .foregroundStyle(onImage ? Color.white : Color.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(onImage ? Color.black.opacity(0.55) : Color.primary.opacity(0.08)))
    }
}

/// 1 本の、浮かせる・リンクをコピー・Finder で表示・削除のボタン（この 1 本を選んでいれば、選んでいるものすべてに効く）
private struct RecordingItemButtons: View {
    let entry: RecordingHistoryEntry
    @ObservedObject var model: RecordingHistoryViewModel
    var onImage = false

    var body: some View {
        HStack(spacing: 4) {
            HistoryHoverButton(symbol: "play.rectangle", help: "浮かせて再生", onImage: onImage) { model.play(model.targets(for: entry)) }
            HistoryHoverButton(symbol: "film", help: "動画（MP4）をクリップボードにコピー", onImage: onImage) {
                model.copyFiles(model.targets(for: entry))
            }
            HistoryHoverButton(symbol: "link", help: "GIF にして上げ、共有リンク（URL）をコピー（上げてあれば、前のリンク）", onImage: onImage) {
                model.copyLink(model.targets(for: entry))
            }
            HistoryHoverButton(symbol: "folder", help: "Finder で表示", onImage: onImage) { model.revealInFinder(model.targets(for: entry)) }
            HistoryHoverButton(symbol: "trash", help: "削除…", onImage: onImage) { model.remove(model.targets(for: entry)) }
        }
    }
}

/// 1 本ぶんの共通の操作（乗せる・クリック・ダブルクリック・右クリック）。どの表示方法でも同じにする
private struct RecordingItemInteractions: ViewModifier {
    let entry: RecordingHistoryEntry
    @ObservedObject var model: RecordingHistoryViewModel

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .trackingHover($model.hovered, id: entry.id)
            .onTapGesture(count: 2) { model.play(model.targets(for: entry)) }
            .simultaneousGesture(TapGesture().onEnded { model.click(entry, modifiers: NSEvent.modifierFlags) })
            .contextMenu { menuItems(model.targets(for: entry)) }
            .hoverRole()
    }

    /// 右クリック（選んでいれば、選んでいるものすべてに。1 本ずつの操作は、2 本以上では押せない）
    @ViewBuilder
    private func menuItems(_ targets: [RecordingHistoryEntry]) -> some View {
        let suffix = targets.count > 1 ? "（\(targets.count) 本）" : ""
        let single = targets.count == 1
        Button("浮かせて再生\(suffix)") { model.play(targets) }
        Divider()
        Section("クリップボードにコピー") {
            Button("動画（MP4）をコピー\(suffix)") { model.copyFiles(targets) }
            Button("GIF をコピー") { model.copyGIF(targets) }
                .disabled(!single)
        }
        Section("共有リンク（\(UploadDestinations.currentLabel)）") {
            Button(single && model.hasUploadedToCurrentDestination(targets[0]) ? "前に上げた GIF のリンクをコピー" : "GIF にして上げ、リンクをコピー") { model.copyLink(targets) }
                .disabled(!single)
        }
        Divider()
        Button("MP4 で保存…") { model.saveMovie(targets) }
            .disabled(!single)
        Button("GIF で保存…") { model.saveGIF(targets) }
            .disabled(!single)
        Button("Finder で表示\(suffix)") { model.revealInFinder(targets) }
        Divider()
        Button("削除…\(suffix)", role: .destructive) { model.remove(targets) }
    }
}
