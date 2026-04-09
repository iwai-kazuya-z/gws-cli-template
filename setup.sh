#!/bin/bash
# =============================================================================
# GWS CLI セットアップスクリプト
# 参考: https://zenn.dev/emuni/articles/gws-cli-practical-guide
# =============================================================================

set -euo pipefail

echo "========================================="
echo "  GWS CLI セットアップ"
echo "========================================="

# ─── 1. GWS CLI インストール確認 ───
echo ""
echo "[1/4] GWS CLI インストール確認..."
if command -v gws &> /dev/null; then
  echo "  ✅ GWS CLI already installed: $(gws --version 2>&1 | head -1)"
else
  echo "  📦 GWS CLI をインストール中..."
  npm install -g @googleworkspace/cli
  echo "  ✅ インストール完了: $(gws --version 2>&1 | head -1)"
fi

# ─── 2. 依存ツールの確認 ───
echo ""
echo "[2/4] 依存ツールの確認..."

# gcloud CLI
if command -v gcloud &> /dev/null; then
  echo "  ✅ gcloud CLI: $(gcloud --version 2>&1 | head -1)"
else
  echo "  ⚠️  gcloud CLI が見つかりません。"
  echo "     インストール: https://cloud.google.com/sdk/docs/install"
  echo "     brew install --cask google-cloud-sdk (macOS)"
fi

# jq (JSON 処理)
if command -v jq &> /dev/null; then
  echo "  ✅ jq: $(jq --version 2>&1)"
else
  echo "  ❌ jq が見つかりません（全スクリプトで必須）"
  echo "     brew install jq (macOS) / apt install jq (Ubuntu)"
fi

# python3 (UC2, UC3 で使用)
if command -v python3 &> /dev/null; then
  echo "  ✅ python3: $(python3 --version 2>&1)"
else
  echo "  ⚠️  python3 が見つかりません（UC2, UC3 で必要）"
fi

# gh CLI (UC3 で使用)
if command -v gh &> /dev/null; then
  echo "  ✅ gh CLI: $(gh --version 2>&1 | head -1)"
else
  echo "  ⚠️  gh CLI が見つかりません（UC3 で必要）"
  echo "     brew install gh (macOS) / https://cli.github.com/"
fi

# ─── 3. .env ファイルの確認 ───
echo ""
echo "[3/4] 環境変数の確認..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
  echo "  ✅ .env ファイルが見つかりました"
  # .env をロード（クレデンシャルをエコーしない）
  set -a
  source "$ENV_FILE"
  set +a
  echo "  ✅ 環境変数をロードしました"
else
  echo "  ⚠️  .env ファイルが見つかりません"
  echo "  .env.example をコピーして設定してください:"
  echo "    cp ${SCRIPT_DIR}/.env.example ${SCRIPT_DIR}/.env"
  echo "    vim ${SCRIPT_DIR}/.env"
fi

# ─── 4. GCP API の有効化 ───
echo ""
echo "[4/4] GCP API の有効化..."

if [ -z "${GCP_PROJECT_ID:-}" ]; then
  echo "  ⚠️  GCP_PROJECT_ID が設定されていません。.env で設定してください。"
  echo "  API の有効化はスキップします。"
else
  echo "  GCP Project: ${GCP_PROJECT_ID}"
  gcloud config set project "${GCP_PROJECT_ID}" 2>/dev/null

  echo "  必要な API を有効化中..."
  gcloud services enable \
    gmail.googleapis.com \
    calendar-json.googleapis.com \
    drive.googleapis.com \
    sheets.googleapis.com \
    docs.googleapis.com \
    slides.googleapis.com \
    admin.googleapis.com \
    people.googleapis.com \
    analyticsdata.googleapis.com \
    2>/dev/null && echo "  ✅ API 有効化完了" || echo "  ⚠️  一部 API の有効化に失敗しました（権限を確認してください）"
fi

# ─── 5. 認証 ───
echo ""
echo "========================================="
echo "  セットアップ完了！"
echo "========================================="
echo ""
echo "次のステップ:"
echo "  1. .env にクレデンシャルを設定（まだの場合）"
echo "  2. 認証を実行:"
echo "     source .env && gws auth login"
echo ""
echo "  ※ スコープを限定したい場合:"
echo '     gws auth login --scopes "https://www.googleapis.com/auth/drive,https://www.googleapis.com/auth/spreadsheets,https://www.googleapis.com/auth/gmail.readonly"'
echo ""
