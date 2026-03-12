#!/bin/bash
# =============================================================================
# ヘルパー: Excel (.xlsx) 更新ワークフロー
#
# Sheets 版で編集した内容を xlsx にエクスポートし、元の xlsx を上書きする。
# 前提: helper-xlsx-to-sheets.sh で変換済みの Sheets コピーが存在すること。
#
# 使い方:
#   ./scripts/helper-xlsx-update.sh <SHEETS_ID> <ORIGINAL_XLSX_ID>
#
# 例:
#   ./scripts/helper-xlsx-update.sh 1XnX24Jc22SM5jfuku0EZnqjtMTHBl5RXkeym6ORYpr8 1ptsXe9IcSnZOwiUuX0lYBdGYSCdieWWS
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
SHEETS_ID="${1:?'使い方: ./helper-xlsx-update.sh <SHEETS_ID> <ORIGINAL_XLSX_ID>'}"
ORIGINAL_XLSX_ID="${2:?'使い方: ./helper-xlsx-update.sh <SHEETS_ID> <ORIGINAL_XLSX_ID>'}"

TMP_FILE=$(mktemp /tmp/gws-xlsx-update-XXXXXX.xlsx)
trap "rm -f ${TMP_FILE}" EXIT

echo "========================================="
echo "  Excel (.xlsx) 更新ワークフロー"
echo "========================================="

# =============================================================================
# Step 1: Sheets → xlsx エクスポート
# =============================================================================
echo ""
echo "📤 Step 1: Sheets → xlsx エクスポート中..."
echo "   Sheets ID: ${SHEETS_ID}"

gws drive files export \
  --params "{\"fileId\": \"${SHEETS_ID}\", \"mimeType\": \"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"}" \
  --output "${TMP_FILE}"

FILE_SIZE=$(wc -c < "${TMP_FILE}" | tr -d ' ')
echo "   ✅ エクスポート完了: ${TMP_FILE} (${FILE_SIZE} bytes)"

if [ "$FILE_SIZE" -lt 100 ]; then
  echo "   ❌ ファイルサイズが小さすぎます。Sheets ID を確認してください。"
  exit 1
fi

# =============================================================================
# Step 2: 元の xlsx を上書き
# =============================================================================
echo ""
echo "📥 Step 2: 元の xlsx を上書き中..."
echo "   Original xlsx ID: ${ORIGINAL_XLSX_ID}"

UPDATE_RESULT=$(gws drive files update \
  --params "{\"fileId\": \"${ORIGINAL_XLSX_ID}\", \"supportsAllDrives\": true}" \
  --upload "${TMP_FILE}" \
  --format json 2>/dev/null)

if echo "$UPDATE_RESULT" | jq -e '.id' &>/dev/null; then
  UPDATED_NAME=$(echo "$UPDATE_RESULT" | jq -r '.name')
  UPDATED_MIME=$(echo "$UPDATE_RESULT" | jq -r '.mimeType')
  echo "   ✅ 上書き完了"
  echo "   ファイル名: ${UPDATED_NAME}"
  echo "   MIME: ${UPDATED_MIME}"
else
  echo "   ❌ 上書きに失敗しました"
  echo "$UPDATE_RESULT" | jq '.' 2>/dev/null || echo "$UPDATE_RESULT"
  exit 1
fi

echo ""
echo "✅ 完了: 元の xlsx ファイルが更新されました"
echo "   https://drive.google.com/file/d/${ORIGINAL_XLSX_ID}/view"
