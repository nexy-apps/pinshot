#!/bin/bash
# 更新を、手元で通しで試す準備をする（make update-test。手順は docs/TESTING.md の「更新を通しで試す」）。
#
# ふだんの Pinshot とは別の ID（app.nexy.Pinshot.updatetest）・別の名前（Pinshot UpdateTest）の試験用アプリを、古い版と新しい版の 2 つ作り、
# 新しい版を手元のサーバー（http://localhost:8766）から配る。古い版を開くと、Sparkle が新しい版を見つけて入れ替える。
# いちばん確かめたいのは、同じ証明書で署名した版どうしなら、更新しても画面収録・アクセシビリティの許可が外れないこと
# （配る版はどの版も nexy Release Signing で署名する。試験用アプリは、同じ形を開発用の証明書 nexy Dev Signing で試す）。
#
# 古い版の開き方は 2 通り:
# - 手早く: 手元でビルドしたもの（build/update-test/old）を、そのまま開く
# - 配る形に近づけて: サーバーからブラウザでダウンロードし、アプリケーションフォルダに入れて、macOS の確認を通してから開く
#   （ダウンロードの印（quarantine）が付いたままの版から、更新できるかを確かめる）
#
# - 別の ID なので、許可（システム設定の一覧）・設定・「ログイン時に起動」は、ふだんの Pinshot と別になる
# - データ（履歴・浮かせた画像・録画）は、Info.plist の PinshotDataFolderName で別のフォルダ
#   （~/Library/Application Support/PinshotUpdateTest）に置く（Pinshot はサンドボックスを使わないので、
#   分けないと、ふだんの Pinshot の履歴を読み、試験用アプリの設定で消してしまう）
# - 更新ファイルの署名の鍵は、その場で作る試験用のもの（キーチェーンは使わない。金庫がなくても試せる）
# - 試験用アプリだけ、手元のサーバー（暗号化なし）から読めるように、通信の例外を足す（配る版には入れない）
#
# 使い方: make update-test から流す（証明書とポートは、Makefile が環境変数で渡す）
#   環境変数 SIGN_IDENTITY: アプリの署名に使う証明書（make update-test が、開発用の証明書 nexy Dev Signing を渡す。
#     make update-test ADHOC=1 のときは "-" でアドホック署名。許可が外れることを比べるため）
#   環境変数 UPDATE_TEST_PORT: 手元のサーバーのポート（Makefile の UPDATE_TEST_PORT）。試験用アプリの中にも書き込む
#   環境変数 NO_SERVER=1: アプリと版の一覧を作るだけで、サーバーは動かさない
#
# 変数のすぐ後ろに全角の文字を続けるときは、${NAME} と波かっこで囲む（create-signing-cert.sh と同じ理由）。
set -euo pipefail

SIGN_IDENTITY="${SIGN_IDENTITY:?make update-test から流してください（SIGN_IDENTITY がありません）}"
PORT="${UPDATE_TEST_PORT:?make update-test から流してください（UPDATE_TEST_PORT がありません）}"
if [ "${SIGN_IDENTITY}" = "-" ]; then
  SIGN_LABEL="アドホック署名"
else
  SIGN_LABEL="証明書「${SIGN_IDENTITY}」で署名"
fi
# 試験用アプリの ID・アプリのファイルとデータのフォルダの名前・画面に出る名前（決まりは、共通のノート「Pinシリーズの決まり」の 3 の節）
TEST_ID="app.nexy.Pinshot.updatetest"
TEST_NAME="PinshotUpdateTest"
TEST_DISPLAY_NAME="Pinshot UpdateTest"
ROOT="$(pwd)"
WORK="${ROOT}/build/update-test"
SITE="${WORK}/site"
OLD_APP="${WORK}/old/${TEST_NAME}.app"
NEW_APP="${WORK}/new/${TEST_NAME}.app"
PRODUCT="${WORK}/DerivedData/Build/Products/Release/Pinshot.app"
PLIST_BUDDY=/usr/libexec/PlistBuddy

# 試験用アプリが動いたままだと、作り直した古い版を開いても、動いているほうが前に出るだけになる
if lsappinfo find bundleid="${TEST_ID}" 2>/dev/null | grep -q .; then
  echo "試験用の Pinshot（${TEST_DISPLAY_NAME}）が動いています。終了してから、もう一度流してください。" >&2
  exit 1
fi

