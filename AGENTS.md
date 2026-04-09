# GWS CLI — AI エージェント向けガイド

このファイルは **AI エージェント (Claude Code, GitHub Copilot, Devin 等)** が GWS CLI を効率的に使うためのリファレンスです。

## 🔑 認証の確認

**全てのコマンド実行前に必ず確認:**

```bash
# 認証ステータス確認（stderr にキーリング情報が出るので 2>/dev/null）
gws auth status 2>/dev/null

# 未認証の場合
source /path/to/gws-cli/.env && gws auth login
```

## ⚠️ 必須: stderr フィルタリング

GWS CLI は stderr に `Using keyring backend: keyring` を出力する。
**jq にパイプする場合は必ず stderr を除外すること:**

```bash
# ✗ jq parse error になる
gws drive files get --params '...' --format json | jq '.name'

# ○ stderr を除外
gws drive files get --params '...' --format json 2>/dev/null | jq '.name'

# ○ 変数に格納する場合は 2>/dev/null を付ける
RESULT=$(gws drive files get --params '...' --format json 2>/dev/null)
echo "$RESULT" | jq '.name'
```

## 📁 Drive API

### ファイル情報の取得

```bash
# 基本
gws drive files get \
  --params '{"fileId": "FILE_ID", "fields": "id,name,mimeType,parents"}' \
  --format json 2>/dev/null

# ★ 共有ドライブのファイルは supportsAllDrives: true が必須
gws drive files get \
  --params '{"fileId": "FILE_ID", "fields": "id,name,mimeType", "supportsAllDrives": true}' \
  --format json 2>/dev/null
```

### ファイル一覧

```bash
gws drive files list \
  --params '{"pageSize": 10, "fields": "files(id,name,mimeType)"}' \
  --format json 2>/dev/null

# 共有ドライブのファイル一覧
gws drive files list \
  --params '{"q": "'\''FOLDER_ID'\'' in parents", "supportsAllDrives": true, "includeItemsFromAllDrives": true, "corpora": "allDrives"}' \
  --format json 2>/dev/null
```

### ファイルアップロード

```bash
gws drive files create \
  --params '{"supportsAllDrives": true}' \
  --json '{"name": "filename.pdf", "parents": ["FOLDER_ID"]}' \
  --upload /path/to/file \
  --format json 2>/dev/null
```

### ファイル更新（上書き）

```bash
gws drive files update \
  --params '{"fileId": "FILE_ID", "supportsAllDrives": true}' \
  --upload /path/to/file \
  --format json 2>/dev/null
```

### ファイルエクスポート

```bash
# Google Sheets → xlsx
gws drive files export \
  --params '{"fileId": "SHEETS_ID", "mimeType": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}' \
  --output /tmp/output.xlsx

# Google Docs → docx
gws drive files export \
  --params '{"fileId": "DOCS_ID", "mimeType": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"}' \
  --output /tmp/output.docx

# Google Slides → pptx
gws drive files export \
  --params '{"fileId": "SLIDES_ID", "mimeType": "application/vnd.openxmlformats-officedocument.presentationml.presentation"}' \
  --output /tmp/output.pptx
```

### ファイルコピー（形式変換を含む）

```bash
# Excel → Google Sheets に変換コピー
gws drive files copy \
  --params '{"fileId": "XLSX_FILE_ID", "supportsAllDrives": true}' \
  --json '{"name": "変換後のファイル名", "mimeType": "application/vnd.google-apps.spreadsheet"}' \
  --format json 2>/dev/null
```

## 📊 Sheets API

### データ読み取り

```bash
gws sheets spreadsheets values get \
  --params '{"spreadsheetId": "SHEET_ID", "range": "Sheet1!A1:Z100"}' \
  --format json 2>/dev/null
```

### データ書き込み（上書き）

```bash
gws sheets spreadsheets values update \
  --params '{"spreadsheetId": "SHEET_ID", "range": "Sheet1!A1", "valueInputOption": "USER_ENTERED"}' \
  --json '{"values": [["A1", "B1"], ["A2", "B2"]]}' \
  --format json 2>/dev/null
```

### データ追記

```bash
gws sheets spreadsheets values append \
  --params '{"spreadsheetId": "SHEET_ID", "range": "Sheet1!A1", "valueInputOption": "USER_ENTERED", "insertDataOption": "INSERT_ROWS"}' \
  --json '{"values": [["新しい行1", "値"], ["新しい行2", "値"]]}' \
  --format json 2>/dev/null
```

### シート一覧取得

```bash
gws sheets spreadsheets get \
  --params '{"spreadsheetId": "SHEET_ID", "fields": "sheets.properties"}' \
  --format json 2>/dev/null | jq '.sheets[].properties | {sheetId, title, index}'
```

