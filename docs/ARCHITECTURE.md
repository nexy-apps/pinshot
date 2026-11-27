# コードの構成

```
Pinshot/
├── App/            起動と、アプリ全体に関わるもの
│   ├── AppDelegate           起動・グローバルショートカットの登録・更新の仕組みを始める・起動の記録（版と許可）
│   ├── AppActions            操作の入口（撮る・録る・浮かせる・履歴を開くなど）。ショートカットとメニューバーのメニューは、どちらもここを呼ぶ
│   ├── HotKey・ShortcutKeyTap  グローバルショートカット（Carbon）と、メニューを開いている間もショートカットを受けるキーの見張り
│   ├── StatusMenuController  メニューバーのアイコン（録画中・アップロード中・新しい版があるときで変える）とメニュー
│   ├── MenuBarIcon           メニューバーのカメラのアイコンと、新しい版があるときの印入りのもの（右下に下向きの矢印の丸。1 色）
│   ├── AppUpdates            更新の状態（使えるか・自動で確かめるか・知らせる新しい版）。更新そのものは AppUpdateService（アプリでは SparkleUpdater）が受け持つ（テストあり）
│   ├── SparkleUpdater        更新（Sparkle）。新しい版を確かめる・知らせる・入れ替える。Sparkle を読み込むのは、このファイルだけ
│   ├── DockIcon              設定・履歴などのウィンドウ（と Sparkle の更新の画面）を開いている間だけ、Dock にアイコンを出す
│   ├── AppInfo               記録（Logger の subsystem）と、版・ビルド番号の読み出し
│   └── AppSupport・AppRelauncher  メインメニュー・アプリのアイコン・⌘Q の扱い、起動し直し
├── Screenshot/     画面の撮影（ScreenCaptureKit）と範囲の選択
│   ├── CaptureController     撮る流れ（選ぶ → タイマー → 浮かせる）
│   ├── ScreenCapturer・WindowList  画面・ウィンドウを撮る、画面に出ているウィンドウの一覧
│   ├── CaptureTypes          モード・撮るもの・撮った画面などの型
│   ├── CaptureShield         ショートカットを押した瞬間に画面にかぶせる透明なウィンドウ（そのまま範囲を選ぶ画面になる）
│   ├── SelectionController   範囲を選ぶ画面（画面ごとのウィンドウ・モードの切り替え）
│   ├── SelectionView(+Drawing)  選ぶ操作（マウス）と、範囲・ルーペ・座標の描画
│   ├── CaptureModeBar・CountdownPanel  モードとタイマーを選ぶバー（SwiftUI）、タイマーの秒読み
│   └── CaptureCursors        キャプチャ中のカーソル
├── Recording/      画面の録画
│   ├── RecordingRules        録画の決まり（大きさを偶数に・座標・時間の表示・ファイル名・GIF のコマ数と大きさ・古い録画の整理・録画の音の選択肢 RecordingAudio。テストあり）
│   ├── ScreenRecorder        画面（と Mac の音・マイクの音）を受け取って MP4 に書く（ScreenCaptureKit の SCStream → AVAssetWriter。両方の音のときは、止めたあとに AudioMixdown で 1 本に混ぜる）
│   ├── RecordingController   録画を始める・止める入口（赤い点線の枠・操作パネル・上限）
│   ├── RecordingStore        アプリの中に残す録画（期間・数・容量の上限で古いものを削除・本数と容量）
│   ├── RecordingPlayer       録画を浮かせてくり返し再生する窓（見た目は浮かせた画像にそろえる：左上の外の ×・下の操作バーと左端の ✙。再生・一時停止・位置のつまみ・音を出す / 消す | コピー・GIF にして上げる | MP4 / GIF で保存・Finder で表示）
│   ├── MicrophoneCapture     マイクの音を受け取る（AVCaptureSession。時刻を画面のコマと同じホストの時計に直す）
│   ├── AudioMixdown          Mac の音とマイクの 2 本の音を 1 本に混ぜて書き直す（映像はそのまま。テストあり）
│   ├── GIFExporter           録画から GIF を作る（テストあり）
│   └── CaptureOutline        録画している範囲の外側の赤い点線の枠（録画には写らない）
├── Pin/            最前面に浮かぶウィンドウと、画像の表示・操作
│   ├── PinManager            浮かせている画像の一覧（閉じた画像を戻す・すべて閉じる・終了後も戻すための保存と復元 など）
│   ├── SavedPin・PinSessionStore  終了・再起動のあとも戻す状態（1 枚ずつ読む・形の番号。テストあり）と、その保存先（~/Library/Application Support/Pinshot/Pins に PNG と session.json。読めないところがあれば unreadable-日時 のフォルダに残す）
│   ├── PinController(+◯◯)    画像 1 枚ぶんの操作（拡大縮小・不透明度・編集モード）。+Export はコピー・保存、+Menu は右クリックメニュー
│   ├── PinPanel・PinAppearance  画像のウィンドウ、画像の不透明度と拡大率（操作バーとツールバーで同じ値を見る）
│   ├── PinToolbarController  編集ツールバーのウィンドウ（出す・置く場所・つまみで動かす）
│   ├── PinCanvasView(+◯◯)    画像と書き込みの表示と操作。役割ごとにファイルを分けている
│   │                         （+Cursor・+Mouse・+Keyboard・+Selection・+History・+Text・+TextRecognition・+TextMark・+Outside）
│   ├── PinAccessory          部品を画像の外に出す子ウィンドウ（閉じるボタンと操作バーはいつも。ほかは画像が小さくて中に入らないとき）
│   ├── PinBackdropView       画像のまわりの背景（余白・影）
│   ├── QuickActionBar・PinCloseButton  画像の下の操作バー（編集中はツールバーの上のバーとしても使う）と選んだ書き込みのバー、左上の外の閉じるボタン
│   ├── HUDView・HintBubble   「コピーしました」などのお知らせ、ボタンの説明のポップアップ（HoverHints。Pinshot が前面になくても出る。操作バー・編集ツールバー・録画の窓など、どのバーも .hoverHint で出す）
│   ├── TextScanOverlay・RecognizedTextPopover  文字を読み取っている間・読み取ったあとの見た目と、読み取った文字の吹き出し（直してコピーし直せる）
│   └── ResizeEdges           端のドラッグで大きさを変える計算（テストあり）
├── Upload/         アップロードして共有リンク（いまは Gyazo。ほかの保存先を足せるように分けてある）
│   ├── UploadTypes・UploadRules  保存先の種類・できること・上げたファイル・共有リンク・コピーする形・失敗の知らせ、コピーする文・ファイル名・トークンらしさ・multipart の本文（テストあり）
│   ├── UploadDestination     保存先の protocol（上げる・共有リンク・消す・ログアウト）と、使える保存先の一覧
│   ├── UploadCenter          どの保存先でも同じ流れ（上げる → リンク → コピー → 履歴 → 知らせる・進み具合・自動で上げる）と、録画を GIF にして上げる流れ（大きすぎたら小さく作り直す）
│   ├── UploadHistoryEntry・UploadHistory  上げたものの 1 件と決まり（テストあり）、その保存（~/Library/Application Support/Pinshot/Uploads に一覧の JSON と縮小画像。新しい 1000 件まで）
│   ├── UploadHTTP・UploadNotifier  通信と返事の番号の読み替え・送った割合、macOS の通知
│   ├── Destinations/GyazoDestination  Gyazo（利用者が貼ったアクセストークンで上げる・消す）
│   └── OAuth/                OAuth 2.0 の共通の部品（PKCE・ログインの画面・localhost の受け口・許可証の取り直し・キーチェーン）。いまは使う保存先がないが、ほかの保存先を足すときに使う（テストあり）
├── History/        撮った画像・読み取った文字・上げたものの履歴
│   ├── CaptureHistoryEntry   履歴の 1 枚と、残し方（期間・数）・日付ごとのまとめ方・表示の文字の決まり（テストあり）。期間と日付は文字の履歴にも使う
│   ├── CaptureHistory        画像の履歴の保存と読み込み（~/Library/Application Support/Pinshot/History に PNG・縮小画像・一覧の JSON）
│   ├── TextHistoryEntry・TextHistory  読み取った文字の履歴の 1 件と決まり（同じ文字はまとめる・探す。テストあり）と、その保存（同じフォルダに texts.json と、読み取った範囲の画像）
│   ├── ListSelection         一覧の選び方（クリック・⌘・shift・⌘A・矢印）と、キー操作の決まり（ListKeys）。画像・文字・共有の一覧で同じ（テストあり）
│   ├── CaptureHistoryWindowController・HistoryWindowView  履歴のウィンドウ（開くときに編集中の画像の編集を終える・キー操作の振り分け）と、その中身（上の「画像 / 文字 / 共有」の切り替え・表示方法・探す欄）
│   ├── CaptureHistoryViewModel・CaptureHistoryView  画像の一覧（複数選択・浮かせる・コピー・保存・消す）
│   ├── TextHistoryViewModel・TextHistoryView  文字の一覧と右の全文の欄（探す・複数選択・コピー・消す・直す・読み取った画像を浮かせる）
│   ├── UploadHistoryViewModel・UploadHistoryView  上げたものの一覧（撮った画像と同じ 3 つの表示・複数選択・リンクをコピー・ブラウザで開く・Gyazo からも削除）
│   ├── HistoryComponents     画像・文字・共有の一覧で同じ部品（日付ごとの並べ方（サムネイル・リスト）・日付の見出し・空のときの案内・小さな画像・サムネイルの 1 件と列・行の背景・乗せたときのボタン・下の帯）
│   └── HistoryNotice         一覧の下に出す短い知らせ（「コピーしました」など。アップロードの途中は消さずに出す）
├── Editor/         書き込みのデータ、描画、書き出し
│   ├── Annotation・AnnotationStyles・Tool・ToolGroup・RGBAColor   書き込みのデータ（Windows 版と形式をそろえる）と、ツールの組
│   ├── AnnotationRenderer・ImageEffects・ImageExporter 描画・モザイクとぼかし・書き出し
│   ├── TextRecognizer        文字の読み取り（Vision）と、読み取った文字を読む順に並べる決まり（テストあり）
│   ├── TextMarkLayout        文字マーカーを、ドラッグした所の文字に合わせて行ごとの四角にする決まりと、その形・画素を見て文字の線がある高さに合わせる処理（TextInk）（テストあり）
│   ├── AnnotationDocument    1 枚の画像の編集データ（書き込み・トリミング・元に戻す履歴）。変えるときは必ずここを通す
│   ├── EditHandle            選んだ書き込みのつまみ（形を直す）
│   ├── EditorState・EditorStyle・StylePreset・EditHistory  編集の状態・スタイルの保存・元に戻す
│   └── Toolbar/              ツールバー（SwiftUI）と、その部品
│       ├── EditorToolbar(+Options)・ToolbarComponents・ToolbarMenuButtons  ツールバー本体（+Options は 2 行目のツールごとのオプション）、共通の部品、メニューを開くボタン
│       ├── TextStylePreview  文字ツールのオプションの見本（書き込みと同じ描き方で、次に入力する文字の見え方を出す）
│       ├── ViewControls      不透明度と拡大率（操作バーに出す。編集中もツールバーの上のバーとして同じ操作バーを出す）
│       └── FontMenu・TextInputController・ColorPanelController  フォントのメニュー、数字や名前の入力欄、カラーパネル
├── Assets.xcassets/ アプリのアイコン（scripts/make-app-icon.swift で描いて書き出す）
├── Licenses/       アプリに同梱するライセンス（Sparkle.txt。make が、取り寄せた Sparkle の配布物から写す）
├── Settings/       設定の値（AppSettings・Shortcut・ExportDecoration）と画面
│   ├── SettingsWindowController  設定のウィンドウ（タブ）
│   ├── General・Pin・Export・History・Share・ShortcutSettingsView   タブごとの画面
│   ├── GyazoSetupView        Gyazo につなぐまでの案内の窓（アプリの登録 → トークンを作る → 貼ってつなぐ）
│   ├── SettingsComponents    設定の画面の共通の部品（枠・説明の文字・選択肢の Picker）
│   └── WelcomeView           使い方と許可の案内
└── Support/        どこからも使う部品
    ├── OverlayPanel          枠のない、前面を奪わないパネルの土台
    ├── PopupMenu・OpenMenus  項目の並びからメニューを作る、開いているメニューを覚えて閉じる
    ├── AppAlert              確かめる・知らせるダイアログ（アプリのアイコン・ウィンドウのシート）
    ├── ScreenGeometry        画面の座標の変換・部品を画面に収める位置・ツールバーと操作バーを画像の下に置く位置・操作パネルを置く位置（テストあり）
    ├── Permissions           画面収録・アクセシビリティの許可
    ├── GraphicsHelpers       画像の描き先を作る・画像のファイルを読む（読んだ時点で展開する。あとでファイルが消えても描ける）・縮める
    ├── EditableText          直せる文字の欄（右クリックは、短い日本語のメニューと、呼ぶ側が足す項目）
    ├── HoverCursor           部品の種類（押せる・動かせる・操作できない）で決めるカーソル
    ├── KeyCode・PercentText  キーの番号の名前、「80%」の表示
    ├── ImageSaver            PNG と録画のファイルを設定に合わせて保存する（浮かせた画像・履歴・録画から使う）
    ├── AppFolders            アプリのデータを置くフォルダ（履歴・浮かせていた画像・録画・上げたもの。名前は Info.plist の PinshotDataFolderName で、開発のビルド・更新の試験用アプリは別のフォルダ）
    ├── StoredJSON            そのフォルダに置く一覧の JSON の読み書き（1 件ずつ読み、読めないものだけ飛ばす。そのときは元のファイルを別名で残し、上書きで失わない。テストあり）
    ├── SaveLocation          保存したもの（画像・GIF・動画）を置く場所の決まり（保存先の中を種類ごと・月ごとに分ける。テストあり）
    └── ViewHelpers           前に出ていなくても押せるビュー・マウスの追跡・角の丸い枠（framedBox）・ドラッグで窓を動かす所（WindowDragArea）

PinshotTests/       画面に関係ない処理のテスト（make test）

scripts/            ビルドと配る手順の道具（Makefile から使う）
├── create-signing-cert.sh   開発用の証明書（nexy Dev Signing）をログインキーチェーンに作る（make cert）
├── vault.sh                 金庫を開けてコマンドを流し、必ず閉める（make dist・make publish）
├── signing-check.sh         配る版用の証明書が使えるか・アプリがその証明書で署名されたかを、指紋（SHA-1）で確かめる（make dist）
├── make-appcast.sh          更新ファイル（zip）に署名して、版の一覧（appcast.xml）を作る（make publish・make update-test）
├── publish-check.sh         公開の前に、Git の状態・タグと更新の鍵を確かめる（make publish）
├── update-test.sh           更新を手元で通しで試す準備をする（make update-test。update-test-key.swift は、その試験用の鍵を作る）
├── update-test-log.sh       更新の試験のあいだの macOS の記録を書き出す（make update-test-log）
├── make-app-icon.swift      アプリのアイコンをコードで描いて、Assets.xcassets に書き出す（make icon）
├── readme-images/           README の絵を作る（make readme-images）
└── release-*.md             リリースの説明（β 版の注意・この版の変更・ダウンロードと開き方。make publish がつなげる）

.githooks/          git hooks（push の前に make test を流す。make setup で有効にする）
Vendor/Sparkle/     更新の仕組み（Sparkle）の配布物。make が取り寄せるので、リポジトリには入れない
```

