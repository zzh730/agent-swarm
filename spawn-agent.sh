#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# spawn-agent.sh — 启动一个隔离的 coding agent
# 用法: spawn-agent.sh --name <task-name> --agent <codex|claude-code|gemini> --prompt <prompt-text-or-file>
# ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWDBOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$CLAWDBOT_DIR/agent-config.yaml"
TASKS_FILE="$CLAWDBOT_DIR/active-tasks.json"

# ── 默认值 ──
AGENT_TYPE="codex"
TASK_NAME=""
PROMPT=""
PROMPT_FILE=""
EFFORT="high"
NOTIFY=true

# ── 解析参数 ──
while [[ $# -gt 0 ]]; do
  case $1 in
    --name)       TASK_NAME="$2"; shift 2 ;;
    --agent)      AGENT_TYPE="$2"; shift 2 ;;
    --prompt)     PROMPT="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --effort)     EFFORT="$2"; shift 2 ;;
    --no-notify)  NOTIFY=false; shift ;;
    -h|--help)
      echo "用法: spawn-agent.sh --name <task-name> --agent <codex|claude-code> --prompt <text>"
      echo ""
      echo "参数:"
      echo "  --name        任务名 (将用作 branch 名: feat/<name>)"
      echo "  --agent       agent 类型: codex | claude-code | gemini"
      echo "  --prompt      prompt 文本"
      echo "  --prompt-file prompt 文件路径"
      echo "  --effort      reasoning effort: low | medium | high (默认 high)"
      echo "  --no-notify   完成后不通知"
      exit 0
      ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# ── 校验 ──
if [[ -z "$TASK_NAME" ]]; then
  echo "❌ 必须指定 --name"
  exit 1
fi

if [[ -z "$PROMPT" && -z "$PROMPT_FILE" ]]; then
  echo "❌ 必须指定 --prompt 或 --prompt-file"
  exit 1
fi

if [[ -n "$PROMPT_FILE" ]]; then
  PROMPT="$(cat "$PROMPT_FILE")"
fi

# ── 读取配置 ──
# 简化版：用 grep/sed 从 yaml 提取值（生产环境建议用 yq）
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DEFAULT_BRANCH=$(grep 'default_branch:' "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '"')
INSTALL_CMD=$(grep 'install_cmd:' "$CONFIG_FILE" | head -1 | awk -F'"' '{print $2}')
WORKTREE_DIR=$(grep 'worktree_dir:' "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '"')
MAX_AGENTS=$(grep 'max_concurrent_agents:' "$CONFIG_FILE" | head -1 | awk '{print $2}')

DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
INSTALL_CMD="${INSTALL_CMD:-npm install}"
WORKTREE_DIR="${WORKTREE_DIR:-../worktrees}"
MAX_AGENTS="${MAX_AGENTS:-5}"

# ── 检查并发上限 ──
CURRENT_AGENTS=$(tmux list-sessions 2>/dev/null | grep -c "^agent-" || true)
if [[ "$CURRENT_AGENTS" -ge "$MAX_AGENTS" ]]; then
  echo "⚠️  已达到并发上限 ($MAX_AGENTS agents)。等待现有 agent 完成或增加上限。"
  echo "当前运行中:"
  tmux list-sessions 2>/dev/null | grep "^agent-" || true
  exit 1
fi

# ── 创建 worktree ──
BRANCH_NAME="feat/$TASK_NAME"
WORKTREE_PATH="$WORKTREE_DIR/$TASK_NAME"
TMUX_SESSION="agent-$TASK_NAME"

echo "📦 创建 worktree: $WORKTREE_PATH (branch: $BRANCH_NAME)"
cd "$REPO_ROOT"
git fetch origin "$DEFAULT_BRANCH" --quiet

# 如果 worktree 已存在，先清理
if [[ -d "$WORKTREE_PATH" ]]; then
  echo "⚠️  Worktree 已存在，清理中..."
  git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || true
fi

git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" "origin/$DEFAULT_BRANCH" 2>/dev/null || \
  git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>/dev/null || \
  { echo "❌ 无法创建 worktree"; exit 1; }

echo "📥 安装依赖..."
cd "$WORKTREE_PATH" && eval "$INSTALL_CMD" --silent 2>/dev/null || eval "$INSTALL_CMD"

# ── 构建 agent 命令 ──
# 在 prompt 末尾追加 Definition of Done
DOD=$(cat <<'EOF'

---
## Definition of Done (你必须完成以下所有项):
1. 所有代码修改已完成并通过本地验证
2. git add, commit (使用 conventional commits 格式)
3. git push origin <your-branch>
4. gh pr create --fill (创建 PR)
5. 如果有 UI 变更，在 PR 描述中包含截图
6. 确认无 merge conflict
EOF
)

FULL_PROMPT="${PROMPT}${DOD}"

case "$AGENT_TYPE" in
  codex)
    AGENT_CMD="codex --model gpt-5.3-codex -c \"model_reasoning_effort=$EFFORT\" --dangerously-bypass-approvals-and-sandbox \"$FULL_PROMPT\""
    ;;
  claude-code|claude)
    AGENT_CMD="claude --model claude-opus-4.5 --dangerously-skip-permissions -p \"$FULL_PROMPT\""
    ;;
  gemini)
    AGENT_CMD="gemini \"$FULL_PROMPT\""
    ;;
  *)
    echo "❌ 未知 agent 类型: $AGENT_TYPE (可选: codex, claude-code, gemini)"
    exit 1
    ;;