### セル範囲クリア

```bash
gws sheets spreadsheets values clear \
  --params '{"spreadsheetId": "SHEET_ID", "range": "Sheet1!A1:Z100"}' \
  --format json 2>/dev/null
```

## 📝 Docs API

### ドキュメント取得

```bash
gws docs documents get \
  --params '{"documentId": "DOC_ID"}' \
  --format json 2>/dev/null
```

### テキスト読み取り（本文抽出）

```bash
gws docs documents get \
  --params '{"documentId": "DOC_ID"}' \
  --format json 2>/dev/null | jq -r '
  [.body.content[].paragraph?.elements[]?.textRun?.content // empty] | join("")'
```

### テキスト挿入

```bash
gws docs documents batchUpdate \
  --params '{"documentId": "DOC_ID"}' \
  --json '{
    "requests": [
      {
        "insertText": {
          "location": {"index": 1},
          "text": "挿入するテキスト\n"
        }
      }
    ]
  }' \
  --format json 2>/dev/null
```

### テキスト置換

```bash
gws docs documents batchUpdate \
  --params '{"documentId": "DOC_ID"}' \
  --json '{
    "requests": [
      {
        "replaceAllText": {
          "containsText": {"text": "{{PLACEHOLDER}}", "matchCase": true},
          "replaceText": "実際の値"
        }
      }
    ]
  }' \
  --format json 2>/dev/null
```

## 🎞️ Slides API

### プレゼンテーション取得

```bash
gws slides presentations get \
  --params '{"presentationId": "PRES_ID"}' \
  --format json 2>/dev/null
```

### スライド一覧

```bash
gws slides presentations get \
  --params '{"presentationId": "PRES_ID"}' \
  --format json 2>/dev/null | jq '.slides[] | {objectId, pageElements: [.pageElements[]?.objectId]}'
```

### テキスト置換

```bash
gws slides presentations batchUpdate \
  --params '{"presentationId": "PRES_ID"}' \
  --json '{
    "requests": [
      {
        "replaceAllText": {
          "containsText": {"text": "{{PLACEHOLDER}}", "matchCase": true},
          "replaceText": "新しいテキスト"
        }
      }
    ]
  }' \
  --format json 2>/dev/null
```

## 📧 Gmail API

### メール検索

```bash
gws gmail users messages list \
  --params '{"userId": "me", "q": "from:someone@example.com newer_than:7d", "maxResults": 10}' \
  --format json 2>/dev/null
```

### メール詳細取得

```bash
gws gmail users messages get \
  --params '{"userId": "me", "id": "MESSAGE_ID"}' \
  --format json 2>/dev/null
```

> **注意:** `format: "metadata"` + `metadataHeaders` は GWS CLI v0.11 でハングする。
> 代わりにフル取得してから jq でヘッダーを抽出すること。

### ヘッダー抽出パターン

```bash
MSG=$(gws gmail users messages get \
  --params '{"userId": "me", "id": "MSG_ID"}' \
  --format json 2>/dev/null)

SUBJECT=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "Subject") | .value')
FROM=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "From") | .value')
DATE=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name == "Date") | .value')
```

## 🔄 Excel (.xlsx) ファイルの読み書きワークフロー

Excel ファイルは Sheets API で直接読めない。以下のワークフローを使う:

### 1. 初回: xlsx → Sheets 変換

```bash
# ヘルパースクリプトで変換 & 読み取り
./scripts/helper-xlsx-to-sheets.sh FILE_ID

# または手動で変換コピー
SHEETS_COPY=$(gws drive files copy \
  --params '{"fileId": "XLSX_FILE_ID", "supportsAllDrives": true}' \
  --json '{"name": "ファイル名_Sheets版", "mimeType": "application/vnd.google-apps.spreadsheet"}' \
  --format json 2>/dev/null)
SHEETS_ID=$(echo "$SHEETS_COPY" | jq -r '.id')
```

### 2. 読み取り: Sheets API で読む

```bash
gws sheets spreadsheets values get \
  --params '{"spreadsheetId": "SHEETS_ID", "range": "Sheet1!A1:Z100"}' \
  --format json 2>/dev/null
```

### 3. 書き込み: Sheets API で編集

```bash
gws sheets spreadsheets values update \
  --params '{"spreadsheetId": "SHEETS_ID", "range": "Sheet1!A1", "valueInputOption": "USER_ENTERED"}' \
  --json '{"values": [["新しい値"]]}' \
  --format json 2>/dev/null
```

### 4. 元の xlsx に書き戻す