# サーバーを動かせるか（ポートが空いているか）を、ビルドの前に確かめる（ビルドには数分かかるので、作り終えてから止まらないように）。
# サーバーと同じく 127.0.0.1 のそのポートで受け口を開いてみて、開けなければ止める
check_port() {
  python3 - "$1" <<'PY'
import socket, sys
sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    sock.bind(("127.0.0.1", int(sys.argv[1])))
except OSError as error:
    sys.exit(error.strerror)
PY
}
if [ "${NO_SERVER:-}" != "1" ] && ! PORT_ERROR="$(check_port "${PORT}" 2>&1)"; then
  echo "手元のサーバーを、ポート ${PORT} で動かせません（${PORT_ERROR}）。" >&2
  echo "Address already in use なら、ほかのものがそのポートを使っています（前に流した試験のサーバーが、別のターミナルで動いたままのことが多い）。" >&2
  echo "何が使っているかは、別のターミナルで  lsof -nP -iTCP:${PORT} -sTCP:LISTEN  を流すと分かります。" >&2
  echo "それを止めてから流し直すか、make update-test UPDATE_TEST_PORT=8800 のように、空いているポートを渡してください。" >&2
  exit 1
fi

# プロジェクトが「書類」などの中にあると、手元でビルドした古い版を入れ替えるときに、macOS がそのフォルダへのアクセスを確かめる
# （入れ替えの部品が、そのフォルダの中のアプリを書き換えるため。配る版はアプリケーションフォルダに置くので、出ない）
FOLDER_NOTE=""
for folder in Documents Desktop Downloads; do
  case "${WORK}/" in
    "${HOME}/${folder}/"*)
      FOLDER_NOTE="     （入れ替えのときに「フォルダ内のファイルにアクセス」と聞かれたら、許可する。このプロジェクトが ~/${folder} の中にあるためで、
      配る版はアプリケーションフォルダに置くので出ない）
"
      ;;
  esac
done

# いまの版（project.yml）を古い版にし、ビルド番号を 1 つ上げたものを新しい版にする
VERSION="$(sed -n 's/.*CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)"
BUILD="$(sed -n 's/.*CFBundleVersion: *"\(.*\)"/\1/p' project.yml)"
NEW_VERSION="${VERSION}.1"
NEW_BUILD="$((BUILD + 1))"

rm -rf "${WORK}/old" "${WORK}/new" "${SITE}" "${WORK}/plists"
mkdir -p "${WORK}/old" "${WORK}/new" "${SITE}/download" "${WORK}/plists"

# 試験用の鍵を作る（1 行目が秘密鍵、2 行目が公開鍵）
echo "試験用の鍵を作っています…"
xcrun swiftc -O -module-cache-path "${WORK}/module-cache" scripts/update-test-key.swift -o "${WORK}/make-key"
# 補助の道具も、アプリと同じ証明書で署名する（アドホック署名にするのは ADHOC=1 のときだけ。決まりの 5 の節）
codesign -f -s "${SIGN_IDENTITY}" "${WORK}/make-key" 2>/dev/null
KEYS="$("${WORK}/make-key")"
KEY_FILE="${WORK}/test-private-key.txt"
echo "${KEYS}" | sed -n 1p > "${KEY_FILE}"
PUBLIC_KEY="$(echo "${KEYS}" | sed -n 2p)"

# 試験用の Info.plist を作る（名前・データのフォルダ・版・配信元・公開鍵を差し替え、手元のサーバーから読めるようにする）。
# 自動で確かめる間隔は、配る版と同じ 1 時間（Info.plist のまま。Sparkle が受け付けるいちばん短い間隔）
make_plist() {
  local output="$1" build="$2" version="$3"
  cp Pinshot/Info.plist "${output}"
  "${PLIST_BUDDY}" \
    -c "Set :CFBundleDisplayName ${TEST_DISPLAY_NAME}" \
    -c "Set :PinshotDataFolderName ${TEST_NAME}" \
    -c "Set :CFBundleVersion ${build}" \
    -c "Set :CFBundleShortVersionString ${version}" \
    -c "Set :SUFeedURL http://localhost:${PORT}/appcast.xml" \
    -c "Set :SUPublicEDKey ${PUBLIC_KEY}" \
    -c "Add :NSAppTransportSecurity dict" \
    -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" \
    -c "Add :NSAppTransportSecurity:NSExceptionDomains dict" \
    -c "Add :NSAppTransportSecurity:NSExceptionDomains:localhost dict" \
    -c "Add :NSAppTransportSecurity:NSExceptionDomains:localhost:NSExceptionAllowsInsecureHTTPLoads bool true" \
    "${output}" >/dev/null
}

