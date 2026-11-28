## この版の主な変更（0.1.2-beta.1 から）

<!-- 出すたびに、この版の変更に書き直す（make publish が、リリースの説明の先頭に入れる） -->

0.1.x を入れている場合は、アプリの中から更新できます（メニューバーのアイコン →「アップデートを確認…」。自動でも確かめます）。画面収録などの許可は、取り直さずにそのまま使えます。

### 新しくできること

- 履歴のウィンドウに「録画」の一覧ができました。残している録画を日付ごとに並べ、浮かせて再生・コピー・保存・共有リンク・Finder で表示・削除ができます。GIF にして上げた録画には「GIF」の印が出ます
- 録画を、動画（MP4）のほか GIF でもクリップボードにコピーできるようになりました（GIF の画像としても、ファイルとしても貼り付けられます）
- 同じ録画を同じ上げる先にもう一度上げるときは、GIF を作り直さずに、前に上げたときのリンクをコピーします
- 録画の窓に、履歴のボタンと右クリックの「履歴…」を付けました（その録画を選んだ状態で、履歴の「録画」を開きます）
- 撮った画像の一覧の下の帯と、上げたものの一覧（録画から上げた GIF で、元の録画が残っているとき）に、Finder で表示を足しました

### 変わったこと

- 録画の窓の操作バーを 2 行にしました（1 行目は再生、2 行目はコピー・保存・共有リンク・Finder・履歴）。コピーと保存は「MP4 | GIF」から選びます
- 浮かせた画像の操作バーも、録画の窓と同じ並び（コピー・保存・共有リンク）にそろえました
- 「撮ったら（録画は止めたら）、クリップボードにもコピーする」を初期設定でオンにしました（設定で変えていなければ、オンになります）
- 履歴のウィンドウを広げ、下の帯のボタンの名前が「…」で切れないようにしました
- 浮かせた画像・録画の窓の右クリックのメニューを撮るのにアクセシビリティの許可が要るとき、メニューの下に案内を出すようにしました

### 直したこと

- 押せる部品の上でマウスを動かすと、カーソルがちらつくのを直しました
- 文字マーカーで空白を含めて引くと、帯が画像の左端から始まるのを直しました

**English:** The History window now has a Recordings list (play, copy, save, share link, show in Finder, delete), and recordings can be copied to the clipboard as MP4 or GIF. Uploading the same recording again to the same destination reuses the previous link instead of re-making the GIF. The recording window's toolbar now has two rows and a History button, and "Copy to clipboard after capture" is now on by default. Also fixes cursor flicker over buttons and a text-marker highlight that started at the image's left edge. If you have 0.1.x, you can update from the menu bar ("アップデートを確認…"); permissions such as Screen Recording are kept.
