import AppKit
import SwiftUI

// MARK: - マウスを乗せたときのカーソル

/// マウスを乗せた部品の種類。カーソルは部品ごとに直接書かず、種類で決める（アプリのすべての部品で、この決まりを使う）
enum HoverRole {
    /// 押せる・触って操作できる（ボタン・メニューを開くボタン・スライダー）
    case pressable
    /// ドラッグで動かせる（ツールバーのつまみ・画像・背景の余白）。ドラッグ中は閉じた手にする
    case movable
    /// 操作できない（無効のボタン・見出し・説明の文字）
    case inactive

    var cursor: NSCursor {
        switch self {
        case .pressable: .pointingHand
        case .movable: .openHand
        case .inactive: .arrow
        }
    }

    /// ドラッグしている間のカーソル（動かせる部品は閉じた手）
    var draggingCursor: NSCursor {
        self == .movable ? .closedHand : cursor
    }
}

/// マウスを乗せている間のカーソルの出し方
@MainActor
enum HoverCursor {
    /// 部品の上でマウスが動いた回数（離れたあとに、ほかの部品に乗ったかを見分ける）
    private static var activeCount = 0

    /// 部品の上でマウスが動いた（動くたびに出し直し、ほかのカーソル処理に上書きされないようにする）
    static func hovering(_ cursor: NSCursor) {
        activeCount &+= 1
        cursor.set()
    }

    /// 部品から離れた。隣の部品に乗り移ったときは、その部品のカーソルを消さないよう、
    /// 次の回まで待って、ほかの部品に乗っていなければ exit に戻す
    static func left(restoring exit: NSCursor) {
        let count = activeCount
        DispatchQueue.main.async {
            if activeCount == count { exit.set() }
        }
    }
}

extension View {
    /// マウスを乗せている間、部品の種類（role）に合ったカーソルにする（初期値は、押せる部品の指）。
    /// exit は離れたときに戻すカーソル（キャプチャ中のモードバーは、キャプチャ用のカーソルに戻す）
    func hoverRole(_ role: HoverRole = .pressable, exit: NSCursor = .arrow) -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active: HoverCursor.hovering(role.cursor)
            case .ended: HoverCursor.left(restoring: exit)
            }
        }
        // macOS も、マウスが動くたびに、ウィンドウのカーソルの範囲（cursor rect）に従ってカーソルを出し直す（範囲のない所は矢印）。
        // 上の出し直しだけだと、それと毎回取り合ってちらつくので、同じカーソルの範囲を部品の上に置いて、両方をそろえる
        .overlay(CursorRectArea(cursor: role.cursor))
    }
}

/// 部品の範囲に、AppKit のカーソルの範囲を置く（クリックやドラッグは、下の部品にそのまま通す）
private struct CursorRectArea: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorRectView {
        let view = CursorRectView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ view: CursorRectView, context: Context) {
        guard view.cursor !== cursor else { return }
        view.cursor = cursor
        view.window?.invalidateCursorRects(for: view)
    }
}

/// カーソルの範囲だけを持つビュー（マウスは受け取らない）
final class CursorRectView: NSView {
    var cursor: NSCursor = .arrow

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    // 大きさが変わったら、範囲を置き直す
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }
}

extension NSView {
    /// マウスの真下にあるウィンドウが、このビューのウィンドウか。
    /// ほかのウィンドウ（画像に重なったツールバーなど）の下にいるときは、カーソルを決めない
    var isWindowFrontmostUnderMouse: Bool {
        guard let window else { return false }
        return NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber
    }
}
