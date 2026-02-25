#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# check-agents.sh — 监控所有活跃 agent 的状态
# 设计原则: 100% 确定性检查，零 token 消耗
# Cron: */10 * * * * /path/to/.clawdbot/scripts/check-agents.sh
# ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWDBOT_DIR="$(dirname "$SCRIPT_DIR")"
TASKS_FILE="$CLAWDBOT_DIR/active-tasks.json"
LEARNINGS_FILE="$CLAWDBOT_DIR/learnings.jsonl"
LOG_FILE="$CLAWDBOT_DIR/monitor.log"
MAX_RETRIES=3

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# ── 确保依赖文件存在 ──
[[ -f "$TASKS_FILE" ]] || { echo "[]" > "$TASKS_FILE"; exit 0; }
[[ -f "$LEARNINGS_FILE" ]] || touch "$LEARNINGS_FILE"

# ── 获取所有 running 状态的任务 ──
RUNNING_TASKS=$(jq -c '.[] | select(.status == "running")' "$TASKS_FILE")

if [[ -z "$RUNNING_TASKS" ]]; then
  exit 0  # 无活跃任务，安静退出
fi

NEEDS_ATTENTION=()
COMPLETED=()

while IFS= read -r task; do
  TASK_ID=$(echo "$task" | jq -r '.id')
  TMUX_SESSION=$(echo "$task" | jq -r '.tmuxSession')
  BRANCH=$(echo "$task" | jq -r '.branch')
  AGENT_TYPE=$(echo "$task" | jq -r '.agent')
  RETRIES=$(echo "$task" | jq -r '.retries')
  NOTIFY=$(echo "$task" | jq -r '.notifyOnComplete')

  log "检查: $TASK_ID (agent: $AGENT_TYPE, session: $TMUX_SESSION)"

  # ── Check 1: tmux session 还活着吗？ ──
  SESSION_ALIVE=$(tmux has-session -t "$TMUX_SESSION" 2>/dev/null && echo "yes" || echo "no")

  # ── Check 2: 有没有对应的 open PR？ ──
  PR_NUMBER=$(gh pr list --head "$BRANCH" --state open --json number -q '.[0].number' 2>/dev/null || echo "")

  if [[ "$SESSION_ALIVE" == "yes" && -z "$PR_NUMBER" ]]; then
    log "  ⏳ Agent 仍在运行，无 PR"
    continue
  fi

  if [[ "$SESSION_ALIVE" == "no" && -z "$PR_NUMBER" ]]; then
    # Agent 死了且没有 PR → 失败
    log "  ❌ Agent 死亡，无 PR"

    if [[ "$RETRIES" -lt "$MAX_RETRIES" ]]; then
      log "  🔄 自动重试 ($((RETRIES + 1))/$MAX_RETRIES)"

      # 更新重试次数
      jq --arg id "$TASK_ID" \
        '(.[] | select(.id == $id)).retries += 1' \
        "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"

      # 记录失败
      echo "{\"task\":\"$TASK_ID\",\"agent\":\"$AGENT_TYPE\",\"result\":\"agent_died_no_pr\",\"retries\":$((RETRIES + 1)),\"timestamp\":\"$(date -u +%FT%TZ)\"}" >> "$LEARNINGS_FILE"

      # TODO: 这里可以调用 orchestrator 重写 prompt
      # 目前简单 respawn
      NEEDS_ATTENTION+=("$TASK_ID: Agent 死亡，已重试 $((RETRIES + 1)) 次")
    else
      log "  🛑 已达最大重试次数，需要人工介入"
      jq --arg id "$TASK_ID" \
        '(.[] | select(.id == $id)).status = "failed"' \
        "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"

      NEEDS_ATTENTION+=("$TASK_ID: ❌ 失败，需要人工介入")
    fi
    continue
  fi

  # ── Check 3: PR 存在，检查 CI 状态 ──
  if [[ -n "$PR_NUMBER" ]]; then
    log "  📝 PR #$PR_NUMBER 已创建"

    # 获取 CI 状态
    CI_STATUS=$(gh pr checks "$PR_NUMBER" --json 'name,state' 2>/dev/null || echo "[]")
    FAILED_CHECKS=$(echo "$CI_STATUS" | jq '[.[] | select(.state == "FAILURE")] | length' 2>/dev/null || echo "0")
    PENDING_CHECKS=$(echo "$CI_STATUS" | jq '[.[] | select(.state == "PENDING")] | length' 2>/dev/null || echo "0")

    if [[ "$PENDING_CHECKS" -gt 0 ]]; then
      log "  ⏳ CI 运行中 ($PENDING_CHECKS pending)"
      continue
    fi

    if [[ "$FAILED_CHECKS" -gt 0 ]]; then
      log "  ❌ CI 失败 ($FAILED_CHECKS checks failed)"

      if [[ "$RETRIES" -lt "$MAX_RETRIES" ]]; then
        log "  🔄 CI 失败，自动重试 ($((RETRIES + 1))/$MAX_RETRIES)"

        jq --arg id "$TASK_ID" \
          '(.[] | select(.id == $id)).retries += 1' \
          "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"

        echo "{\"task\":\"$TASK_ID\",\"agent\":\"$AGENT_TYPE\",\"result\":\"ci_failed\",\"checks\":$CI_STATUS,\"retries\":$((RETRIES + 1)),\"timestamp\":\"$(date -u +%FT%TZ)\"}" >> "$LEARNINGS_FILE"

        NEEDS_ATTENTION+=("$TASK_ID: CI 失败, PR #$PR_NUMBER, 重试 $((RETRIES + 1))")
      else
        jq --arg id "$TASK_ID" \
          '(.[] | select(.id == $id)).status = "ci_failed"' \
          "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"

        NEEDS_ATTENTION+=("$TASK_ID: ❌ CI 持续失败, PR #$PR_NUMBER, 需要人工介入")
      fi
      continue
    fi

    # ── Check 4: CI 全绿 → 检查 review 状态 ──
    REVIEW_STATUS=$(gh pr view "$PR_NUMBER" --json reviewDecision -q '.reviewDecision' 2>/dev/null || echo "")

    # 所有检查通过！
    log "  ✅ PR #$PR_NUMBER — CI 通过, 准备 review"

    TIMESTAMP=$(date +%s)000
    jq --arg id "$TASK_ID" --arg pr "$PR_NUMBER" --argjson ts "$TIMESTAMP" \
      '(.[] | select(.id == $id)) |= . + {
        "status": "ready_for_review",
        "pr": ($pr | tonumber),
        "completedAt": $ts,
        "checks": {
          "prCreated": true,
          "ciPassed": true
        }
      }' "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"

    # 记录成功
    echo "{\"task\":\"$TASK_ID\",\"agent\":\"$AGENT_TYPE\",\"result\":\"ready_for_review\",\"pr\":$PR_NUMBER,\"timestamp\":\"$(date -u +%FT%TZ)\"}" >> "$LEARNINGS_FILE"

    COMPLETED+=("$TASK_ID: ✅ PR #$PR_NUMBER ready for review")

    # Kill tmux session (agent 已完成)
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
  fi

done <<< "$RUNNING_TASKS"

# ── 发送通知 ──
if [[ ${#COMPLETED[@]} -gt 0 || ${#NEEDS_ATTENTION[@]} -gt 0 ]]; then
  MESSAGE=""

  if [[ ${#COMPLETED[@]} -gt 0 ]]; then
    MESSAGE+="🎉 Ready for review:\n"
    for item in "${COMPLETED[@]}"; do
      MESSAGE+="  $item\n"
    done
  fi

  if [[ ${#NEEDS_ATTENTION[@]} -gt 0 ]]; then
    MESSAGE+="\n⚠️ Needs attention:\n"
    for item in "${NEEDS_ATTENTION[@]}"; do
      MESSAGE+="  $item\n"
    done
  fi

  log "$MESSAGE"

  # 调用通知脚本
  "$SCRIPT_DIR/notify.sh" "$MESSAGE"
fi
