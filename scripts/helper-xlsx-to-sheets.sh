#!/bin/bash
# =============================================================================
# ヘルパー: Excel (.xlsx) → Google Sheets 変換 & 読み取り
#
# 共有ドライブ上の Excel ファイルを Google Sheets 形式にコピーし、
# Sheets API で読み書きできるようにする。
#
# 使い方:
#   ./scripts/helper-xlsx-to-sheets.sh <FILE_ID> [SHEET_RANGE]
#
# 例:
#   ./scripts/helper-xlsx-to-sheets.sh 1ptsXe9IcSnZOwiUuX0lYBdGYSCdieWWS
#   ./scripts/helper-xlsx-to-sheets.sh 1ptsXe9IcSnZOwiUuX0lYBdGYSCdieWWS "Sheet1!A1:Z50"
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# .env 読み込み
if [ -f "${SCRIPT_DIR}/../.env" ]; then
  set -a; source "${SCRIPT_DIR}/../.env"; set +a
fi

# ─── 認証チェック ───
if ! gws auth status &>/dev/null; then
  echo "❌ GWS CLI が未認証です。先に認証を実行してください:"
  echo "   source $(dirname "$SCRIPT_DIR")/.env && gws auth login"
  exit 1
fi

# ─── 引数 ───
FILE_ID="${1:?'使い方: ./helper-xlsx-to-sheets.sh <FILE_ID> [SHEET_RANGE]'}"
RANGE="${2:-Sheet1!A1:Z100}"

echo "========================================="
echo "  Excel → Google Sheets 変換 & 読み取り"
echo "========================================="

# =============================================================================
# Step 1: ファイル情報を取得（共有ドライブ対応）
# =============================================================================
echo ""
echo "📄 Step 1: ファイル情報を取得中..."

# stderr を除外して取得（GWS CLI の keyring メッセージが jq を壊すため）
FILE_INFO=$(gws drive files get \
  --params "{\"fileId\": \"${FILE_ID}\", \"fields\": \"id,name,mimeType,parents\", \"supportsAllDrives\": true}" \
  --format json 2>/dev/null) || true

# JSON パースチェック
if ! echo "$FILE_INFO" | jq empty 2>/dev/null; then
  echo "❌ GWS CLI の応答が不正です。認証を確認してください。"
  echo "   gws auth status"
  exit 1
fi

if echo "$FILE_INFO" | jq -e '.error' &>/dev/null; then
  echo "❌ ファイルが見つかりません (ID: ${FILE_ID})"
  echo "   共有ドライブのファイルは supportsAllDrives が必要です。"
  echo "$FILE_INFO" | jq -r '.error.message'
  exit 1
fi

FILE_NAME=$(echo "$FILE_INFO" | jq -r '.name')
MIME_TYPE=$(echo "$FILE_INFO" | jq -r '.mimeType')
echo "  ファイル名: ${FILE_NAME}"
echo "  MIME タイプ: ${MIME_TYPE}"

# =============================================================================
# Step 2: Google Sheets 形式かチェック
# =============================================================================
SHEETS_MIME="application/vnd.google-apps.spreadsheet"

if [ "$MIME_TYPE" = "$SHEETS_MIME" ]; then
  echo ""
  echo "✅ すでに Google Sheets 形式です。そのまま読み取ります。"
  SHEETS_ID="$FILE_ID"
else
  echo ""
  echo "📊 Step 2: Google Sheets 形式にコピー中..."
  
  # Drive API の copy で mimeType を指定して変換コピー（2>/dev/null で stderr 除外）
  COPY_RESULT=$(gws drive files copy \
    --params "{\"fileId\": \"${FILE_ID}\", \"supportsAllDrives\": true}" \
    --json "{\"name\": \"${FILE_NAME} (Sheets変換)\", \"mimeType\": \"${SHEETS_MIME}\"}" \
    --format json 2>/dev/null)
  
  SHEETS_ID=$(echo "$COPY_RESULT" | jq -r '.id')
  echo "  ✅ 変換コピー完了: ${SHEETS_ID}"
  echo "     https://docs.google.com/spreadsheets/d/${SHEETS_ID}/edit"
fi

# =============================================================================
# Step 3: Sheets API でデータ読み取り
# =============================================================================
echo ""
echo "📖 Step 3: データ読み取り中... (範囲: ${RANGE})"

DATA=$(gws sheets spreadsheets values get \
  --params "{\"spreadsheetId\": \"${SHEETS_ID}\", \"range\": \"${RANGE}\"}" \
  --format json 2>/dev/null)

ROW_COUNT=$(echo "$DATA" | jq '.values | length // 0')
echo "  取得した行数: ${ROW_COUNT}"

# 最初の5行をプレビュー表示
echo ""
echo "─── プレビュー（先頭5行） ───"
echo "$DATA" | jq -r '.values[:5][] | @tsv'

echo ""
echo "─── 全データ (JSON) ───"
echo "$DATA" | jq '.values'

echo ""
echo "✅ 完了"
echo "   Sheets ID: ${SHEETS_ID}"
echo "   URL: https://docs.google.com/spreadsheets/d/${SHEETS_ID}/edit"

# 変換コピーの場合、不要なら削除を案内
if [ "$MIME_TYPE" != "$SHEETS_MIME" ]; then
  echo ""
  echo "💡 変換コピーが不要になったら削除できます:"
  echo "   gws drive files delete --params '{\"fileId\": \"${SHEETS_ID}\", \"supportsAllDrives\": true}'"
fi
