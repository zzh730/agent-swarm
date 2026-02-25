#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# cleanup-worktrees.sh — 清理已完成任务的 worktree
# 建议: daily cron 运行
# Cron: 0 3 * * * /path/to/.clawdbot/scripts/cleanup-worktrees.sh
# ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWDBOT_DIR="$(dirname "$SCRIPT_DIR")"
TASKS_FILE="$CLAWDBOT_DIR/active-tasks.json"

[[ -f "$TASKS_FILE" ]] || exit 0

echo "🧹 开始清理..."

# ── 清理已合并的任务 ──
DONE_TASKS=$(jq -c '.[] | select(.status == "merged" or .status == "done")' "$TASKS_FILE")

CLEANED=0
while IFS= read -r task; do
  [[ -z "$task" ]] && continue

  TASK_ID=$(echo "$task" | jq -r '.id')
  WORKTREE=$(echo "$task" | jq -r '.worktree')
  BRANCH=$(echo "$task" | jq -r '.branch')
  TMUX_SESSION=$(echo "$task" | jq -r '.tmuxSession')

  echo "  清理: $TASK_ID"

  # Kill tmux session (如果还在)
  tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

  # 移除 worktree
  if [[ -d "$WORKTREE" ]]; then
    git worktree remove "$WORKTREE" --force 2>/dev/null || true
  fi

  # 删除已合并的 branch
  git branch -D "$BRANCH" 2>/dev/null || true

  ((CLEANED++)) || true
done <<< "$DONE_TASKS"

# ── 从 tasks.json 中移除已清理的任务 ──
jq '[.[] | select(.status != "merged" and .status != "done")]' "$TASKS_FILE" > "$TASKS_FILE.tmp" \
  && mv "$TASKS_FILE.tmp" "$TASKS_FILE"

# ── 清理 git worktree 的孤立引用 ──
git worktree prune 2>/dev/null || true

echo "✅ 清理完成: $CLEANED 个任务"
