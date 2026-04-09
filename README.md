# GWS CLI 実践ガイド — セットアップ & ユースケース集

[GWS CLI でここまでできる！](https://zenn.dev/emuni/articles/gws-cli-practical-guide) の記事を元に、Google Workspace CLI (`@googleworkspace/cli`) のセットアップと3つの実践ユースケースをスクリプト化したものです。

## 📁 ディレクトリ構造

```
gws-cli/
├── README.md                           # このファイル
├── AGENTS.md                           # AI エージェント向け GWS CLI リファレンス
├── LICENSE                             # MIT License
├── Taskfile.yml                        # タスクランナー（task コマンド用）
├── .env.example                        # 環境変数テンプレート
├── .gitignore                          # クレデンシャル除外設定
├── setup.sh                            # セットアップスクリプト
├── claude-code-settings.json           # AI エージェント用 deny 設定
└── scripts/
    ├── uc1-slides-template.sh          # UC1: Slides テンプレート量産
    ├── uc2-gmail-to-drive.sh           # UC2: Gmail 添付 → Drive 保存
    ├── uc3-issues-gmail-to-sheets.sh   # UC3: Issues + Gmail → Sheets
    ├── uc4-ga4-report.sh               # UC4: GA4 runReport 汎用 CLI (stdout)
    ├── helper-xlsx-to-sheets.sh        # Helper: Excel → Sheets 変換 & 読み取り
    ├── helper-xlsx-update.sh           # Helper: Sheets 版 → 元 xlsx 書き戻し
    └── helper-sheets-rw.sh            # Helper: Sheets 汎用 読み書き
```

## 🚀 クイックスタート

### 1. 前提条件

- **Node.js** 18+ (npm)
- **gcloud CLI** (API 有効化用、任意)
- **gh CLI** (UC3 で使用)
- **Python 3** (UC2, UC3 のデータ整形で使用)
- **jq** (JSON 処理)

### 2. セットアップ

```bash
# GWS CLI インストール
npm install -g @googleworkspace/cli
gws --version  # 0.11.1

# .env 作成
cd gws-cli
cp .env.example .env
vim .env  # OAuth クライアント ID 等を設定

# セットアップ実行（API有効化等）
chmod +x setup.sh
./setup.sh

# 認証
source .env
gws auth login
```

### 3. GCP での準備

1. [GCP Console](https://console.cloud.google.com/) でプロジェクトを選択
2. **APIs & Services > Credentials** で OAuth クライアント ID を作成（アプリの種類: **デスクトップアプリ**）
3. クライアント ID とシークレットを `.env` に記載
4. 必要な API を有効化:

```bash
gcloud services enable \
  gmail.googleapis.com \
  calendar-json.googleapis.com \
  drive.googleapis.com \
  sheets.googleapis.com \
  docs.googleapis.com \
  slides.googleapis.com \
  admin.googleapis.com \
  people.googleapis.com
```

## 📋 ユースケース

### UC1: Slides テンプレートの量産

テンプレートスライドを `duplicateObject` で複製し、テキスト (`deleteText` + `insertText`) と画像 (`replaceImage`) を差し替えて量産。

```bash
# .env に SLIDES_PRESENTATION_ID を設定してから実行
chmod +x scripts/uc1-slides-template.sh
./scripts/uc1-slides-template.sh
```

**主な操作:**
- `duplicateObject` — スライドと全要素の一括コピー
- `deleteText` + `insertText` — テキスト差し替え
- `replaceImage` — サイズ・位置を保ったまま画像差し替え（`CENTER_CROP` / `CENTER_INSIDE`）

### UC2: Gmail 添付ファイル → Drive 自動保存

メールの添付ファイルを検索 → ダウンロード → Drive にアップロード。

```bash
# .env に DRIVE_UPLOAD_FOLDER_ID を設定（任意）
chmod +x scripts/uc2-gmail-to-drive.sh

# デフォルト: PDF 添付付きメール
./scripts/uc2-gmail-to-drive.sh

# カスタムクエリ
./scripts/uc2-gmail-to-drive.sh "from:client@example.com has:attachment filename:docx"
```

**パイプライン:** Gmail検索 → メッセージ取得 → 添付解析(Python) → Base64デコード → Drive アップロード

### UC3: GitHub Issues + Gmail → スプレッドシート転記

`gh` CLI と GWS CLI を組み合わせて、要望管理シートを自動生成。

```bash
# .env に SPREADSHEET_ID と GITHUB_REPO を設定
chmod +x scripts/uc3-issues-gmail-to-sheets.sh
./scripts/uc3-issues-gmail-to-sheets.sh

# メール検索クエリをカスタマイズ
./scripts/uc3-issues-gmail-to-sheets.sh "label:client-requests newer_than:30d"
```

**出力シートの列:** No / ソース / タイトル / Issue番号 / ラベル / 作成者 / 日時 / URL / ステータス

### UC4: GA4 runReport 汎用 CLI

GA4 Data API の `runReport` を叩き、結果を **stdout** に返す汎用ツール。Biz フロー `Devin → dorapita-mcp → gws-cli → Notion` の中で、gws-cli レイヤの GA4 取得 CLI として位置付ける。Sheets/Notion への書き込みは行わず、呼び出し元がパイプで受ける前提。

**前提:**

```bash
# ADC 認証（GWS CLI の gws auth とは別）
gcloud auth application-default login \
  --scopes="https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/cloud-platform"

# .env に GA4_PROPERTY_ID を設定
# 対象 GA4 プロパティに「閲覧者」以上で紐付いた Google アカウントが必要
```

**使い方:**

```bash
# サンプル config を使う
./scripts/uc4-ga4-report.sh --config config/ga4-reports/page-path-activeusers-7d.json

# TSV 出力
./scripts/uc4-ga4-report.sh --config config/ga4-reports/page-path-activeusers-7d.json --format tsv

# 上流 (Devin/dorapita-mcp) が動的生成した runReport body を stdin から渡す
echo "$BODY_JSON" | ./scripts/uc4-ga4-report.sh --config - --format ndjson

# property id を明示
./scripts/uc4-ga4-report.sh --property-id 375307567 --config -
```

**フラグ:**

| フラグ | 説明 |
|--------|------|
| `--property-id <id>` | GA4 プロパティ ID（省略時 `GA4_PROPERTY_ID`） |
| `--config <path\|->` | runReport body JSON のパス、または `-` で stdin |
| `--format json\|tsv\|ndjson` | 出力フォーマット（デフォルト `json`） |

## 🔧 GWS CLI 基本コマンド

```bash
# コマンド体系: gws <サービス> <リソース> [サブリソース] <メソッド> [フラグ]

# Drive ファイル一覧
gws drive files list --params '{"pageSize": 5}'

# Gmail メッセージ一覧
gws gmail users messages list --params '{"userId": "me"}'

# Sheets データ取得
gws sheets spreadsheets values get --params '{"spreadsheetId": "xxx", "range": "Sheet1!A1:D10"}'
```

### 主なフラグ

| フラグ | 説明 |
|--------|------|
| `--params <JSON>` | URL/クエリパラメータ |
| `--json <JSON>` | リクエストボディ（POST/PATCH/PUT） |
| `--format <FMT>` | 出力形式: `json` / `table` / `yaml` / `csv` |
| `--page-all` | 自動ページネーション |
| `--upload <PATH>` | ファイルアップロード |

## 🔒 セキュリティ注意事項

### AI エージェント利用時の deny 設定

`claude-code-settings.json` に削除系・送信系コマンドの deny リストを設定済みです。Claude Code の `settings.json` にマージして使ってください。

### クレデンシャル管理

- `.env` は **絶対にコミットしない**（`.gitignore` で除外済み）
- OAuth クライアントシークレットが漏洩した場合は GCP コンソールから即座にリセット
- AI エージェントが `.env` を読み取らないよう deny 設定を適用

### 権限（スコープ）は最小限に

```bash
# 読み取り専用で認証
gws auth login --scopes "https://www.googleapis.com/auth/drive.readonly,https://www.googleapis.com/auth/gmail.readonly"

# Drive と Sheets だけ
gws auth login --scopes "https://www.googleapis.com/auth/drive,https://www.googleapis.com/auth/spreadsheets"
```

## 🏗️ テンプレートリポジトリとして使う

このリポジトリはテンプレートリポジトリとして設定できます。組織内の他メンバーが簡単に自分用の GWS CLI 環境を構築できます。

### GitHub テンプレート化の手順

1. GitHub リポジトリの **Settings** → **General** → ✅ **Template repository** にチェック
2. メンバーはリポジトリページの **"Use this template"** → **"Create a new repository"** をクリック

### メンバーの初回セットアップ

```bash
# 1. テンプレートからリポジトリを作成（GitHub UI で実施済み）
git clone https://github.com/<your-org>/<your-repo>.git
cd <your-repo>/gws-cli

# 2. .env を作成して GCP クレデンシャルを記入
cp .env.example .env
vim .env

# 3. セットアップ実行（ツール確認 + API 有効化）
chmod +x setup.sh
./setup.sh

# 4. GWS CLI 認証
source .env && gws auth login

# 5. ユースケースを実行
chmod +x scripts/*.sh
./scripts/uc1-slides-template.sh
```

### Taskfile でワンコマンド実行

[Task](https://taskfile.dev/) をインストール済みの場合:

```bash
task setup   # セットアップ
task auth    # 認証
task uc1     # UC1 実行
task uc2     # UC2 実行
task uc3     # UC3 実行
task check   # 前提条件チェック
task xlsx-to-sheets -- <FILE_ID>           # xlsx → Sheets 変換
task xlsx-update -- <SHEETS_ID> <XLSX_ID>  # xlsx 書き戻し
task sheets-read -- <SHEET_ID> "A1:Z100"   # Sheets 読み取り
task sheets-write -- <SHEET_ID> "A1" '[[…]]' # Sheets 書き込み
task sheets-list -- <SHEET_ID>             # シート一覧
```

### git submodule として使う（一元管理）

他リポジトリから submodule として追加すれば、アップデートが全リポジトリに自動伝播します。

```bash
# 他のリポジトリで submodule 追加
cd your-project
git submodule add https://github.com/iwai-kazuya-z/gws-cli-template.git gws-cli
git commit -m "feat: add gws-cli submodule"

# .env はリポ固有なので gws-cli/ 内に作成
cp gws-cli/.env.example gws-cli/.env
vim gws-cli/.env

# セットアップ & 認証
cd gws-cli && ./setup.sh
source .env && gws auth login
```

submodule のアップデート:

```bash
git submodule update --remote gws-cli
git add gws-cli && git commit -m "chore: update gws-cli submodule"
```

### 適用先ごとにカスタマイズが必要なもの

| ファイル | 何を変える |
|----------|-----------|
| `.env` | `GCP_PROJECT_ID`, OAuth クレデンシャル, UC別ID (Slides/Drive/Sheets/GitHub Repo) |
| `claude-code-settings.json` | プロジェクト固有の deny ルールがあれば追加 |
| `scripts/` | ユースケースに合わせて新スクリプト追加 or 不要なものを削除 |

> **Note:** GWS CLI 本体 (`gws` コマンド) はグローバルインストールなので、一度セットアップすればマシン上の全リポジトリから使えます。このリポジトリはあくまでプロジェクト固有の **設定・スクリプト・セキュリティルール** を束ねる「ランチャー」です。

## ⚠️ Tips: よくあるハマりポイント

### 共有ドライブのファイルが 404 になる

共有ドライブ上のファイルは `supportsAllDrives: true` が必須です。

```bash
# ✗ 404 になる
gws drive files get --params '{"fileId": "xxx"}'

# ○ 共有ドライブ対応
gws drive files get --params '{"fileId": "xxx", "supportsAllDrives": true}'
```

### Excel (.xlsx) ファイルは Sheets API で読めない

Drive 上の Excel ファイルは Sheets API (`values.get` 等) が 400 エラーになります。ヘルパースクリプトで Google Sheets 形式に変換してから読み取ります。

```bash
# Excel → Sheets 変換 & データ読み取り
./scripts/helper-xlsx-to-sheets.sh <FILE_ID>
./scripts/helper-xlsx-to-sheets.sh <FILE_ID> "Sheet1!A1:Z50"

# Sheets 版で編集後、元の xlsx に書き戻す
./scripts/helper-xlsx-update.sh <SHEETS_ID> <ORIGINAL_XLSX_ID>
```

### GWS CLI のアカウント切り替え

`gws auth login` で再認証すると以前の認証は上書きされます。複数アカウントを併用する場合は、対象ファイルの共有設定を追加する方が便利です。

```bash
# 現在の認証アカウント確認
gws auth status 2>&1 | grep user
```

## 🤖 AI エージェント向け

`AGENTS.md` に AI エージェント専用の包括的なリファレンスがあります:

- GWS CLI 全コマンドのテンプレート (Drive / Sheets / Docs / Slides / Gmail)
- 既知の罠と対処法 (stderr, 404, xlsx 等)
- xlsx 読み書きワークフロー
- 安全ルール (deny 設定の説明)

Claude Code / GitHub Copilot / Devin 等がこのリポジトリを参照するとき、まず `AGENTS.md` を読むことで GWS CLI の操作を即座に実行できます。

## 📚 参考

- [GWS CLI 公式リポジトリ](https://github.com/googleworkspace/cli)
- [元記事: GWS CLI でここまでできる！](https://zenn.dev/emuni/articles/gws-cli-practical-guide)
- [Google Workspace API ドキュメント](https://developers.google.com/workspace)