```bash
# Step A: Sheets → xlsx エクスポート
gws drive files export \
  --params '{"fileId": "SHEETS_ID", "mimeType": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}' \
  --output /tmp/updated.xlsx

# Step B: 元ファイルを上書き
gws drive files update \
  --params '{"fileId": "ORIGINAL_XLSX_ID", "supportsAllDrives": true}' \
  --upload /tmp/updated.xlsx \
  --format json 2>/dev/null
```

### ヘルパースクリプト（推奨）

```bash
# xlsx → Sheets 変換 & 読み取り
./scripts/helper-xlsx-to-sheets.sh FILE_ID [RANGE]

# xlsx 更新ワークフロー（Sheets版で編集 → 元xlsxに書き戻し）
./scripts/helper-xlsx-update.sh SHEETS_ID ORIGINAL_XLSX_ID

# Sheets 汎用読み取り / 書き込み
./scripts/helper-sheets-rw.sh read SHEET_ID "Sheet1!A1:Z100"
./scripts/helper-sheets-rw.sh write SHEET_ID "Sheet1!A1" '[["値1","値2"],["値3","値4"]]'
./scripts/helper-sheets-rw.sh append SHEET_ID "Sheet1!A1" '[["追加行"]]'
./scripts/helper-sheets-rw.sh sheets SHEET_ID
```

## 🚫 既知の罠 (Known Gotchas)

| 罠 | 対処法 |
|----|--------|
| 共有ドライブのファイルが **404** | `"supportsAllDrives": true` を全 Drive API パラメータに追加 |
| jq が **parse error** | `gws` コマンドに `2>/dev/null` を付けて stderr を除外 |
| Excel (.xlsx) で Sheets API が **400** | `drive files copy` で Sheets 形式に変換してから使う |
| Gmail `metadataHeaders` で **ハング** | 使わない。フル取得 → jq でヘッダー抽出 |
| `--download` フラグが **存在しない** | `--output /path/to/file` を使う |
| `--format json` を付け忘れると **table 形式** | パイプ前に必ず `--format json` を付ける |

## 📜 GWS CLI コマンド体系

```
gws <サービス> <リソース> [サブリソース] <メソッド> [フラグ]
```

### サービス一覧

| サービス | リソース例 | 用途 |
|----------|-----------|------|
| `drive` | `files`, `permissions` | ファイル管理 |
| `sheets` | `spreadsheets`, `spreadsheets.values` | スプレッドシート |
| `docs` | `documents` | ドキュメント |
| `slides` | `presentations` | プレゼンテーション |
| `gmail` | `users.messages`, `users.labels` | メール |
| `calendar` | `events`, `calendarList` | カレンダー |
| `admin` | `users`, `groups` | 管理者 |
| `people` | `people`, `contactGroups` | 連絡先 |

### 主要フラグ

| フラグ | 用途 | 例 |
|--------|------|-----|
| `--params <JSON>` | URL / クエリパラメータ | `--params '{"fileId": "xxx"}'` |
| `--json <JSON>` | リクエストボディ (POST/PATCH/PUT) | `--json '{"values": [...]}'` |
| `--format json` | JSON 出力 (jq 連携に必須) | `--format json` |
| `--upload <PATH>` | ファイルアップロード | `--upload /tmp/file.pdf` |
| `--output <PATH>` | ファイルダウンロード/エクスポート | `--output /tmp/out.xlsx` |
| `--page-all` | 自動ページネーション | `--page-all` |

## 📈 GA4 Data API (UC4)

GWS CLI の守備範囲外（`gws` コマンドには無い）なので、ADC + curl で直接 `analyticsdata.googleapis.com` を叩く。UC4 (`scripts/uc4-ga4-report.sh`) がその汎用ラッパー。

- 認証: `gcloud auth application-default login --scopes="https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/cloud-platform"`
- quota project: `x-goog-user-project: iwai-personal-tools`
- エンドポイントは **読み取り系に限定**する（`runReport`, 将来の `batchRunReports` / `runPivotReport` 等）。書き込み系は追加しない
- 出力は stdout 固定。Sheets/Notion 連携は別ツールにパイプで渡す

```bash
# 静的 config
./scripts/uc4-ga4-report.sh --config config/ga4-reports/page-path-activeusers-7d.json

# 動的 body（上流エージェントが生成）
echo "$BODY" | ./scripts/uc4-ga4-report.sh --config - --format ndjson
```

## 🛡️ 安全ルール

- **削除 (delete / trash / remove)**: 禁止。`claude-code-settings.json` で deny 済み
- **メール送信 (gmail send)**: 禁止。deny 済み
- **下書き作成・送信 (drafts create/send)**: 禁止。deny 済み
- **.env の読み取り**: 禁止。deny 済み
- **認証情報のエクスポート**: 禁止。deny 済み
- データの **読み取り・更新** は許可されている
