import AppKit

/// 履歴の一覧のモデルに共通の選び方（クリック・⌘ + クリック・shift + クリック・⌘A・矢印キー・esc）と、操作の対象の決め方。
/// 画像・文字・録画・共有の一覧で同じにするため、ここにまとめる（選び方そのものは ListSelection、キーの決まりは ListKeys）
@MainActor
protocol HistoryListModel: AnyObject {
    associatedtype Entry: HistoryItem
    /// 一覧に並んでいるもの（並んでいる順。探す文字で絞っているときは、見えているものだけ）
    var listedEntries: [Entry] { get }
    var selection: ListSelection { get }
    /// 選んでいるものを変える（selection は外から書き換えられないようにしておき、ここだけを通す）
    func updateSelection(_ change: (inout ListSelection) -> Void)
}

extension HistoryListModel {
    /// 選んでいるもの（一覧に並んでいる順）
    var selectedEntries: [Entry] {
        listedEntries.filter { selection.contains($0.id) }
    }

    /// entry に対する操作の対象（entry を選んでいれば、選んでいるものすべて。そうでなければ entry だけ）
    func targets(for entry: Entry) -> [Entry] {
        selection.contains(entry.id) ? selectedEntries : [entry]
    }

    private var order: [UUID] { listedEntries.map(\.id) }

    /// クリックで選ぶ（⌘ で足す・外す、shift で起点からの範囲）
    func click(_ entry: Entry, modifiers: NSEvent.ModifierFlags) {
        let order = order
        updateSelection { $0.click(entry.id, command: modifiers.contains(.command), shift: modifiers.contains(.shift), order: order) }
    }

    /// id の 1 件だけを選ぶ（ほかの窓から「履歴で見る」で開いたときなど）
    func selectOnly(_ id: UUID) {
        let order = order
        updateSelection { $0.click(id, command: false, shift: false, order: order) }
    }

    func selectAll() {
        let order = order
        updateSelection { $0.selectAll(order) }
    }

    func clearSelection() {
        updateSelection { $0.clear() }
    }

    /// 一覧のキー操作。扱ったら true（扱わないキーは false で、ほかへ流す）。
    /// 選び方のキー（⌘A・矢印・esc）はここで扱い、選んでいるものへの操作（delete・return・⌘C）は、渡したものを呼ぶ
    /// （何も選んでいなければ扱わない）。horizontal・vertical は ListKeys.action と同じ
    func handleListKey(
        _ event: NSEvent,
        horizontal: Bool,
        vertical: Bool,
        remove: ([Entry]) -> Void,
        activate: ([Entry]) -> Void,
        copy: ([Entry]) -> Void
    ) -> Bool {
        guard let action = ListKeys.action(for: event, horizontal: horizontal, vertical: vertical) else { return false }
        let selected = selectedEntries
        switch action {
        case .selectAll:
            selectAll()
        case .move(let step, let extending):
            let order = order
            updateSelection { $0.move(by: step, extending: extending, order: order) }
        case .clearSelection:
            guard !selection.isEmpty else { return false }
            clearSelection()
        case .remove:
            guard !selected.isEmpty else { return false }
            remove(selected)
        case .activate:
            guard !selected.isEmpty else { return false }
            activate(selected)
        case .copy:
            guard !selected.isEmpty else { return false }
            copy(selected)
        }
        return true
    }
}
