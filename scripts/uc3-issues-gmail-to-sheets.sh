#!/bin/bash
# =============================================================================
# ユースケース3: GitHub Issues + Gmail → スプレッドシート転記
#
# GitHub Issues と Gmail を取得し、要望管理シートにまとめる
# 参考: https://zenn.dev/emuni/articles/gws-cli-practical-guide
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

# gh CLI チェック (UC3 必須)
if ! command -v gh &>/dev/null; then
  echo "❌ gh CLI が見つかりません。インストールしてください:"
  echo "   brew install gh (macOS)"
  exit 1
fi

# ─── 設定 ───
SHEET_ID="${SPREADSHEET_ID:?'SPREADSHEET_ID を .env で設定してください'}"
REPO="${GITHUB_REPO:-googleworkspace/cli}"
GMAIL_QUERY="${1:-is:inbox newer_than:7d}"  # デフォルト: 直近7日の受信メール
TMP_DIR=$(mktemp -d)
trap "rm -rf ${TMP_DIR}" EXIT

echo "========================================="
echo "  UC3: GitHub Issues + Gmail → Sheets"
echo "========================================="

# =============================================================================
# Step 1: GitHub Issues を取得 (gh CLI)
# =============================================================================
echo ""
echo "🐙 Step 1: GitHub Issues を取得中..."
echo "  リポジトリ: ${REPO}"

gh issue list \
  --repo "${REPO}" \
  --limit 20 \
  --state open \
  --json number,title,labels,createdAt,author,url \
  > "${TMP_DIR}/issues.json"

ISSUE_COUNT=$(jq '. | length' "${TMP_DIR}/issues.json")
echo "  取得した Issue: ${ISSUE_COUNT} 件"

# Issue 一覧表示
jq -r '.[] | "  #\(.number) \(.title) (\(.author.login))"' "${TMP_DIR}/issues.json" | head -10

# =============================================================================
# Step 2: Gmail からメールを取得 (GWS CLI)
# =============================================================================
echo ""
echo "📧 Step 2: Gmail メールを取得中..."
echo "  検索クエリ: ${GMAIL_QUERY}"

MESSAGES=$(gws gmail users messages list \
  --params "{\"userId\": \"me\", \"q\": \"${GMAIL_QUERY}\", \"maxResults\": 20}" \
  --format json 2>/dev/null)

MSG_IDS=$(echo "$MESSAGES" | jq -r '.messages[]?.id // empty')
MSG_COUNT=$(echo "$MESSAGES" | jq '.messages | length // 0')
echo "  取得したメール: ${MSG_COUNT} 件"

# 各メールの件名・送信者を取得
echo "[]" > "${TMP_DIR}/emails.json"

for MSG_ID in $MSG_IDS; do
  # NOTE: format=metadata + metadataHeaders は GWS CLI v0.11 でハングするため
  #       シンプルな get を使用（全ヘッダーから Subject/From/Date を抽出）
  MSG_DETAIL=$(timeout 30 gws gmail users messages get \
    --params "{\"userId\": \"me\", \"id\": \"${MSG_ID}\"}" \
    --format json 2>/dev/null || echo '{}')
  
  SUBJECT=$(echo "$MSG_DETAIL" | jq -r '.payload.headers[]? | select(.name == "Subject") | .value // "（件名なし）"' | head -1)
  FROM=$(echo "$MSG_DETAIL" | jq -r '.payload.headers[]? | select(.name == "From") | .value // "unknown"' | head -1)
  DATE=$(echo "$MSG_DETAIL" | jq -r '.payload.headers[]? | select(.name == "Date") | .value // ""' | head -1)
  
  # JSON配列に追加
  jq --arg subject "$SUBJECT" --arg from "$FROM" --arg date "$DATE" --arg id "$MSG_ID" \
    '. += [{"id": $id, "subject": $subject, "from": $from, "date": $date}]' \
    "${TMP_DIR}/emails.json" > "${TMP_DIR}/emails_tmp.json"
  mv "${TMP_DIR}/emails_tmp.json" "${TMP_DIR}/emails.json"
  
  echo "  📩 ${SUBJECT} (${FROM})"
done

# =============================================================================
# Step 3: データを統合してスプレッドシートに書き込み
# =============================================================================
echo ""
echo "📊 Step 3: スプレッドシートに書き込み中..."

# Python でデータを整形
python3 -c "
import json, subprocess, sys

# データ読み込み
issues = json.load(open('${TMP_DIR}/issues.json'))
emails = json.load(open('${TMP_DIR}/emails.json'))

# ヘッダー行
rows = [
    ['No', 'ソース', 'タイトル', 'Issue番号', 'ラベル', '作成者/送信者', '日時', 'URL/メールID', 'ステータス']
]

row_num = 1

# GitHub Issues を行に変換
for issue in issues:
    labels = ', '.join([l.get('name', '') for l in issue.get('labels', [])])
    rows.append([
        str(row_num),
        'GitHub Issue',
        issue.get('title', ''),
        f\"#{issue.get('number', '')}\",
        labels,
        issue.get('author', {}).get('login', ''),
        issue.get('createdAt', '')[:10],
        issue.get('url', ''),
        'Open'
    ])
    row_num += 1

# Gmail メールを行に変換
for email in emails:
    rows.append([
        str(row_num),
        'Gmail',
        email.get('subject', ''),
        '',
        '',
        email.get('from', ''),
        email.get('date', ''),
        f\"mail:{email.get('id', '')}\",
        '未対応'
    ])
    row_num += 1

print(f'合計 {len(rows) - 1} 行のデータを書き込みます')

# スプレッドシートに書き込み
values_json = json.dumps({
    'values': rows
})

range_notation = f\"Sheet1!A1:{chr(64 + len(rows[0]))}{len(rows)}\"

print(f'範囲: {range_notation}')
print(json.dumps({'range': range_notation, 'values': rows}, ensure_ascii=False, indent=2)[:500])

# GWS CLI でスプレッドシートに書き込み
result = subprocess.run(
    ['gws', 'sheets', 'spreadsheets', 'values', 'update',
     '--params', json.dumps({
         'spreadsheetId': '${SHEET_ID}',
         'range': range_notation,
         'valueInputOption': 'USER_ENTERED'
     }),
     '--json', values_json,
     '--format', 'json'],
    capture_output=True, text=True
)

if result.returncode == 0:
    resp = json.loads(result.stdout)
    print(f\"✅ 書き込み完了: {resp.get('updatedCells', '?')} セル更新\")
else:
    print(f'❌ エラー: {result.stderr}', file=sys.stderr)
    sys.exit(1)
"

echo ""
echo "✅ UC3 完了: https://docs.google.com/spreadsheets/d/${SHEET_ID}/edit"
