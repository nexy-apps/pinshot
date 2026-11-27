## ダウンロードと開き方

1. 下の `Pinshot-<版>.dmg` をダウンロードして開き、`Pinshot` を `Applications`（アプリケーションフォルダ）へドラッグします（`.zip` は展開して `Pinshot.app` を入れる形です。中身は同じ）
2. 初めて開くと、「"Pinshot.app"は開いていません」（Apple はマルウェアが含まれていないことを検証できませんでした）と止められます（Apple の公証を受けていないため）。次のどちらかで開けます。一度開けば、次からは止められません

   **システム設定から（おすすめ）**
   1. 「完了」を押す（「ゴミ箱に入れる」は押さない）
   2. システム設定 →「プライバシーとセキュリティ」を開き、下のほうへスクロールする
   3. 「"Pinshot.app"は開いていません…」の横の「このまま開く」を押す
   4. パスワードか Touch ID で確かめたら、もう一度 Pinshot を開く

   macOS 14 では、Pinshot を右クリック（control + クリック）して「開く」を選んでも開けます。

   **ターミナルから**
   1. 「完了」を押す
   2. ターミナルで `xattr -dr com.apple.quarantine /Applications/Pinshot.app` を流す
   3. Pinshot を開く
3. 初めてキャプチャするときに「画面収録」の許可を求められます。システム設定で Pinshot をオンにして、Pinshot を開き直してください
   - 録画にマイクの音を入れるときは、初めてのときに「マイク」の許可も求められます（使わなければ不要です）

入れたあとは、アプリの中から新しい版に更新できます（メニューバーのアイコン →「アップデートを確認…」。自動でも確かめます）。更新のときは、手順 2 も、許可の取り直しも要りません。

本物の Pinshot は、この Releases からだけ配っています。ほかの場所で配られているものは、作者が作ったものではありません。

macOS 14 以降が必要です。

ソースからビルドする方法は [README](https://github.com/nexy-apps/pinshot#readme) を見てください。

---

**English:** Requires macOS 14 or later. Download the dmg (or zip), drag `Pinshot.app` to Applications, open it once and choose "Done" (not "Move to Trash") on the "“Pinshot.app” Not Opened" dialog, then allow it in System Settings → Privacy & Security ("Open Anyway"), or run `xattr -dr com.apple.quarantine /Applications/Pinshot.app`. The app is signed with the author's own certificate (not a Developer ID) and is not notarized. Once installed, it updates itself from the menu bar ("アップデートを確認…") and keeps its permissions across updates. Official builds are distributed only from these GitHub Releases.