# 配る版と同じ設定（Release）で、試験用の ID のアプリをビルドする（速くするため、この Mac の CPU 向けだけ）
build_app() {
  local plist="$1"
  if ! xcodebuild -project Pinshot.xcodeproj -scheme Pinshot -sdk macosx -configuration Release \
    -derivedDataPath "${WORK}/DerivedData" CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" ARCHS="$(uname -m)" \
    PRODUCT_BUNDLE_IDENTIFIER="${TEST_ID}" INFOPLIST_FILE="${plist}" build >"${WORK}/build.log" 2>&1; then
    tail -30 "${WORK}/build.log"
    echo "ビルドできませんでした（記録: ${WORK}/build.log）" >&2
    exit 1
  fi
}

# アプリを zip にする（配る zip と同じ作り方）
zip_app() {
  ditto -c -k --sequesterRsrc --keepParent "$1" "$2"
}

echo "古い版（${VERSION}・ビルド ${BUILD}・${SIGN_LABEL}）を作っています…"
make_plist "${WORK}/plists/old.plist" "${BUILD}" "${VERSION}"
build_app "${WORK}/plists/old.plist"
ditto "${PRODUCT}" "${OLD_APP}"
# 配る形に近づけて試すときに、ブラウザでダウンロードする古い版
OLD_ZIP_NAME="${TEST_NAME}-${VERSION}.zip"
zip_app "${OLD_APP}" "${SITE}/download/${OLD_ZIP_NAME}"

echo "新しい版（${NEW_VERSION}・ビルド ${NEW_BUILD}・${SIGN_LABEL}）を作っています…"
make_plist "${WORK}/plists/new.plist" "${NEW_BUILD}" "${NEW_VERSION}"
build_app "${WORK}/plists/new.plist"
ditto "${PRODUCT}" "${NEW_APP}"
NEW_ZIP="${SITE}/${TEST_NAME}-${NEW_VERSION}.zip"
zip_app "${NEW_APP}" "${NEW_ZIP}"

# 2 つの版の「同じアプリ」の条件（macOS が許可を覚えるときの目印）。証明書で署名していれば、2 つとも同じになる
OLD_REQUIREMENT="$(codesign -d -r- "${OLD_APP}" 2>&1 | sed -n 's/^designated => //p')"
NEW_REQUIREMENT="$(codesign -d -r- "${NEW_APP}" 2>&1 | sed -n 's/^designated => //p')"

# 版の一覧を作る（試験用の鍵で署名する）
cat > "${WORK}/notes.md" <<EOF
## 更新の試験

- これは、更新を手元で試すための版です（${VERSION} → ${NEW_VERSION}）
- 入れ替わったあと、画面収録・アクセシビリティの許可が外れていないか、浮かせた画像が戻るか、「ログイン時に起動」が入ったままかを確かめます
EOF
SPARKLE_KEY_FILE="${KEY_FILE}" ./scripts/make-appcast.sh "${NEW_ZIP}" "${WORK}/notes.md" "http://localhost:${PORT}/" "${SITE}/appcast.xml"

cat <<EOF

準備ができました（${SIGN_LABEL}）。

  古い版（${VERSION}）: ${OLD_APP}
  新しい版（${NEW_VERSION}）: 手元のサーバーから配ります

  macOS が「同じアプリ」と見なす条件（許可はこれにひも付く）:
    古い版: ${OLD_REQUIREMENT}
    新しい版: ${NEW_REQUIREMENT}

どちらの試し方でも、先に、開発のビルド（Pinshot Dev）を make stop で終了し、Releases から入れた Pinshot も動いていれば終了しておきます
（ショートカットが重ならないように）。
試験用アプリの名前は ${TEST_DISPLAY_NAME} です（アプリのファイルは ${TEST_NAME}.app。メニューバーのアイコンは、ふだんの Pinshot と同じカメラ）。
データは ~/Library/Application Support/${TEST_NAME} に置くので、ふだんの Pinshot の履歴や浮かせた画像には触れません。