## 設計のメモ

- 書き込みの座標は「元の画像のポイント座標（左上が原点）」で持ち、拡大縮小・トリミングしても変わらない
- 書き込み・トリミング・元に戻す履歴は `AnnotationDocument` が持つ。変更は必ずそのメソッドを通し、「元に戻すに積む」「番号を詰める」などの決まりをそこで守る
- 浮かせた画像やツールバーは、クリックしても前面を奪わないパネル（`OverlayPanel`）で作る。アプリ全体を前に出すと、ほかの浮かせた画像まで前に出てしまうため
- カーソル（`HoverRole`）・キーの番号（`KeyCode`）・画面に収める位置（`ScreenGeometry`）・背景の描き方（`ExportDecoration`）・ダイアログ（`AppAlert`）は、部品ごとに直接書かず、共通の部品を使う
- テスト（`PinshotTests/`）は、アプリを起動せずに動く。画面に関係ないソースを、テストのターゲットに直接入れている（`project.yml`）
- 保存する形（書き込みの種類・項目の名前）を変えると、前の版が残したものを読めなくなる。`StoredFormatTests` に、いまの版が書いた JSON を決まった文字列で持っているので、形を変えるときは前の形を読み替えて引き継ぎ、そのテストの JSON は書き換えない（新しい形のテストを足す）。浮かせていた画像の形を前の版で読めないように変えたら、`SavedPinSession.currentVersion` を増やす

