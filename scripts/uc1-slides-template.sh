#!/bin/bash
# =============================================================================
# ユースケース1: Slides テンプレートの量産
# 
# テンプレートスライドを複製して、テキスト・画像を差し替えて量産する。
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
PRESENTATION_ID="${SLIDES_PRESENTATION_ID:?'SLIDES_PRESENTATION_ID を .env で設定してください'}"

# =============================================================================
# Step 1: プレゼンテーション情報の取得
# =============================================================================
echo "📊 Step 1: プレゼンテーション情報を取得中..."
PRESENTATION_INFO=$(gws slides presentations get \
  --params "{\"presentationId\": \"${PRESENTATION_ID}\"}" \
  --format json 2>/dev/null)

echo "タイトル: $(echo "$PRESENTATION_INFO" | jq -r '.title')"
echo "スライド数: $(echo "$PRESENTATION_INFO" | jq '.slides | length')"

# スライド一覧を表示
echo ""
echo "スライド一覧:"
echo "$PRESENTATION_INFO" | jq -r '.slides[] | "  ID: \(.objectId)"'

# =============================================================================
# Step 2: テンプレートスライド（最後のスライド）の要素を取得
# =============================================================================
echo ""
echo "📋 Step 2: テンプレートスライドの要素を取得中..."

# 最後のスライドをテンプレートとして使用
TEMPLATE_SLIDE_ID=$(echo "$PRESENTATION_INFO" | jq -r '.slides[-1].objectId')
echo "テンプレートスライド ID: ${TEMPLATE_SLIDE_ID}"

# テンプレート内の要素 ID を取得
echo "テンプレート内の要素:"
echo "$PRESENTATION_INFO" | jq -r ".slides[-1].pageElements[]? | \"  \(.objectId): \(.shape.shapeType // .image // \"unknown\") - \(.shape.text.textElements[]?.textRun.content? // \"\")\""

# =============================================================================
# Step 3: スライドを複製する (duplicateObject)
# =============================================================================
echo ""
echo "📑 Step 3: テンプレートスライドを複製中..."

# 新しいスライド用のオブジェクト ID を生成
NEW_SLIDE_ID="slide_copy_$(date +%s)"

# テンプレートスライドの全要素 ID を取得してマッピングを構築
ELEMENT_IDS=$(echo "$PRESENTATION_INFO" | jq -r ".slides[-1].pageElements[]?.objectId")

OBJECT_IDS_MAP="{\"${TEMPLATE_SLIDE_ID}\": \"${NEW_SLIDE_ID}\""
ELEM_IDX=0
for EID in $ELEMENT_IDS; do
  NEW_EID="${EID}_copy_${ELEM_IDX}_$(date +%s)"
  OBJECT_IDS_MAP="${OBJECT_IDS_MAP}, \"${EID}\": \"${NEW_EID}\""
  ELEM_IDX=$((ELEM_IDX + 1))
done
OBJECT_IDS_MAP="${OBJECT_IDS_MAP}}"

DUPLICATE_RESULT=$(gws slides presentations batchUpdate \
  --params "{\"presentationId\": \"${PRESENTATION_ID}\"}" \
  --json "{
    \"requests\": [
      {
        \"duplicateObject\": {
          \"objectId\": \"${TEMPLATE_SLIDE_ID}\",
          \"objectIds\": ${OBJECT_IDS_MAP}
        }
      }
    ]
  }" \
  --format json 2>/dev/null)

echo "✅ スライド複製完了: ${NEW_SLIDE_ID}"

# =============================================================================
# Step 4: テキストの書き換え (deleteText + insertText)
# =============================================================================
echo ""
echo "✏️  Step 4: テキストの書き換え..."
echo "  ※ 実際の使用時は、以下の変数を編集してください"

# 例: タイトルと本文を書き換える
# ※ 実際の要素 ID はテンプレートによって異なります
# TITLE_ELEMENT_ID="対象のテキストボックスID"
# BODY_ELEMENT_ID="対象のテキストボックスID"
# NEW_TITLE="新しいタイトル"
# NEW_BODY="新しい本文テキスト"

# テキスト書き換えのサンプルコマンド（コメントアウト）:
# gws slides presentations batchUpdate \
#   --params "{\"presentationId\": \"${PRESENTATION_ID}\"}" \
#   --json "{
#     \"requests\": [
#       {
#         \"deleteText\": {
#           \"objectId\": \"${TITLE_ELEMENT_ID}\",
#           \"textRange\": {\"type\": \"ALL\"}
#         }
#       },
#       {
#         \"insertText\": {
#           \"objectId\": \"${TITLE_ELEMENT_ID}\",
#           \"text\": \"${NEW_TITLE}\",
#           \"insertionIndex\": 0
#         }
#       },
#       {
#         \"deleteText\": {
#           \"objectId\": \"${BODY_ELEMENT_ID}\",
#           \"textRange\": {\"type\": \"ALL\"}
#         }
#       },
#       {
#         \"insertText\": {
#           \"objectId\": \"${BODY_ELEMENT_ID}\",
#           \"text\": \"${NEW_BODY}\",
#           \"insertionIndex\": 0
#         }
#       }
#     ]
#   }"

echo "  ⚠️  テキスト書き換えは要素 ID を確認してから実行してください"

# =============================================================================
# Step 5: 画像の差し替え (replaceImage)
# =============================================================================
echo ""
echo "🖼️  Step 5: 画像差し替え..."
echo "  ※ replaceImage を使えば、サイズ・位置を保ったまま画像を差し替えられます"

# 画像差し替えのサンプルコマンド（コメントアウト）:
# IMAGE_ELEMENT_ID="対象の画像ID"
# NEW_IMAGE_URL="https://example.com/new-image.jpg"
#
# gws slides presentations batchUpdate \
#   --params "{\"presentationId\": \"${PRESENTATION_ID}\"}" \
#   --json "{
#     \"requests\": [
#       {
#         \"replaceImage\": {
#           \"imageObjectId\": \"${IMAGE_ELEMENT_ID}\",
#           \"url\": \"${NEW_IMAGE_URL}\",
#           \"imageReplaceMethod\": \"CENTER_CROP\"
#         }
#       }
#     ]
#   }"

echo "  ⚠️  画像差し替えは要素 ID と画像 URL を確認してから実行してください"
echo ""
echo "✅ UC1 完了: https://docs.google.com/presentation/d/${PRESENTATION_ID}/edit"
