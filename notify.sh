#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# notify.sh — 发送通知 (Telegram / Slack / stdout)
# 用法: notify.sh "message text"
# ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/agent-config.yaml"

MESSAGE="${1:-No message}"

# ── Telegram ──
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="$MESSAGE" \
    -d parse_mode="HTML" > /dev/null 2>&1 || true
  exit 0
fi

# ── Slack ──
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
  curl -s -X POST "${SLACK_WEBHOOK_URL}" \
    -H 'Content-Type: application/json' \
    -d "{\"text\": \"$MESSAGE\"}" > /dev/null 2>&1 || true
  exit 0
fi

# ── Fallback: stdout ──
echo -e "$MESSAGE"
