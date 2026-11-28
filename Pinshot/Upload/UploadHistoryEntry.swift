import Foundation

/// 上げたものの履歴の 1 件（画面やネットに関わらない。テストにも入れる）。
/// 一覧（uploads.json）と、小さな縮小画像（id の名前の PNG）を、アプリ用のフォルダに置く
struct UploadHistoryEntry: Codable, HistoryItem, Equatable {
    var id: UUID
    /// 上げた日時
    var date: Date
    /// 保存先に上げたファイル（消すときに使う）
    var remote: RemoteFile
    /// 共有リンク
    var link: SharedLink
    var kind: ExportKind
    /// 保存先に付けたファイル名
    var fileName: String
    /// 元の録画のファイル名（録画を GIF にして上げたとき。前の版の履歴にはない）。
    /// 録画は中身が変わらないので、同じ録画を同じ上げる先にもう一度上げるときは、作り直さずにこのリンクを使う
    var sourceName: String? = nil

    var destination: UploadDestinationID { remote.destination }

    /// 一覧に出す縮小画像のファイル名
    var thumbnailFileName: String { "\(id.uuidString).thumb.png" }
}

extension ExportKind: Codable {}

/// 上げたものの履歴の決まり
enum UploadHistoryRules {
    /// 一覧に残す数（超えた古いものは一覧から外す。上げる先からは消さない）
    static let limit = 1000

    /// 新しいものを先頭に足す（同じ ID のものがあれば置き換える）
    static func adding(_ entry: UploadHistoryEntry, to entries: [UploadHistoryEntry]) -> [UploadHistoryEntry] {
        [entry] + entries.filter { $0.id != entry.id }
    }

    /// sourceName の録画を上げた、いちばん新しいもの（entries は新しい順）。destination を渡すと、その上げる先に上げたものだけ。なければ nil
    static func latest(forSource sourceName: String, destination: UploadDestinationID? = nil, in entries: [UploadHistoryEntry]) -> UploadHistoryEntry? {
        entries.first { $0.sourceName == sourceName && (destination == nil || $0.destination == destination) }
    }

    /// 残す数を超えた古いもの（entries は新しい順）
    static func overLimit(_ entries: [UploadHistoryEntry], limit: Int = limit) -> [UploadHistoryEntry] {
        Array(entries.dropFirst(limit))
    }

    /// サムネイルの下に出す、短いリンク（例: 「gyazo.com/8980c524…」。https:// を外す）
    static func shortLink(_ url: URL) -> String {
        let host = url.host ?? ""
        let path = url.path
        return path.isEmpty || path == "/" ? host : host + path
    }
}