■ 手早く試す（手元でビルドした古い版から更新する）
  1. 別のターミナルで、古い版を開く:  open "${OLD_APP}"
     開いてすぐに新しい版を確かめ、メニューバーのカメラのアイコンの右下に下向きの矢印の印が入り、メニューの上に
     「新しいバージョン ${NEW_VERSION} があります…」と出ることを確かめる（ここではまだ選ばない）
     （印が付くのは、初めて開いたときか、前に確かめてから 1 時間以上たっているとき。付かなければ、4 で「アップデートを確認…」から進める。
     前の試験の設定が残っていると、確かめる前から印が出る。自動で見つけるところから見たいときは、先に defaults delete ${TEST_ID}）
  2. 使い方の窓（初めて開くと出る。メニューの「使い方と許可…」でも出る）から、画面収録とアクセシビリティを許可する
     （システム設定の一覧には ${TEST_DISPLAY_NAME} か ${TEST_NAME} と出る。画面収録をオンにして、開き直すよう言われたら開き直す。開き直しても印は残る）
     ⌘⇧2 で 1 枚撮り、浮かせたままにする。設定の「一般」で「ログイン時に起動」をオンにする
  3. 印が消えないことを確かめる: 「新しいバージョン … があります…」を選び、更新の画面が出たら「あとで通知」で閉じる。
     続けて、メニューの「Pinshot を終了」で終了し、もう一度開く。どちらのあとも、印とメニューの知らせが残っているか
  4. もう一度「新しいバージョン … があります…」を選ぶ →「アップデートをインストール」→ ダウンロードのあと「インストールして再起動」
${FOLDER_NOTE}  5. 入れ替わって開き直したら、次を確かめる:
     - 開き直すときに、macOS の確認の画面が出ないか（出たら、押す前にスクリーンショットを撮っておく）
     - 設定の「一般」のバージョンが ${NEW_VERSION} になっているか
     - アイコンの矢印の印とメニューの知らせが消え、ふだんのカメラのアイコンに戻っているか
     - メニューに「画面収録の許可が必要です…」が出ず、設定の「一般」の画面収録・アクセシビリティが「許可済み」のままか
     - ⌘⇧2 で、許可を聞かれずに撮れるか
     - 浮かせていた画像が戻っているか、「ログイン時に起動」がオンのままか
  （別の回に）更新の画面で「このバージョンはスキップ」を選ぶと印が消え、終了して開き直しても戻らないか

■ 配る形に近づけて試す（ダウンロードして、macOS の確認を通した古い版から更新する）
  1. ブラウザ（Safari など）で次を開いて、古い版をダウンロードする:
       http://localhost:${PORT}/download/${OLD_ZIP_NAME}
  2. 「ダウンロード」フォルダにできた ${TEST_NAME}.app を、Finder で「アプリケーション」フォルダへ移す
     （zip のままのときは、ダブルクリックで展開してから）
  3. 移した ${TEST_NAME} を開く。「"${TEST_NAME}.app"は開いていません」と止められるので、「完了」を押し（「ゴミ箱に入れる」は押さない）、
     システム設定 →「プライバシーとセキュリティ」の下の方の「このまま開く」で開く
     （ここでは、ターミナルの xattr -d では開かない。ダウンロードの印を付けたまま試すため）
     止められずにそのまま開いたときは、そのまま進めてよい（この Mac で一度開いたことのある版は、止められないことがある。
     あとから xattr で印を付けると、別の場所に写して動かす扱い（App Translocation）になり、更新できなくなるので、付けない）
  4. あとは「手早く試す」の 1 の後半（印を確かめる）と、2〜5 と同じ

終わったら:
  - 設定の「一般」で「ログイン時に起動」をオフに戻してから、試験用の Pinshot を終了する
    （戻し忘れたときは、システム設定 →「一般」→「ログイン項目」で外す）
  - アプリケーションフォルダに入れた ${TEST_NAME}.app は、ゴミ箱に入れる
  - このサーバーを control + C で止める
  - 試験用アプリの許可を外す: システム設定 →「プライバシーとセキュリティ」の「画面収録」「アクセシビリティ」で
    ${TEST_DISPLAY_NAME} を選んで「−」で消す（ターミナルなら tccutil reset ScreenCapture ${TEST_ID} と tccutil reset Accessibility ${TEST_ID}。
    マイクを許可したときは tccutil reset Microphone ${TEST_ID} も）。ADHOC=1 で試したあとに証明書で試すとき（その逆も）も、先にこれで外す
  - 試験用のデータも消すときは、~/Library/Application Support/${TEST_NAME} をゴミ箱に入れ、defaults delete ${TEST_ID} を流す
    （ふだんの Pinshot のデータ ~/Library/Application Support/Pinshot と取り違えないように、フォルダの名前で確かめる）
  - 別のターミナルで make update-test-log を流すと、試験のあいだの macOS の記録が
    ${WORK}/system.log に書き出される（許可が引き継がれたかの裏取りと、うまくいかないときの手がかり）
EOF

if [ "${NO_SERVER:-}" = "1" ]; then
  exit 0
fi

echo
echo "サーバーを動かしています（http://localhost:${PORT}）…"
exec python3 -m http.server "${PORT}" --bind 127.0.0.1 --directory "${SITE}"
