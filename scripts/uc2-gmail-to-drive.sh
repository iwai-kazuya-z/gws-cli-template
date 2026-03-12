#!/bin/bash
# =============================================================================
# ユースケース2: Gmail 添付ファイル → Drive 自動保存
#
# メールの添付ファイルを検索→ダウンロード→Drive にアップロード
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

# ─── 設定 ───
UPLOAD_FOLDER_ID="${DRIVE_UPLOAD_FOLDER_ID:-}"
SEARCH_QUERY="${1:-has:attachment filename:pdf}"  # デフォルト: PDF添付付きメール
TMP_DIR=$(mktemp -d)
trap "rm -rf ${TMP_DIR}" EXIT

echo "========================================="
echo "  UC2: Gmail 添付ファイル → Drive 自動保存"
echo "========================================="

# =============================================================================
# Step 1: 添付ファイル付きメールを検索
# =============================================================================
echo ""
echo "📧 Step 1: メール検索中..."
echo "  検索クエリ: ${SEARCH_QUERY}"

MESSAGES=$(gws gmail users messages list \
  --params "{\"userId\": \"me\", \"q\": \"${SEARCH_QUERY}\", \"maxResults\": 10}" \
  --format json 2>/dev/null)

MESSAGE_COUNT=$(echo "$MESSAGES" | jq '.messages | length // 0')
echo "  見つかったメール: ${MESSAGE_COUNT} 件"

if [ "$MESSAGE_COUNT" -eq 0 ]; then
  echo "  添付ファイル付きメールが見つかりませんでした。"
  echo "  検索クエリを変更してください（例: has:attachment filename:docx）"
  exit 0
fi

# メッセージ ID 一覧
echo "$MESSAGES" | jq -r '.messages[]?.id' | head -5 | while read -r MSG_ID; do
  echo "  - ${MSG_ID}"
done

# =============================================================================
# Step 2: メッセージから添付ファイル情報を取得
# =============================================================================
echo ""
echo "📎 Step 2: 添付ファイル情報を取得中..."

# 最初のメッセージを処理
FIRST_MSG_ID=$(echo "$MESSAGES" | jq -r '.messages[0].id')

MSG_DETAIL=$(gws gmail users messages get \
  --params "{\"userId\": \"me\", \"id\": \"${FIRST_MSG_ID}\"}" \
  --format json 2>/dev/null)

# 件名を取得
SUBJECT=$(echo "$MSG_DETAIL" | jq -r '.payload.headers[] | select(.name == "Subject") | .value')
echo "  件名: ${SUBJECT}"

# 添付ファイル情報を Python で解析（ネスト構造対応）
python3 -c "
import json, sys

msg = json.loads(sys.stdin.read())

def find_attachments(parts, attachments=None):
    if attachments is None:
        attachments = []
    if not parts:
        return attachments
    for part in parts:
        if part.get('filename') and part.get('body', {}).get('attachmentId'):
            attachments.append({
                'filename': part['filename'],
                'mimeType': part.get('mimeType', 'unknown'),
                'size': part.get('body', {}).get('size', 0),
                'attachmentId': part['body']['attachmentId']
            })
        if part.get('parts'):
            find_attachments(part['parts'], attachments)
    return attachments

parts = msg.get('payload', {}).get('parts', [])
if not parts and msg.get('payload', {}).get('body', {}).get('attachmentId'):
    parts = [msg['payload']]

attachments = find_attachments(parts)
for att in attachments:
    size_kb = att['size'] / 1024
    print(f\"  📄 {att['filename']} ({att['mimeType']}, {size_kb:.1f} KB)\")
    print(f\"     attachmentId: {att['attachmentId'][:50]}...\")

# 添付ファイル情報を JSON で出力（後続ステップ用）
json.dump(attachments, open('${TMP_DIR}/attachments.json', 'w'))
print(f\"\n  合計: {len(attachments)} 個の添付ファイル\")
" <<< "$MSG_DETAIL"

# =============================================================================
# Step 3: 添付ファイルをダウンロード
# =============================================================================
echo ""
echo "⬇️  Step 3: 添付ファイルをダウンロード中..."

python3 -c "
import json, base64, os

attachments = json.load(open('${TMP_DIR}/attachments.json'))
msg_id = '${FIRST_MSG_ID}'
tmp_dir = '${TMP_DIR}'

for att in attachments:
    print(f\"  ダウンロード中: {att['filename']}...\")
    
    # GWS CLI で添付ファイルデータを取得
    import subprocess
    result = subprocess.run(
        ['gws', 'gmail', 'users', 'messages', 'attachments', 'get',
         '--params', json.dumps({
             'userId': 'me',
             'messageId': msg_id,
             'id': att['attachmentId']
         }),
         '--format', 'json'],
        capture_output=True, text=True
    )
    
    if result.returncode != 0:
        print(f'    ❌ エラー: {result.stderr}')
        continue
    
    data = json.loads(result.stdout)
    
    # URL-safe Base64 デコード
    file_data = base64.urlsafe_b64decode(data['data'])
    
    filepath = os.path.join(tmp_dir, att['filename'])
    with open(filepath, 'wb') as f:
        f.write(file_data)
    
    size_kb = os.path.getsize(filepath) / 1024
    print(f'    ✅ 保存完了: {filepath} ({size_kb:.1f} KB)')
"

# =============================================================================
# Step 4: Drive にアップロード
# =============================================================================
echo ""
echo "☁️  Step 4: Drive にアップロード中..."

if [ -z "$UPLOAD_FOLDER_ID" ]; then
  echo "  ⚠️  DRIVE_UPLOAD_FOLDER_ID が設定されていません。"
  echo "  マイドライブのルートにアップロードします。"
fi

for FILE in "${TMP_DIR}"/*; do
  [ -f "$FILE" ] || continue
  FILENAME=$(basename "$FILE")
  
  # attachments.json はスキップ
  [ "$FILENAME" = "attachments.json" ] && continue
  
  echo "  アップロード中: ${FILENAME}..."
  
  if [ -n "$UPLOAD_FOLDER_ID" ]; then
    UPLOAD_RESULT=$(gws drive files create \
      --params '{"supportsAllDrives": true}' \
      --json "{\"name\": \"${FILENAME}\", \"parents\": [\"${UPLOAD_FOLDER_ID}\"]}" \
      --upload "$FILE" \
      --format json)
  else
    UPLOAD_RESULT=$(gws drive files create \
      --json "{\"name\": \"${FILENAME}\"}" \
      --upload "$FILE" \
      --format json)
  fi
  
  FILE_ID=$(echo "$UPLOAD_RESULT" | jq -r '.id')
  echo "  ✅ アップロード完了: ${FILENAME} (ID: ${FILE_ID})"
  echo "     https://drive.google.com/file/d/${FILE_ID}/view"
done

echo ""
echo "✅ UC2 完了: 全ファイルのアップロードが完了しました"