### 署名

- 決まりの全体は、共通のノート「Pinシリーズの決まり」（アプリの ID・証明書・金庫・アドホック署名の扱い）。ここには Pinshot での形だけを書く。Pinshelf と同じ形
- macOS は、画面収録・アクセシビリティ・マイクの許可を、アプリの「同じアプリ」の条件（designated requirement）にひも付けて覚える。アドホック署名は、条件が中身のハッシュなので、ビルドし直すたび・版が変わるたびに別のアプリと見なされ、許可が外れる。決まった自己署名の証明書で署名すると、条件は「アプリの ID ＋ 証明書」になり、版が変わっても同じアプリと見なされる
- ID と証明書は、使い道で分ける

  | 使い道 | ID | 画面の名前 | データのフォルダ | 証明書 |
  |---|---|---|---|---|
  | 配る版（`make dist`・`make publish`） | `app.nexy.Pinshot` | Pinshot | `Pinshot` | `nexy Release Signing`（作者の金庫の中） |
  | 開発のビルド（`make run`・`make install`） | `app.nexy.Pinshot.dev` | Pinshot Dev | `Pinshot Dev` | `nexy Dev Signing`（各自のログインキーチェーン。`make cert`） |
  | 更新の試験（`make update-test`） | `app.nexy.Pinshot.updatetest` | Pinshot UpdateTest | `PinshotUpdateTest` | `nexy Dev Signing` |
  | テスト（`make test`） | `app.nexy.Pinshot.tests` | — | — | `nexy Dev Signing` |

