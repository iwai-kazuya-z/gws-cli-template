#!/bin/bash
# =============================================================================
# UC4: GA4 runReport 汎用 CLI
#
# GA4 Data API (analyticsdata.googleapis.com) の runReport を叩き、結果を
# stdout に構造化データで返す汎用ツール。
#
# 位置づけ: Biz フロー (Devin → dorapita-mcp → gws-cli → Notion) の中で、
#           gws-cli レイヤの GA4 取得 CLI として動作する。
#           Sheets/Notion 等の出力先には依存しない（stdout 固定）。
#
# 前提:
#   - gcloud auth application-default login --scopes=\
#       "https://www.googleapis.com/auth/analytics.readonly,\
#        https://www.googleapis.com/auth/cloud-platform"
#   - 対象 GA4 プロパティに「閲覧者」以上で紐付いた Google アカウント
#   - quota project は GA4_QUOTA_PROJECT（デフォルト: iwai-personal-tools）
#
# Usage:
#   uc4-ga4-report.sh [--property-id <id>] [--config <path|->] [--format json|tsv|ndjson]
#
# Examples:
#   # .env の GA4_PROPERTY_ID + サンプル config を使う
#   ./scripts/uc4-ga4-report.sh --config config/ga4-reports/page-path-activeusers-7d.json
#
#   # 上流 (Devin/dorapita-mcp) が動的生成した runReport body を stdin から渡す
#   echo "$BODY_JSON" | ./scripts/uc4-ga4-report.sh --config - --format tsv
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GWS_CLI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# .env 読み込み（存在すれば）
if [ -f "${GWS_CLI_DIR}/.env" ]; then
  set -a; source "${GWS_CLI_DIR}/.env"; set +a
fi

# ─── 引数パース ───
PROPERTY_ID="${GA4_PROPERTY_ID:-}"
CONFIG_PATH=""
FORMAT="json"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --property-id) PROPERTY_ID="$2"; shift 2 ;;
    --config)      CONFIG_PATH="$2"; shift 2 ;;
    --format)      FORMAT="$2"; shift 2 ;;
    -h|--help)     usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

# ─── 入力バリデーション ───
if [ -z "$PROPERTY_ID" ]; then
  echo "❌ GA4 property id が未指定です。--property-id または .env の GA4_PROPERTY_ID を設定してください。" >&2
  exit 1
fi
if [ -z "$CONFIG_PATH" ]; then
  echo "❌ --config <path|-> が必要です。runReport body JSON のパス、または '-' (stdin) を指定してください。" >&2
  exit 1
fi
case "$FORMAT" in
  json|tsv|ndjson) ;;
  *) echo "❌ --format は json|tsv|ndjson のいずれかです (got: $FORMAT)" >&2; exit 1 ;;
esac

# ─── 依存コマンド ───
for cmd in gcloud curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ 必須コマンドが見つかりません: $cmd" >&2; exit 1; }
done

# ─── runReport body 読み込み ───
if [ "$CONFIG_PATH" = "-" ]; then
  REQUEST_BODY="$(cat)"
else
  [ -f "$CONFIG_PATH" ] || { echo "❌ config が存在しません: $CONFIG_PATH" >&2; exit 1; }
  REQUEST_BODY="$(cat "$CONFIG_PATH")"
fi
echo "$REQUEST_BODY" | jq empty 2>/dev/null || {
  echo "❌ config が有効な JSON ではありません" >&2; exit 1;
}

# ─── アクセストークン取得 ───
TOKEN="$(gcloud auth application-default print-access-token 2>/dev/null || true)"
if [ -z "$TOKEN" ]; then
  echo "❌ ADC アクセストークンを取得できませんでした。以下で再ログインしてください:" >&2
  echo "   gcloud auth application-default login --scopes=\"https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/cloud-platform\"" >&2
  exit 1
fi

QUOTA_PROJECT="${GA4_QUOTA_PROJECT:-iwai-personal-tools}"
ENDPOINT="https://analyticsdata.googleapis.com/v1beta/properties/${PROPERTY_ID}:runReport"

# ─── API 呼び出し ───
HTTP_RESPONSE="$(mktemp)"
trap 'rm -f "$HTTP_RESPONSE"' EXIT

HTTP_CODE="$(curl -sS -o "$HTTP_RESPONSE" -w "%{http_code}" \
  -X POST "$ENDPOINT" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "x-goog-user-project: ${QUOTA_PROJECT}" \
  -H "Content-Type: application/json" \
  --data "$REQUEST_BODY")"

if [ "$HTTP_CODE" != "200" ]; then
  echo "❌ GA4 runReport 失敗 (HTTP ${HTTP_CODE})" >&2
  cat "$HTTP_RESPONSE" >&2
  echo >&2
  exit 1
fi

# ─── 整形出力 ───
case "$FORMAT" in
  json)
    cat "$HTTP_RESPONSE"
    ;;
  ndjson)
    # 1 行 = 1 行レポート。dimension/metric を name→value の map にフラット化
    jq -c '
      (.dimensionHeaders // []) as $dh
      | (.metricHeaders // [])  as $mh
      | (.rows // [])[]
      | . as $row
      | [ range(0; $dh|length) | {key: $dh[.].name, value: ($row.dimensionValues[.].value // null)} ] as $dims
      | [ range(0; $mh|length) | {key: $mh[.].name, value: ($row.metricValues[.].value    // null)} ] as $mets
      | (($dims + $mets) | from_entries)
    ' "$HTTP_RESPONSE"
    ;;
  tsv)
    jq -r '
      ( [ (.dimensionHeaders // [])[].name ]
        + [ (.metricHeaders // [])[].name ]
      ) as $header
      | $header, (
          (.rows // [])[]
          | [ (.dimensionValues // [])[].value ]
            + [ (.metricValues // [])[].value ]
        )
      | @tsv
    ' "$HTTP_RESPONSE"
    ;;
esac
