## この版について（0.1.0）

<!-- 出すたびに、この版の変更に書き直す（make publish が、リリースの説明の先頭に入れる） -->

アプリの ID と署名を新しくして、0.1.0 から出し直した最初の版です。機能は 0.5.0-beta.1 と同じです（アプリの中からの更新を含みます）。

- アプリの ID を `app.nexy.Pinshot` にしました。前の β 版（ID `dev.portfolio.pinshot`）とは別のアプリとして扱われるので、前の版からは更新されません。前の版を使っていた場合は、ここから入れ直し、画面収録などの許可を取り直してください（システム設定の一覧で古い Pinshot を「−」で消してから、もう一度許可します。前の版はゴミ箱に入れてかまいません）。履歴と浮かせた画像はそのまま残りますが、設定と Gyazo へのログインは引き継がれません
- 作者の証明書（nexy Release Signing）で署名するようにしました。これから先の版は、どれも同じ証明書で署名するので、アプリの中から更新しても、macOS の確認は出ず、許可も外れません

**English:** This is the first release after changing the app ID to `app.nexy.Pinshot` and signing it with the author's own certificate (nexy Release Signing). Features are the same as 0.5.0-beta.1, including in-app updates. It does not update from earlier betas (different app ID), so please install it fresh and grant Screen Recording (and Accessibility) again; history and pinned images are kept, but settings and the Gyazo login are not carried over.
