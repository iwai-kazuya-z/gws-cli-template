#!/bin/bash
# =============================================================================
# ヘルパー: Google Sheets 汎用 読み取り / 書き込み
#
# AI エージェントが最も頻繁に使うスプレッドシート操作を 1 スクリプトに集約。
#
# 使い方:
#   ./scripts/helper-sheets-rw.sh read   <SHEET_ID> <RANGE>
#   ./scripts/helper-sheets-rw.sh write  <SHEET_ID> <RANGE> <VALUES_JSON>
#   ./scripts/helper-sheets-rw.sh append <SHEET_ID> <RANGE> <VALUES_JSON>
#   ./scripts/helper-sheets-rw.sh clear  <SHEET_ID> <RANGE>
#   ./scripts/helper-sheets-rw.sh sheets <SHEET_ID>
#
# VALUES_JSON の形式:
#   '[["A1","B1"],["A2","B2"]]'
#
# 例:
#   ./scripts/helper-sheets-rw.sh read 1XnX...pr8 "Sheet1!A1:Z100"
#   ./scripts/helper-sheets-rw.sh write 1XnX...pr8 "Sheet1!A1" '[["更新値"]]'
#   ./scripts/helper-sheets-rw.sh append 1XnX...pr8 "Sheet1!A1" '[["追加行","値"]]'
#   ./scripts/helper-sheets-rw.sh sheets 1XnX...pr8
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# .env 読み込み
if [ -f "${SCRIPT_DIR}/../.env" ]; then
  set -a; source "${SCRIPT_DIR}/../.env"; set +a
fi

# ─── 認証チェック ───
if ! gws auth status &>/dev/null; then
  echo "❌ GWS CLI が未認証です。先に認証を実行してください:" >&2
  echo "   source $(dirname "$SCRIPT_DIR")/.env && gws auth login" >&2
  exit 1
fi

# ─── 引数 ───
ACTION="${1:?'使い方: ./helper-sheets-rw.sh <read|write|append|clear|sheets> <SHEET_ID> [RANGE] [VALUES_JSON]'}"
SHEET_ID="${2:?'SHEET_ID を指定してください'}"

case "$ACTION" in
  # ─────────────────────────────────────────────────
  # read: セル範囲のデータを読み取り（JSON 出力）
  # ─────────────────────────────────────────────────
  read)
    RANGE="${3:?'RANGE を指定してください (例: Sheet1!A1:Z100)'}"
    echo "📖 読み取り中... (${RANGE})" >&2

    RESULT=$(gws sheets spreadsheets values get \
      --params "{\"spreadsheetId\": \"${SHEET_ID}\", \"range\": \"${RANGE}\"}" \
      --format json 2>/dev/null)

    ROW_COUNT=$(echo "$RESULT" | jq '.values | length // 0')
    echo "   取得: ${ROW_COUNT} 行" >&2

    # stdout に JSON を出力（パイプ連携用）
    echo "$RESULT" | jq '.values'
    ;;

  # ─────────────────────────────────────────────────
  # write: セル範囲にデータを上書き
  # ─────────────────────────────────────────────────
  write)
    RANGE="${3:?'RANGE を指定してください (例: Sheet1!A1)'}"
    VALUES="${4:?'VALUES_JSON を指定してください (例: [[\"A\",\"B\"],[\"C\",\"D\"]])'}"
    echo "✏️  書き込み中... (${RANGE})" >&2

    RESULT=$(gws sheets spreadsheets values update \
      --params "{\"spreadsheetId\": \"${SHEET_ID}\", \"range\": \"${RANGE}\", \"valueInputOption\": \"USER_ENTERED\"}" \
      --json "{\"values\": ${VALUES}}" \
      --format json 2>/dev/null)

    UPDATED=$(echo "$RESULT" | jq -r '.updatedCells // "?"')
    echo "   ✅ 更新: ${UPDATED} セル" >&2

    echo "$RESULT" | jq '.'
    ;;

  # ─────────────────────────────────────────────────
  # append: データを末尾に追記
  # ─────────────────────────────────────────────────
  append)
    RANGE="${3:?'RANGE を指定してください (例: Sheet1!A1)'}"
    VALUES="${4:?'VALUES_JSON を指定してください (例: [[\"新規行\"]])'}"
    echo "➕ 追記中... (${RANGE})" >&2

    RESULT=$(gws sheets spreadsheets values append \
      --params "{\"spreadsheetId\": \"${SHEET_ID}\", \"range\": \"${RANGE}\", \"valueInputOption\": \"USER_ENTERED\", \"insertDataOption\": \"INSERT_ROWS\"}" \
      --json "{\"values\": ${VALUES}}" \
      --format json 2>/dev/null)

    UPDATED_RANGE=$(echo "$RESULT" | jq -r '.updates.updatedRange // "?"')
    UPDATED_CELLS=$(echo "$RESULT" | jq -r '.updates.updatedCells // "?"')
    echo "   ✅ 追記: ${UPDATED_CELLS} セル (${UPDATED_RANGE})" >&2

    echo "$RESULT" | jq '.'
    ;;

  # ─────────────────────────────────────────────────
  # clear: セル範囲をクリア
  # ─────────────────────────────────────────────────
  clear)
    RANGE="${3:?'RANGE を指定してください (例: Sheet1!A1:Z100)'}"
    echo "🗑️  クリア中... (${RANGE})" >&2

    RESULT=$(gws sheets spreadsheets values clear \
      --params "{\"spreadsheetId\": \"${SHEET_ID}\", \"range\": \"${RANGE}\"}" \
      --format json 2>/dev/null)

    echo "   ✅ クリア完了" >&2
    echo "$RESULT" | jq '.'
    ;;

  # ─────────────────────────────────────────────────
  # sheets: シート一覧を取得
  # ─────────────────────────────────────────────────
  sheets)
    echo "📋 シート一覧取得中..." >&2

    RESULT=$(gws sheets spreadsheets get \
      --params "{\"spreadsheetId\": \"${SHEET_ID}\", \"fields\": \"sheets.properties\"}" \
      --format json 2>/dev/null)

    echo "$RESULT" | jq '[.sheets[].properties | {sheetId, title, index}]'
    ;;

  *)
    echo "❌ 不明なアクション: ${ACTION}" >&2
    echo "使い方: ./helper-sheets-rw.sh <read|write|append|clear|sheets> <SHEET_ID> [RANGE] [VALUES_JSON]" >&2
    exit 1
    ;;
esac