esac

# ── 启动 tmux session ──
echo "🚀 启动 agent: $TMUX_SESSION (type: $AGENT_TYPE)"

# 如果已有同名 session，kill 它
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

# 创建 agent 运行脚本（带日志）
AGENT_SCRIPT="$WORKTREE_PATH/.agent-run.sh"
cat > "$AGENT_SCRIPT" <<SCRIPT
#!/usr/bin/env bash
cd "$WORKTREE_PATH"
echo "[\$(date)] Agent started: $AGENT_TYPE | Task: $TASK_NAME" | tee -a .agent.log

# 运行 agent
$AGENT_CMD 2>&1 | tee -a .agent.log

EXIT_CODE=\$?
echo "[\$(date)] Agent exited with code: \$EXIT_CODE" | tee -a .agent.log

# 标记完成
if [[ \$EXIT_CODE -eq 0 ]]; then
  echo "AGENT_STATUS=completed" >> .agent.log
else
  echo "AGENT_STATUS=failed" >> .agent.log
fi
SCRIPT
chmod +x "$AGENT_SCRIPT"

tmux new-session -d -s "$TMUX_SESSION" -c "$WORKTREE_PATH" "$AGENT_SCRIPT"

# ── 注册任务 ──
# 确保 tasks 文件存在
if [[ ! -f "$TASKS_FILE" ]]; then
  echo "[]" > "$TASKS_FILE"
fi

TIMESTAMP=$(date +%s)000

# 用 jq 追加任务
TASK_JSON=$(cat <<EOF
{
  "id": "$TASK_NAME",
  "tmuxSession": "$TMUX_SESSION",
  "agent": "$AGENT_TYPE",
  "description": "",
  "branch": "$BRANCH_NAME",
  "worktree": "$WORKTREE_PATH",
  "startedAt": $TIMESTAMP,
  "status": "running",
  "retries": 0,
  "notifyOnComplete": $NOTIFY
}
EOF
)

# 移除同 id 旧记录，追加新记录
jq --argjson task "$TASK_JSON" '[.[] | select(.id != $task.id)] + [$task]' "$TASKS_FILE" > "$TASKS_FILE.tmp" \
  && mv "$TASKS_FILE.tmp" "$TASKS_FILE"

echo ""
echo "✅ Agent 已启动"
echo "   Session:  $TMUX_SESSION"
echo "   Branch:   $BRANCH_NAME"
echo "   Worktree: $WORKTREE_PATH"
echo ""
echo "📋 常用命令:"
echo "   tmux attach -t $TMUX_SESSION          # 查看 agent 实时输出"
echo "   tmux send-keys -t $TMUX_SESSION '...' # 向 agent 发送纠偏指令"
echo "   tmux kill-session -t $TMUX_SESSION    # 终止 agent"
