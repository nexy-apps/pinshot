DERIVED_DATA := build
APP := $(DERIVED_DATA)/Build/Products/Debug/Pinshot.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Pinshot.app
INSTALL_BUILT_APP := $(DERIVED_DATA)/Build/Products/Install/Pinshot.app
# 開発のビルド（make build・run・install）の ID。make stop が、配る版を止めないよう、この ID のアプリだけを終了する。
# ID と画面の名前は project.yml の Debug・Install で決めている（変えるときは、ここも合わせる。決まりは共通のノート「Pinシリーズの決まり」の 3 の節）
DEV_BUNDLE_ID := app.nexy.Pinshot.dev
# make install で入れる場所（開発のビルドなので、配る版の Pinshot.app とぶつからないよう「Pinshot Dev.app」の名前で入れる）
INSTALL_DIR ?= /Applications
INSTALL_APP := $(INSTALL_DIR)/Pinshot Dev.app
# アプリの版（project.yml の CFBundleShortVersionString）
VERSION := $(shell sed -n 's/.*CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)
# β 版として出すときは BETA=1 のように番号を渡す（タグは v0.1.0-beta.1、GitHub ではプレリリースにする）
BETA ?=
RELEASE_NAME := $(VERSION)$(if $(BETA),-beta.$(BETA))
DIST_BASE := dist/Pinshot-$(RELEASE_NAME)
DIST_ZIP := $(DIST_BASE).zip
DIST_DMG := $(DIST_BASE).dmg

# 署名（決まりは、共通のノート「Pinシリーズの決まり」の 4・5 の節と docs/ARCHITECTURE.md の「署名」）。
# 開発のビルド・テスト・更新の試験・補助の道具は、開発用の証明書で署名する（make cert で一度だけ作る）。
# 証明書がなければ止めて案内を出す（黙ってアドホック署名にしない）。ADHOC=1 を付けたときだけ、注意を出してアドホック署名にする。
# 作者以外がソースからビルドするときは、DEV_CERT="〇〇 Dev Signing" のように自分の証明書の名前を渡せる
DEV_CERT ?= nexy Dev Signing
ADHOC ?=
# BETA=1 とそろえて、1 だけを受け付ける（true・yes などは、気づかずに証明書のビルドになるので止める）
ifneq ($(filter-out 1,$(ADHOC)),)
$(error ADHOC には 1 だけを渡せます（いまの値: $(ADHOC)）。アドホック署名にするときは ADHOC=1、しないときは付けない)
endif
DEV_SIGN := $(if $(filter 1,$(ADHOC)),-,$(DEV_CERT))
# ビルドしたアプリが、想定の署名（開発用の証明書。ADHOC=1 のときはアドホック署名）になったかを確かめる。
# 開発用の証明書は人ごとに違い、指紋を決めておけないので、名前で見る（配る版は signing-check.sh で指紋を見る）
DEV_SIGN_WANT := $(if $(filter 1,$(ADHOC)),Signature=adhoc,Authority=$(DEV_CERT))
check_dev_signed = codesign -dvv "$(1)" 2>&1 | grep -qxF "$(DEV_SIGN_WANT)" || { \
	echo "$(1) が、想定の署名（$(DEV_SIGN_WANT)）になっていません。いまの署名:" >&2; \
	codesign -dvv "$(1)" 2>&1 | grep -E '^(Authority|Signature)=' >&2; exit 1; }
# 配る版（make dist・make publish）は、作者の金庫の中の「nexy Release Signing」で署名する。証明書は project.yml の
# Release の CODE_SIGN_IDENTITY（SHA-1）で決めていて、ここではビルドの前後の確かめのために読む。ADHOC=1 は効かない。
# 金庫は scripts/vault.sh が開けて、必ず閉める
RELEASE_SIGN_IDENTITY = $(or $(shell sed -n 's/^ *CODE_SIGN_IDENTITY: *\([0-9A-F]\{40\}\) *$$/\1/p' project.yml),\
	$(error project.yml の Release に、CODE_SIGN_IDENTITY（証明書の SHA-1）がありません))
# 金庫の中の、更新ファイルに署名する鍵のアカウント名（Sparkle の道具に渡す）
SPARKLE_ACCOUNT := nexy-release

XCODEBUILD := xcodebuild -project Pinshot.xcodeproj -scheme Pinshot -derivedDataPath $(DERIVED_DATA)

# 更新の仕組み（Sparkle）。公式の配布物を取り寄せて Vendor/Sparkle に置く（リポジトリには入れない）。
# 版を上げるときは、SPARKLE_VERSION と SPARKLE_SHA256（配布物 Sparkle-版.tar.xz の SHA-256）を一緒に変える
SPARKLE_VERSION := 2.10.1
SPARKLE_SHA256 := 1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE_DIR := Vendor/Sparkle
# 取り寄せた版の印（版を上げると名前が変わり、取り寄せ直す）
SPARKLE_STAMP := $(SPARKLE_DIR)/.version-$(SPARKLE_VERSION)
# 更新ファイルの署名を確かめる公開鍵（project.yml の PINSHOT_UPDATE_PUBLIC_KEY）
# （最初の 1 行だけ読む。Debug・Install の空の値は読まない。make publish でだけ使うので、使うときに読む）
UPDATE_PUBLIC_KEY = $(shell sed -n '/^ *PINSHOT_UPDATE_PUBLIC_KEY: *"\(.*\)"/{s//\1/p;q;}' project.yml)
# Release を作るリポジトリ（手元には写しの yzanbo などほかの送り先もあるので、gh にはいつもこれを渡す）
GITHUB_REPO := nexy-apps/pinshot
# 配る更新ファイル（zip）を置く場所。版の一覧（appcast.xml）の中のダウンロード元になる
RELEASE_DOWNLOAD_URL := https://github.com/$(GITHUB_REPO)/releases/download/v$(RELEASE_NAME)/
# 版の一覧（appcast.xml）を置く場所。組織 nexy-apps の GitHub Pages（https://nexy-apps.github.io/pinshot/appcast.xml）。
# アプリのリポジトリには置かない（make publish が、置き場所のリポジトリに書き込んで送る）
APPCAST_REPO := https://github.com/nexy-apps/nexy-apps.github.io.git
APPCAST_SITE := $(DERIVED_DATA)/appcast-site
APPCAST_FILE := pinshot/appcast.xml
# 更新の試験で、新しい版を配る手元のサーバーのポート（Pin シリーズの試験どうしでぶつからないよう、Pinshelf は 8765、Pinstage は 8767）。
# ほかで使っているときは make update-test UPDATE_TEST_PORT=8800 のように替える
UPDATE_TEST_PORT ?= 8766

.PHONY: generate build release install install-build uninstall dist dist-in-vault publish publish-in-vault appcast-site \
	test run stop clean cert setup icon readme-images sparkle dev-signing update-test update-test-log

# アイコンを描くスクリプトをビルドする場所
ICON_TOOL_DIR := $(DERIVED_DATA)/icon-tool

# project.yml から Pinshot.xcodeproj を作る（Sparkle がまだなければ、先に取り寄せる）
generate: $(SPARKLE_STAMP)
	xcodegen generate

# Sparkle（更新の仕組み）を取り寄せる。ビルドの前に自動で行うので、ふだんは自分で呼ばなくてよい。
# 取り寄せたファイルは、決めてある SHA-256 と合うことを確かめてから使う（合わなければ止まる）
sparkle: $(SPARKLE_STAMP)

$(SPARKLE_STAMP):
	rm -rf "$(SPARKLE_DIR)"
	mkdir -p "$(SPARKLE_DIR)"
	curl -fsSL -o "$(SPARKLE_DIR)/Sparkle.tar.xz" \
		"https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz"
	echo "$(SPARKLE_SHA256)  $(SPARKLE_DIR)/Sparkle.tar.xz" | shasum -a 256 -c -
	@# 使うものだけ取り出す: アプリに入れるフレームワーク・署名と版の一覧の道具・ライセンス
	tar -xJf "$(SPARKLE_DIR)/Sparkle.tar.xz" -C "$(SPARKLE_DIR)" ./Sparkle.framework ./bin ./LICENSE
	rm "$(SPARKLE_DIR)/Sparkle.tar.xz"
	@# Sparkle のライセンスは、配るものに全文を含める決まりなので、アプリに同梱するファイルへ写す（リポジトリに入れる）
	mkdir -p Pinshot/Licenses
	cp "$(SPARKLE_DIR)/LICENSE" Pinshot/Licenses/Sparkle.txt
	touch "$@"

# 開発用の証明書があるかを確かめる（なければ止めて案内を出す）。ADHOC=1 のときは、注意を出してアドホック署名にする
dev-signing:
ifeq ($(ADHOC),1)
	@echo "注意: 証明書なし（アドホック署名）でビルドします。ビルドのたびに、画面収録などの許可を取り直すことになります。"
else
	@security find-identity -v -p codesigning 2>/dev/null | grep -qF '"$(DEV_CERT)"' || { \
		echo "開発用の証明書「$(DEV_CERT)」が、この Mac にありません。" >&2; \
		echo "最初に 1 回だけ make cert を流してください（証明書なしでビルドするときは ADHOC=1 を付ける）。" >&2; \
		exit 1; }
	@echo "署名: $(DEV_SIGN)"
endif

# 開発用（Debug）にビルドする（ID は app.nexy.Pinshot.dev・画面の名前は Pinshot Dev・開発用の証明書）
build: generate dev-signing
	$(XCODEBUILD) -configuration Debug CODE_SIGN_IDENTITY="$(DEV_SIGN)" build
	@$(call check_dev_signed,$(APP))

# 配る版の設定（Release）でビルドする。Intel と Apple Silicon の両方で動く形にする。
# 配る版用の証明書で署名するので、金庫が開いている必要がある（make dist から使う。ひとりで流すと、署名で止まる）
release: generate
	$(XCODEBUILD) -configuration Release ONLY_ACTIVE_ARCH=NO build

# 配る版と同じ作り（project.yml の Install）でビルドし、開発のビルドとして「Pinshot Dev.app」の名前でアプリケーションフォルダに入れる
# （前に入れたものは置き換える。ID は app.nexy.Pinshot.dev・開発用の証明書なので、配る版の Pinshot とは別のアプリとして並ぶ）。
# 動いている Pinshot Dev は、ビルドが終わってから止める
install: install-build stop
	mkdir -p "$(INSTALL_APP)"
	rsync -a --delete "$(INSTALL_BUILT_APP)/" "$(INSTALL_APP)/"
	@echo ""
	@echo "$(INSTALL_APP) に入れました。アプリケーションフォルダから Pinshot Dev を開いてください。"

install-build: generate dev-signing
	$(XCODEBUILD) -configuration Install ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="$(DEV_SIGN)" build
	@$(call check_dev_signed,$(INSTALL_BUILT_APP))

# アプリケーションフォルダから Pinshot Dev を消す（設定・データ・許可は残る）
uninstall: stop
	rm -rf "$(INSTALL_APP)"

# GitHub の Releases に置く DMG と zip を作る（dist/Pinshot-版.dmg・.zip・.sha256）。
# DMG は、開くと Pinshot.app とアプリケーションフォルダが並び、ドラッグで入れられる形にする。
# 配る版は、作者の金庫の中の「nexy Release Signing」で署名する。金庫は scripts/vault.sh が開け（パスワードをその場で聞く）、
# 終わったら（失敗しても）必ず閉める。ビルドの前に証明書があるかを、ビルドのあとに正しい証明書で署名されたかを確かめる
dist:
	./scripts/vault.sh $(MAKE) dist-in-vault

# 金庫を開けたあとの、make dist の中身（make dist と make publish から使う。ひとりでは流さない）
dist-in-vault:
	./scripts/signing-check.sh keychain "$(RELEASE_SIGN_IDENTITY)"
	$(MAKE) release
	./scripts/signing-check.sh app "$(RELEASE_APP)" "$(RELEASE_SIGN_IDENTITY)"
	mkdir -p dist
	ditto -c -k --sequesterRsrc --keepParent "$(RELEASE_APP)" "$(DIST_ZIP)"
	rm -rf dist/dmg-root
	mkdir -p dist/dmg-root
	ditto "$(RELEASE_APP)" dist/dmg-root/Pinshot.app
	ln -s /Applications dist/dmg-root/Applications
	@# macOS 26 以降は diskutil image で作る（hdiutil create は「使わなくなる」と警告が出るため）。ない版では hdiutil で作る
	rm -f "$(DIST_DMG)"
	if diskutil image create from -h >/dev/null 2>&1; then \
		diskutil image create from --format UDZO --volumeName "Pinshot" dist/dmg-root "$(DIST_DMG)"; \
	else \
		hdiutil create -volname "Pinshot" -srcfolder dist/dmg-root -ov -format UDZO "$(DIST_DMG)"; \
	fi
	rm -rf dist/dmg-root
	cd dist && shasum -a 256 "Pinshot-$(RELEASE_NAME).dmg" "Pinshot-$(RELEASE_NAME).zip" > "Pinshot-$(RELEASE_NAME).sha256"
	@echo ""
	@echo "$(DIST_DMG) と $(DIST_ZIP) を作りました（版: $(RELEASE_NAME)）"

# DMG と zip を作り、GitHub に Release（タグ v版）を作ってアップロードする（GitHub CLI を使う）。
# 説明は「この版の変更」（scripts/release-changes.md。出すたびに書き直す）と「ダウンロードと開き方」をつなげる。
# β 版のときは、説明の先頭に β 版の注意を付け、プレリリースにする。
#
# 入れてもらったアプリに更新を届けるため、zip に金庫の中の鍵で署名して、版の一覧（appcast.xml）を作り、
# 置き場所のリポジトリ（nexy-apps/nexy-apps.github.io）の pinshot/appcast.xml に書き込んで送る（アプリの main には何も送らない）。
# 金庫は最初に 1 回だけ開ける（パスワードを聞く）。先に、main が GitHub と同じか・この版をまだ出していないかを確かめ、
# 版の一覧の置き場所を取ってくる（通信で失敗したときに、金庫を開けてビルドしたあとで止まらないように）
publish: $(SPARKLE_STAMP)
	./scripts/publish-check.sh git "$(RELEASE_NAME)"
	$(MAKE) appcast-site
	./scripts/vault.sh $(MAKE) publish-in-vault

# 版の一覧の置き場所のリポジトリを、手元に取ってくる（前に取ってあれば、GitHub の最新に合わせる。歴史は要らないので最新だけ）
appcast-site:
	if [ -d "$(APPCAST_SITE)/.git" ]; then git -C "$(APPCAST_SITE)" fetch -q --depth 1 origin main && git -C "$(APPCAST_SITE)" reset -q --hard origin/main; \
	else rm -rf "$(APPCAST_SITE)" && git clone -q --depth 1 "$(APPCAST_REPO)" "$(APPCAST_SITE)"; fi

# 金庫を開けたあとの、make publish の中身（make publish から使う。ひとりでは流さない）
publish-in-vault:
	./scripts/publish-check.sh key "$(UPDATE_PUBLIC_KEY)" "$(SPARKLE_ACCOUNT)"
	$(MAKE) dist-in-vault
	( $(if $(BETA),cat scripts/release-notes-beta.md; echo;) cat scripts/release-changes.md; echo; cat scripts/release-notes.md ) > dist/release-notes.md
	mkdir -p "$(dir $(APPCAST_SITE)/$(APPCAST_FILE))"
	SPARKLE_ACCOUNT="$(SPARKLE_ACCOUNT)" ./scripts/make-appcast.sh "$(DIST_ZIP)" scripts/release-changes.md "$(RELEASE_DOWNLOAD_URL)" "$(APPCAST_SITE)/$(APPCAST_FILE)"
	gh release create "v$(RELEASE_NAME)" "$(DIST_DMG)" "$(DIST_ZIP)" "$(DIST_BASE).sha256" --repo "$(GITHUB_REPO)" \
		--target main --title "Pinshot $(RELEASE_NAME)$(if $(BETA), (β 版))" $(if $(BETA),--prerelease) \
		--notes-file dist/release-notes.md
	git -C "$(APPCAST_SITE)" add "$(APPCAST_FILE)"
	git -C "$(APPCAST_SITE)" commit -q -m "chore: Pinshot の版の一覧を $(RELEASE_NAME) にする" -- "$(APPCAST_FILE)"
	git -C "$(APPCAST_SITE)" push -q origin main
	@echo ""
	@echo "$(RELEASE_NAME) を公開しました。版の一覧は数分で https://nexy-apps.github.io/$(APPCAST_FILE) に出て、入れてもらったアプリに新しい版が届きます。"

# 更新を、手元で通しで試す（docs/TESTING.md の「更新を通しで試す」）。
# ふだんの Pinshot とは別の ID・別のデータフォルダの試験用アプリを、開発用の証明書で 2 つの版作り、
# 新しい版を手元のサーバーから配る（止めるときは control + C）
update-test: generate dev-signing
	SIGN_IDENTITY="$(DEV_SIGN)" UPDATE_TEST_PORT="$(UPDATE_TEST_PORT)" ./scripts/update-test.sh

# 更新の試験のあいだの macOS の記録を、build/update-test/system.log に書き出す
# （許可が引き継がれたかの裏取りと、うまくいかないときの手がかりに使う）。
# いつからの記録かは SINCE="2026-11-26 19:50:00" のように渡す（なければ、直近 30 分）
update-test-log:
	./scripts/update-test-log.sh

# テストを動かす（アプリは起動しない）。テストも開発用の証明書で署名する（ADHOC=1 のときはアドホック署名）。
# xcodebuild test は端末によっては動かないので、ビルドしてから xctest で直接動かす
test: generate dev-signing
	$(XCODEBUILD) -configuration Debug CODE_SIGN_IDENTITY="$(DEV_SIGN)" build-for-testing
	xcrun xctest $(DERIVED_DATA)/Build/Products/Debug/PinshotTests.xctest

# 最初に 1 回だけ流す: GitHub に送る前（push の前）に自動テストを流す git hooks（.githooks/pre-push）を有効にする
setup:
	git config core.hooksPath .githooks
	@echo "git hooks を有効にしました。git push の前に make test が流れます。"

# 動いている Pinshot Dev を終了してから、ビルドして起動する
run: build stop
	@# 念のため、開けなかったときは少し待って開き直す（最後の 1 回だけ、エラーを出す）
	@for i in 1 2 3 4; do open "$(APP)" 2>/dev/null && exit 0; sleep 0.5; done; open "$(APP)"

# 動いている開発のビルド（Pinshot Dev）を終了する（配る版の Pinshot は止めない。どちらも中のプログラムの名前は Pinshot なので、ID で選ぶ）。
# 浮かせている画像を保存してから終わるので、終わり切るまで（最大 5 秒）待つ。
# プロセスが消えても、macOS（LaunchServices）が終了を知るのは少し遅れる。知る前に open すると、
# 終わった Pinshot に起動の知らせを送ろうとして -600 で失敗するので、知るまで待つ
stop:
	-@for asn in $$(lsappinfo find bundleid=$(DEV_BUNDLE_ID) 2>/dev/null); do \
		pid=$$(lsappinfo info -only pid "$$asn" 2>/dev/null | sed -n 's/.*=//p'); \
		[ -n "$$pid" ] && kill "$$pid" 2>/dev/null; \
	done; \
	for i in $$(seq 1 50); do lsappinfo find bundleid=$(DEV_BUNDLE_ID) 2>/dev/null | grep -q . || break; sleep 0.1; done

clean:
	xcodebuild -project Pinshot.xcodeproj -scheme Pinshot -derivedDataPath $(DERIVED_DATA) clean
	rm -rf $(DERIVED_DATA)/update-test $(APPCAST_SITE)

# README の絵（docs/images のいちばん上の静止画 hero.png と、使い方の GIF）を作り直す（Pinshot の見た目・動きを変えたとき）。
# アプリのコード（入口の AppDelegate と、Sparkle を読み込む SparkleUpdater を除く）と scripts/readme-images/main.swift を一緒にビルドし、
# Pinshot の部品を実際に出して描き写す。
# 作っている間、画面に Pinshot の部品が少しのあいだ出る（マウス・キーボードの操作や、画面の収録はしない）
README_TOOL_DIR := $(DERIVED_DATA)/readme-images
readme-images: dev-signing
	mkdir -p "$(README_TOOL_DIR)"
	find Pinshot -name '*.swift' ! -name AppDelegate.swift ! -name SparkleUpdater.swift > "$(README_TOOL_DIR)/sources.txt"
	echo scripts/readme-images/main.swift >> "$(README_TOOL_DIR)/sources.txt"
	xcrun swiftc -swift-version 5 -target $(shell uname -m)-apple-macos14.0 -module-name ReadmeImages \
		-module-cache-path "$(README_TOOL_DIR)/module-cache" @"$(README_TOOL_DIR)/sources.txt" -o "$(README_TOOL_DIR)/ReadmeImages"
	codesign -f -s "$(DEV_SIGN)" "$(README_TOOL_DIR)/ReadmeImages"
	"$(README_TOOL_DIR)/ReadmeImages" docs/images

# アプリのアイコンを描き直す（scripts/make-app-icon.swift を変えたとき）
icon: dev-signing
	mkdir -p $(ICON_TOOL_DIR)
	swiftc -O -module-cache-path $(ICON_TOOL_DIR)/cache scripts/make-app-icon.swift -o $(ICON_TOOL_DIR)/make-app-icon
	codesign -f -s "$(DEV_SIGN)" $(ICON_TOOL_DIR)/make-app-icon
	$(ICON_TOOL_DIR)/make-app-icon

# 開発用の証明書（DEV_CERT。作者は「nexy Dev Signing」）を作る（最初に一度だけ。あれば作らず、その SHA-1 を出す。
# 途中で、Mac のログインパスワードを聞かれる）。配る版用の証明書と金庫は別のもので、作者だけが持つ（Pinshelf の scripts/create-nexy-keys.sh）
cert:
	./scripts/create-signing-cert.sh "$(DEV_CERT)"
