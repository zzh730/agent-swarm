#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# setup.sh — 一键安装 Agent Swarm 到你的 repo
# 用法: curl -sSL <url> | bash  或  bash setup.sh /path/to/your/repo
# ──────────────────────────────────────────────

TARGET_DIR="${1:-.}"

echo "🤖 Agent Swarm Setup"
echo "   目标目录: $TARGET_DIR"
echo ""

# ── 检查依赖 ──
MISSING=()
command -v git    >/dev/null 2>&1 || MISSING+=("git")
command -v gh     >/dev/null 2>&1 || MISSING+=("gh (GitHub CLI)")
command -v tmux   >/dev/null 2>&1 || MISSING+=("tmux")
command -v jq     >/dev/null 2>&1 || MISSING+=("jq")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "❌ 缺少以下工具，请先安装:"
  for tool in "${MISSING[@]}"; do
    echo "   - $tool"
  done
  echo ""
  echo "macOS: brew install gh tmux jq"
  echo "Linux: sudo apt install gh tmux jq"
  exit 1
fi

# ── 检查 coding agent ──
HAS_AGENT=false
if command -v codex >/dev/null 2>&1; then
  echo "✅ 检测到 Codex"
  HAS_AGENT=true
fi
if command -v claude >/dev/null 2>&1; then
  echo "✅ 检测到 Claude Code"
  HAS_AGENT=true
fi

if [[ "$HAS_AGENT" == "false" ]]; then
  echo "⚠️  未检测到 coding agent (codex 或 claude code)"
  echo "   npm install -g @anthropic-ai/claude-code"
  echo "   npm install -g @openai/codex"
  echo ""
fi

# ── 检查 gh 认证 ──
if ! gh auth status >/dev/null 2>&1; then
  echo "⚠️  GitHub CLI 未登录，请运行: gh auth login"
fi

# ── 创建目录结构 ──
cd "$TARGET_DIR"

echo ""
echo "📁 创建 .clawdbot/ 目录结构..."

mkdir -p .clawdbot/scripts
mkdir -p .clawdbot/prompt-templates

# 如果脚本和模板文件在同一目录（本 template），则复制
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -d "$TEMPLATE_DIR/.clawdbot" ]]; then
  cp -rn "$TEMPLATE_DIR/.clawdbot/"* .clawdbot/ 2>/dev/null || true
  echo "  ✅ 模板文件已复制"
fi

# ── 确保脚本可执行 ──
chmod +x .clawdbot/scripts/*.sh 2>/dev/null || true

# ── 初始化 tasks registry ──
if [[ ! -f .clawdbot/active-tasks.json ]]; then
  echo "[]" > .clawdbot/active-tasks.json
fi

# ── 创建 worktrees 目录 ──
WORKTREE_DIR="../worktrees"
mkdir -p "$WORKTREE_DIR" 2>/dev/null || true

# ── 添加 .gitignore 条目 ──
GITIGNORE=".gitignore"
ENTRIES=(
  ".clawdbot/active-tasks.json"
  ".clawdbot/learnings.jsonl"
  ".clawdbot/monitor.log"
  ".agent.log"
  ".agent-run.sh"
)

if [[ -f "$GITIGNORE" ]]; then
  for entry in "${ENTRIES[@]}"; do
    grep -qxF "$entry" "$GITIGNORE" 2>/dev/null || echo "$entry" >> "$GITIGNORE"
  done
  echo "  ✅ .gitignore 已更新"
else
  printf '%s\n' "${ENTRIES[@]}" > "$GITIGNORE"
  echo "  ✅ .gitignore 已创建"
fi

echo ""
echo "══════════════════════════════════════════"
echo "  ✅ Agent Swarm 安装完成!"
echo "══════════════════════════════════════════"
echo ""
echo "下一步:"
echo ""
echo "  1. 编辑配置:"
echo "     vim .clawdbot/agent-config.yaml"
echo ""
echo "  2. 启动你的第一个 agent:"
echo "     .clawdbot/scripts/spawn-agent.sh \\"
echo "       --name 'my-first-task' \\"
echo "       --agent 'claude-code' \\"
echo "       --prompt 'Add a health check endpoint at /api/health'"
echo ""
echo "  3. 设置监控 cron:"
echo "     crontab -e"
echo "     */10 * * * * $(pwd)/.clawdbot/scripts/check-agents.sh"
echo ""
echo "  4. 查看 agent 状态:"
echo "     tmux list-sessions"
echo "     cat .clawdbot/active-tasks.json | jq"
echo ""