- ビルドの設定は `project.yml` の 3 つ。Debug（`make build`・`make run`）、Install（`make install`。Release と同じ最適化で、ID・名前・データのフォルダ・証明書・空の公開鍵は Debug と同じ。YAML のアンカーで Debug と共有する）、Release（`make dist`）。Pinshot はサンドボックスを使わないので、データのフォルダ（`~/Library/Application Support/<名前>`）を Info.plist の `PinshotDataFolderName` で分ける（`AppFolders`）。分けないと、開発のビルドが配る版の履歴・浮かせた画像を読み、自分の設定（残す期間・数）で消してしまう
- 開発のビルド・テスト・アイコンや README の画像を作る道具も、開発用の証明書で署名する。証明書がなければ止まって `make cert` を案内し、`ADHOC=1` を付けたときだけアドホック署名にする（`1` だけを受け付ける。配る版には効かない）。`make build`・`make install` は、ビルドのあとに想定の署名になったかを `codesign -dvv` で確かめる（開発用の証明書は人ごとに違うので、名前で見る）
- 配る版用の証明書と、更新ファイルの署名の鍵（Sparkle・アカウント名 `nexy-release`）は、作者の Mac の鍵付きのキーチェーン（金庫。`~/Library/Keychains/nexy-release.keychain-db`）に入れる（Pin シリーズで共通。作者が Pinshelf の `scripts/create-nexy-keys.sh` で一度だけ作った）。金庫はふだん閉まっていて、検索リストにも入れない（閉まった金庫をほかのプログラムが探すと、パスワードの画面が出るため）。`make dist`・`make publish` は `scripts/vault.sh` を通して、その場でパスワードを聞いて開け、開けている間だけ検索リストに入れ（Xcode は、検索リストにない箱の証明書を `--keychain` を渡しても見つけられない）、終わったら（失敗や control + C でも）閉めて検索リストを戻す
- 証明書は名前ではなく指紋（SHA-1）で確かめる。名前は誰でも同じものを作れるため。`make dist` は、署名の前に金庫の証明書の指紋が `project.yml` の Release の `CODE_SIGN_IDENTITY`（Xcode もこの指紋で証明書を選ぶ）と合うか、署名のあとにアプリがその証明書で署名されたかを確かめる（`scripts/signing-check.sh`）。金庫が開いていないと、Release のビルドは「No certificate matching …」で止まり、アドホック署名にはならない
- Apple の Developer ID は使わず、公証も受けていない（初めて開くときに「このまま開く」が要る）
- Hardened Runtime は切っている（`ENABLE_HARDENED_RUNTIME = NO`）。埋め込んだ Sparkle は、Xcode が本体だけを証明書で署名し直し、中の部品（`Autoupdate`・`Updater.app`・XPC サービス）は配布物のアドホック署名のまま。Hardened Runtime とライブラリの検証を使っていないので、このまま動く（`codesign --verify --deep --strict` も通る）
- 配る版（Release）と `make install`（Install）には、デバッガをつなぐための許可（`get-task-allow`）を入れない（`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`。何もしないと、Xcode がビルドのときに足す）
- 2026-11 に、ID（前は `dev.portfolio.pinshot`）と署名（前は `yzanbo Code Signing`。その前の 0.4.1 まではアドホック署名）を改め、0.1.0 から出し直した（前の版からは更新しない）

