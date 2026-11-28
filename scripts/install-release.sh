#!/bin/bash
# 製品版（GitHub の Releases に置いた本物）を落として、アプリケーションフォルダに入れる（make install-release）。
#
# 製品版は金庫の中の証明書で署名するので、手元ではビルドできない。Releases に置いたものを落として入れれば、
# 金庫は要らず、使う人が受け取るものとまったく同じものを入れられる。
# アプリの中からの更新を試すとき（前の版を入れて、そこから更新する）と、ふだん使いの製品版を入れ直すときに使う。
#
# 使い方: install-release.sh <リポジトリ（nexy-apps/pinshot）> <製品版の証明書の SHA-1> [タグ]
#   タグがなければ、いちばん新しいリリース（β 版も含む）
#   環境変数 INSTALL_DIR: 入れる場所（なければ /Applications）
#   環境変数 NO_OPEN=1: 入れたあとに開かない
#
# 入れる前に、落とした zip を .sha256 と照らし合わせ、中のアプリが製品版の証明書で署名されているかを確かめる
# （合わなければ入れない）。動いている製品版は終了し、前の版はゴミ箱に入れる。
# 変数のすぐ後ろに全角の文字を続けるときは、${NAME} と波かっこで囲む（create-signing-cert.sh と同じ理由）。
set -euo pipefail

REPO="${1:?使い方: install-release.sh <リポジトリ> <証明書の SHA-1> [タグ]（make install-release から流す）}"
SHA1="${2:?使い方: install-release.sh <リポジトリ> <証明書の SHA-1> [タグ]}"
TAG="${3:-}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP="${INSTALL_DIR}/Pinshot.app"
BUNDLE_ID="app.nexy.Pinshot"
ROOT="$(pwd)"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI（gh）がありません。brew install gh で入れて、gh auth login でログインしてください。" >&2
  exit 1
fi

if [ -z "${TAG}" ]; then
  TAG="$(gh release list --repo "${REPO}" --limit 1 --json tagName --jq '.[0].tagName')"
  if [ -z "${TAG}" ]; then
    echo "${REPO} に、リリースが見つかりません。" >&2
    exit 1
  fi
fi
echo "製品版 ${TAG} を落としています…"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
gh release download "${TAG}" --repo "${REPO}" --pattern '*.zip' --pattern '*.sha256' --dir "${WORK}"

ZIP_PATH="$(ls "${WORK}"/Pinshot-*.zip 2>/dev/null | head -1)"
SUM_PATH="$(ls "${WORK}"/Pinshot-*.sha256 2>/dev/null | head -1)"
if [ -z "${ZIP_PATH}" ] || [ -z "${SUM_PATH}" ]; then
  echo "${TAG} に、zip か .sha256 がありません。" >&2
  exit 1
fi

# 落とした zip が、Releases に置いた .sha256 と合うか（.sha256 には DMG の行もあるので、zip の行だけを見る）
ZIP_NAME="$(basename "${ZIP_PATH}")"
if ! (cd "${WORK}" && grep -F "  ${ZIP_NAME}" "$(basename "${SUM_PATH}")" | shasum -a 256 -c - >/dev/null); then
  echo "${ZIP_NAME} の SHA-256 が、Releases の .sha256 と合いません。入れずに止めます。" >&2
  exit 1
fi

ditto -x -k "${ZIP_PATH}" "${WORK}/app"
NEW_APP="${WORK}/app/Pinshot.app"
if [ ! -d "${NEW_APP}" ]; then
  echo "${ZIP_NAME} の中に Pinshot.app がありません。" >&2
  exit 1
fi
# 製品版の証明書（指紋）で署名されているか（make dist と同じ確かめ）
"${ROOT}/scripts/signing-check.sh" app "${NEW_APP}" "${SHA1}"

# 入れる場所の製品版が動いていれば、終了する（浮かせた画像を保存してから終わるので、終わり切るまで最大 8 秒待つ）。
# 開発版（Pinshot Dev）と、ほかの場所の製品版は止めない
running_here() {
  local asn path
  for asn in $(lsappinfo find bundleid="${BUNDLE_ID}" 2>/dev/null); do
    # いまの macOS の lsappinfo は「bundle path="/Applications/Pinshot.app"」の形で返す（前の形「"LSBundlePath"="…"」も読む）
    path="$(lsappinfo info -only bundlepath "${asn}" 2>/dev/null | sed -n 's/.*[Pp]ath"* *= *"\(.*\)".*/\1/p' | head -1)"
    [ "${path%/}" = "${APP%/}" ] && return 0
  done
  return 1
}
if running_here; then
  echo "動いている Pinshot（製品版）を終了します"
  osascript -e "quit app id \"${BUNDLE_ID}\"" >/dev/null 2>&1 || true
  for _ in $(seq 1 80); do
    running_here || break
    sleep 0.1
  done
  if running_here; then
    echo "Pinshot（製品版）を終了できませんでした。メニューバーのメニューの「Pinshot を終了」で終了してから、もう一度流してください。" >&2
    exit 1
  fi
fi

# 前の版はゴミ箱に入れる（消さない。名前に日時を付けて、ゴミ箱の中でぶつからないように）
if [ -d "${APP}" ]; then
  mv "${APP}" "${HOME}/.Trash/Pinshot（前の版 $(date +%Y-%m-%d\ %H.%M.%S)）.app"
fi
mkdir -p "${INSTALL_DIR}"
ditto "${NEW_APP}" "${APP}"
# macOS に登録し直す（写している途中のアプリを先に見つけて、「開けないアプリ」と覚えないように）
touch "${APP}"
"${LSREGISTER}" -f "${APP}" >/dev/null 2>&1 || true

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
echo
echo "${APP} に、製品版 ${VERSION}（${TAG}）を入れました。"
if [ "${NO_OPEN:-}" != "1" ]; then
  open "${APP}"
fi
