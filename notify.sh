#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# notify.sh — 发送通知 (Telegram / Slack / Discord / stdout)
# 用法: notify.sh "message text"
# ──────────────────────────────────────────────

MESSAGE="${1:-No message}"
SENT=0

# ── Telegram ──
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="$MESSAGE" \
    -d parse_mode="HTML" > /dev/null 2>&1 && SENT=1 || true
fi

# ── Slack ──
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
  PAYLOAD=$(jq -nc --arg text "$MESSAGE" '{text: $text}')
  curl -sS -X POST "${SLACK_WEBHOOK_URL}" \
    -H 'Content-Type: application/json' \
    -d "$PAYLOAD" > /dev/null 2>&1 && SENT=1 || true
fi

# ── Discord Webhook ──
if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
  PAYLOAD=$(jq -nc --arg content "$MESSAGE" '{content: $content}')
  curl -sS -X POST "${DISCORD_WEBHOOK_URL}" \
    -H 'Content-Type: application/json' \
    -d "$PAYLOAD" > /dev/null 2>&1 && SENT=1 || true
fi

# ── Discord Bot API ──
if [[ -n "${DISCORD_BOT_TOKEN:-}" && -n "${DISCORD_CHANNEL_ID:-}" ]]; then
  PAYLOAD=$(jq -nc --arg content "$MESSAGE" '{content: $content}')
  curl -sS -X POST "https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages" \
    -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "$PAYLOAD" > /dev/null 2>&1 && SENT=1 || true
fi

if [[ "$SENT" -eq 0 ]]; then
  # ── Fallback: stdout ──
  echo -e "$MESSAGE"
fi