### 更新

Developer ID に登録しない前提で、[Sparkle](https://sparkle-project.org) 2 を使う（Pinshelf と同じ形。検討の経緯は、Pinshelf のノート「更新の仕組みの方針」にまとめてある）。

- **取り込み方**: 公式の配布物（`Sparkle.framework` と道具）を `make` が取り寄せ、決めてある SHA-256 と合うことを確かめて `Vendor/Sparkle` に置く。Swift パッケージにしないのは、取り寄せる版と中身を固定し、道具（`generate_appcast` など）も同じ配布物から使うため。Sparkle の版を上げるときは、`Makefile` の `SPARKLE_VERSION` と `SPARKLE_SHA256` を一緒に変える
- **本物かの確かめ**: 更新ファイル（zip）は、作者の EdDSA の鍵で署名する。アプリには公開鍵（`SUPublicEDKey`。`project.yml` の `PINSHOT_UPDATE_PUBLIC_KEY`）を入れ、Sparkle が署名を確かめてから入れ替える。鍵は Pin シリーズで共通で、秘密鍵は作者の金庫の中にあり、`generate_appcast` が版の一覧を作るときに zip に署名する（`sign_update` は使わない）。公開鍵の入っていないビルド（開発のビルド。`project.yml` の Debug と Install は空にする）では、更新の機能を出さない（`SparkleUpdater.start` が nil を返す。配る版を「新しい版」と見て入れ替えないように）
- **「このまま開く」が要らない理由**: Sparkle が自分でダウンロードして確かめた版からは、ダウンロードのしるし（quarantine）を外す。だから、更新で入れた版は Gatekeeper に止められない
- **許可が外れない理由**: どの版も同じ証明書で署名しているので（上の「署名」）、入れ替えた版も同じアプリと見なされる。リリースの前に `make update-test` で確かめる（docs/TESTING.md）
- **サンドボックス**: Pinshot は使っていないので、Sparkle の入れ替え役（XPC サービス）も、ネット接続などの許可（entitlements）も要らない（Pinshelf はサンドボックスのため、どちらも足している）
- **知らせ方**: メニューバーに常駐するアプリなので、自動で見つけた新しい版は画面に割り込ませず、アイコンの印とメニューで知らせる（Sparkle の「控えめな知らせ」の作法。`standardUserDriverShouldHandleShowingScheduledUpdate` で、いつも自分で受け持つ）。メニューから選ぶと、Sparkle の更新の画面が前面に出る。知らせの決まりは Pin シリーズ共通（Pinshelf のノート「更新の仕組みの方針」の 8 の節）
- **確かめる間隔**: 1 時間に 1 回（`SUScheduledCheckInterval` 3600。Sparkle が受け付けるいちばん短い間隔で、VS Code と同じ）。起動したときは、前に確かめてから 1 時間以上たっていれば、すぐ確かめる。版の一覧は小さな XML 1 つなので、1 時間ごとでも GitHub への負担は小さい
- **印の形**: カメラのアイコンの右下を丸く切り抜き、下向きの矢印を抜いた丸を置いたものに替える（`MenuBarIcon`）。テンプレート画像のままにして、色は付けない（メニューバーの色付きの点は、マイク・カメラの使用中の印と紛れやすい）。Pinshelf は丸を直径 10pt にしているが、Pinshot でそうするとカメラのレンズが欠けるので、直径 8.4pt にした（PNG に書き出して見比べた）。録画中・アップロード中は、それぞれのアイコンを出し、終わってから印入りに戻す
- **印を消すとき**: 印は「まだ入れていない新しい版がある」の意味で、入れるか飛ばすまで出しておく（VS Code・Chrome と同じ考え方）。Sparkle の説明書は「画面を見てもらったら印を消す」作り（`standardUserDriverDidReceiveUserAttention`）を勧めるが、それだと更新の画面を開いて「あとで通知」で閉じただけで消え、次に自動で確かめるまで戻らないので使わない。見つけた版とビルド番号を `UserDefaults` に保存し（`AppUpdates`）、起動したときに今の版より新しければ印を戻す（終了しても消えないように）。消すのは、利用者が「このバージョンはスキップ」を選んだとき（`updater(_:userDidMake:forUpdate:state:)` の `.skip`）・確かめ直して新しい版がなかったとき（`updaterDidNotFindUpdate`。通信の失敗では呼ばれない）・入れて今の版が同じか新しくなったとき。Sparkle の受け口は任意のメソッドで、Swift での名前を間違えてもエラーにならず呼ばれないだけなので、`#selector(SPUUpdaterDelegate.updater(_:userDidMake:forUpdate:state:))` のような型検査で確かめた
- **Dock**: 更新の画面は Sparkle のウィンドウで、開け閉めを自分では知れないので、確かめ始めてから確かめ終えるまで、名前付きの印で Dock に出しておく（`DockIcon.hold`・`release`）
- **確認中の小窓の長さ**: 問い合わせはすぐ終わり、「アップデートを確認中…」の小窓が一瞬で閉じてちらついて見えるので、Sparkle の標準の画面（`SPUStandardUserDriver`）を `PacedUserDriver` で包み、小窓を少なくとも 0.5 秒は出してから結果の画面に渡す（そのため `SPUStandardUpdaterController` ではなく、`SPUUpdater` を自分で作る）
- **画面の側との分け方**: Sparkle を読み込むのは `SparkleUpdater` だけ。メニューと設定は `AppUpdates`（状態）を通して使う。Sparkle なしでアプリのコードをビルドする `make readme-images` と、テストのため
- **版の一覧**: `appcast.xml` は、組織 nexy-apps の GitHub Pages のリポジトリ（[nexy-apps.github.io](https://github.com/nexy-apps/nexy-apps.github.io)）の `pinshot/appcast.xml` に置き、アプリは `https://nexy-apps.github.io/pinshot/appcast.xml` から読む（`SUFeedURL`。配ったあとは変えない。のちに独自のドメインを付けても、GitHub Pages が同じ道筋のまま転送し、Sparkle は転送をたどる）。アプリのリポジトリには置かない。β 版は GitHub の「最新の版」に出ないので、Releases の latest は使えない。載せるのは、いちばん新しい版だけ。この版の変更（`scripts/release-changes.md`）を、Markdown のまま埋め込む
- **版の比べ方**: Sparkle は `CFBundleVersion`（ビルド番号）で新旧を比べる。出すたびに必ず上げる
- **記録**: 起動のたびに、版・画面収録とアクセシビリティの許可・「ログイン時に起動」を、macOS の記録に 1 行残す（`AppDelegate.logLaunch`。subsystem は `app.nexy.Pinshot`）。入れ替えのあとに許可が引き継がれたかを、あとから確かめられる
- **試験用アプリ**: `make update-test` は、別の ID（`app.nexy.Pinshot.updatetest`）・別の名前・別のデータのフォルダ（Info.plist の `PinshotDataFolderName`。`AppFolders`）で作り、開発用の証明書で署名する。Gyazo の許可証のキーチェーンの名前は、アプリの ID から作るので（`KeychainTokenStore`。配る Pinshot では `app.nexy.Pinshot.upload`）、開発のビルド・試験用アプリでは自然に分かれる
- **ライセンス**: Sparkle のライセンス（MIT など）は、配るものに全文を含める決まり。`Pinshot/Licenses/Sparkle.txt` として同梱する（`make` が、取り寄せた配布物から写す）

### 版とリリース

- 版（`CFBundleShortVersionString`）とビルド番号（`CFBundleVersion`）は `project.yml` で決める。出すたびに両方を上げ、`scripts/release-changes.md`（この版の変更）を書き直す
- `make publish BETA=1` で β 版としてプレリリースにする（タグは `v<版>-beta.1`。説明の先頭に `scripts/release-notes-beta.md` の注意が付く）。正式版は `BETA` を付けずに `make publish`
- `make publish` は、先にコミット済みで GitHub の main と同じか・タグがまだないかを確かめ（`scripts/publish-check.sh git`）、版の一覧の置き場所を `build/appcast-site` に取り寄せてから、金庫を開け、金庫の更新の鍵が `project.yml` の公開鍵と合うかを確かめる（`publish-check.sh key`）。そろっていなければ何も作らずに止まる。そのあと、DMG と zip を作り、`build/appcast-site` の `pinshot/appcast.xml` を作り直し、Release を作ってから、版の一覧をコミットしてプッシュする（アプリのリポジトリの main には何も送らない）。版の一覧に署名するとき、Mac が画面で金庫のパスワードをもう一度聞く（金庫は開いているが、更新の鍵を確認なしに使ってよい道具に `generate_appcast` が入っていないため。「許可」で進める）。Release は `gh` に `--repo nexy-apps/pinshot` を渡して作る（手元には写しの `yzanbo` など、送り先がほかにもあるため）
- 更新ファイルの署名の鍵（EdDSA）は Pin シリーズで共通の 1 本で、作者の金庫の中にある。失くすと更新を届けられなくなるので、控えを Mac の外に保管してある（決まりは共通のノート「Pinシリーズの決まり」）
- テストは手元だけで流す（GitHub Actions では流さない）。`make setup` で git hooks（`.githooks/pre-push`）を有効にすると、push の前に `make test` が流れ、失敗したら push を止める
- リリースの前に、`make update-test` で、更新しても許可が引き継がれることを確かめる（docs/TESTING.md）
