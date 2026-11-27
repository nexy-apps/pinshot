import Foundation

/// アプリのデータを置くフォルダ（~/Library/Application Support/Pinshot）
///
/// フォルダの名前は Info.plist の PinshotDataFolderName（project.yml の PINSHOT_DATA_FOLDER_NAME）で決める。
/// 配る版は Pinshot、開発のビルド（ID が app.nexy.Pinshot.dev）は Pinshot Dev、更新の試験用アプリは PinshotUpdateTest。
/// Pinshot はサンドボックスを使わないので、分けないと、開発のビルドや試験用アプリが配る版の履歴や浮かせた画像を読み、
/// 自分の設定（残す期間・数）で消してしまうため。キーがないとき（古いビルド）は Pinshot
enum AppFolders {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    private static var folderName: String {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "PinshotDataFolderName") as? String, !name.isEmpty else {
            return "Pinshot"
        }
        return name
    }

    /// 撮った画像の履歴（読み取った文字の履歴も、ここに texts.json で置く）
    static var history: URL { root.appendingPathComponent("History", isDirectory: true) }

    /// 浮かせていた画像（終了・再起動のあとに戻す）
    static var pins: URL { root.appendingPathComponent("Pins", isDirectory: true) }

    /// 画面の録画（残す期間と数は、設定の「履歴」で決める。RecordingStore）
    static var recordings: URL { root.appendingPathComponent("Recordings", isDirectory: true) }

    /// 上げたものの履歴（共有リンクの一覧と、小さな縮小画像）
    static var uploads: URL { root.appendingPathComponent("Uploads", isDirectory: true) }
}
