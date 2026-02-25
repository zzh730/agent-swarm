# Agent Swarm Template

> 从 Elvis 的 OpenClaw + Codex/Claude Code 架构中提炼，适用于任意 repo。

## 核心架构：两层分离

```
┌─────────────────────────────────────────────┐
│              YOU (Human)                     │
│   决策 · 审批 · 方向把控                       │
└──────────────────┬──────────────────────────┘
                   │ Telegram / Slack / Discord 通知
┌──────────────────▼──────────────────────────┐
│         ORCHESTRATOR (Zoe 层)                │
│                                              │
│  持有：业务上下文 · 客户数据 · 会议纪要         │
│        历史决策 · 失败记录 · prompt 模板        │
│                                              │
│  职责：                                       │
│   1. 将业务需求翻译为精确的 coding prompt      │
│   2. 选择合适的 agent (Codex/CC/Gemini)       │
│   3. 监控 agent 进度，失败时 rewrite prompt    │
│   4. 主动扫描 (Sentry/会议/git log) 发现任务   │
└──┬───────┬───────┬──────────────────────────┘
   │       │       │  每个 agent 独立 worktree + tmux
┌──▼──┐ ┌─▼───┐ ┌─▼────┐
│Codex│ │ CC  │ │Gemini│   ← 只看代码，不看业务
│Agent│ │Agent│ │Agent │
└──┬──┘ └──┬──┘ └──┬───┘
   │       │       │
   └───────┼───────┘
           ▼
     Git PR → CI → 3x AI Review → Human Merge
```

**核心洞察：Context window 是零和博弈。**
填满代码 → 没有业务上下文空间；填满业务 → 没有代码空间。
所以必须分层：orchestrator 持有业务上下文，coding agent 只持有代码上下文。

---

## 快速开始

### 1. 目录结构

在你的 repo 根目录创建：

```
your-repo/
├── .clawdbot/
│   ├── active-tasks.json          # Agent 任务注册表
│   ├── prompt-templates/          # Prompt 模板库
│   │   ├── backend-feature.md
│   │   ├── frontend-feature.md
│   │   ├── bugfix.md
│   │   └── refactor.md
│   ├── scripts/
│   │   ├── spawn-agent.sh         # 启动 agent
│   │   ├── check-agents.sh        # 监控 cron
│   │   ├── cleanup-worktrees.sh   # 清理
│   │   └── notify.sh              # 通知
│   ├── learnings.jsonl            # Prompt 成功/失败记录
│   └── agent-config.yaml          # 全局配置
```

### 2. 安装依赖

```bash
# CLI 工具
brew install gh tmux jq

# Coding agents (至少装一个)
npm install -g @anthropic-ai/claude-code
npm install -g @openai/codex

# 可选：通知 (使用 webhook / bot token，无额外 Python 依赖)
# TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID
# SLACK_WEBHOOK_URL
# DISCORD_WEBHOOK_URL 或 DISCORD_BOT_TOKEN + DISCORD_CHANNEL_ID
```

### 3. 配置

复制 `.clawdbot/agent-config.yaml` 到你的 repo，按需修改。

### 4. 运行

```bash
# 启动一个 agent
.clawdbot/scripts/spawn-agent.sh \
  --name "feat-user-auth" \
  --agent "claude-code" \
  --prompt "Implement OAuth2 login flow..."

# 设置监控 cron (每 10 分钟)
crontab -e
# */10 * * * * /path/to/repo/.clawdbot/scripts/check-agents.sh
```

---

## 八步工作流详解

### Step 1: 需求 → Orchestrator 理解

Orchestrator 需要访问你的业务上下文源：

| 上下文源 | 接入方式 | 用途 |
|---------|---------|------|
| 会议纪要 | Obsidian vault / Notion API | 理解客户需求的原始语境 |
| 客户数据 | Read-only DB access | 拉取真实配置写入 prompt |
| Sentry/日志 | API | 主动发现 bug |
| Git history | `git log` | 了解代码变更历史 |
| 历史 prompt | `learnings.jsonl` | 知道什么 prompt 结构有效 |

Orchestrator 做三件事：
1. **理解需求**（结合业务上下文）
2. **准备数据**（从 DB/API 拉取 agent 需要的真实数据）
3. **生成精确 prompt**（包含所有必要上下文）

### Step 2: 启动 Agent

每个 agent 运行在**独立 worktree + 独立 tmux session**：

```bash
# 1. 创建隔离的 worktree
git worktree add ../worktrees/feat-xxx -b feat/xxx origin/main
cd ../worktrees/feat-xxx && <your-install-cmd>  # npm/pnpm/pip install

# 2. 在 tmux 中启动 agent
tmux new-session -d -s "agent-feat-xxx" \
  -c "/path/to/worktrees/feat-xxx" \
  ".clawdbot/scripts/run-agent.sh feat-xxx claude-code high"
```

**为什么用 tmux 而不是 `claude -p`？**
→ 可以中途纠偏。Agent 方向不对时，直接向 tmux session 发送修正指令，不用 kill 重启。

### Step 3: 监控循环 (Cron)

每 10 分钟跑一次，**零 token 消耗**的纯确定性检查：

```
check-agents.sh 检查项:
├── tmux session 是否还活着？
├── 对应 branch 是否有 open PR？
├── CI 状态？ (gh pr checks)
├── 如果 CI 失败 → 自动 respawn (最多 3 次)
└── 如果全部通过 → 发通知
```

### Step 4: Agent 创建 PR

Agent 完成后自动：`git add . && git commit && git push && gh pr create --fill`

**"Done" 的定义（写入 agent prompt 中）：**

- [ ] PR 已创建
- [ ] Branch 已 sync main（无冲突）
- [ ] CI 全绿（lint, types, unit tests, E2E）
- [ ] 包含截图（如果有 UI 变更）

### Step 5: 三模型交叉 Review

| Reviewer | 强项 | 弱项 |
|----------|------|------|
| **Codex** | 边界情况、逻辑错误、竞态条件 | 较慢 |
| **Gemini Code Assist** | 安全问题、可扩展性（免费） | - |
| **Claude Code** | 验证其他 reviewer 的发现 | 过于保守，噪音多 |

配置方式：GitHub Actions 或 PR webhook 触发三个 review bot。

### Step 6: CI 自动测试

标准 pipeline + 一条额外规则：
> **UI 变更必须附截图，否则 CI 失败。**

### Step 7: Human Review

此时你收到通知。PR 已经过：CI ✅ + 3x AI Review ✅ + 截图 ✅
→ 你的 review 时间：5-10 分钟，很多 PR 看截图就能 merge。

### Step 8: Merge + 清理

合并后，daily cron 清理孤立 worktree 和 task JSON。

---

## Ralph Loop V2：自适应重试

这是整个系统最核心的差异化。普通 retry 是同一个 prompt 重跑。
Orchestrator 的 retry 是**带上下文分析的 prompt 重写**：

```
Agent 失败
    │
    ▼
Orchestrator 分析失败原因
    │
    ├─ Context 溢出？ → 缩小范围："只关注这 3 个文件"
    ├─ 方向错误？   → 纠偏："客户要的是 X 不是 Y，原话是..."
    ├─ 缺少信息？   → 补充："这是客户的邮件和公司背景"
    └─ 技术障碍？   → 换 agent 或拆分任务
    │
    ▼
用新 prompt Respawn（最多 3 次）
    │
    ▼
成功 → 记录到 learnings.jsonl
```

**成功信号**：CI passing + 3x review passing + human merge
**失败信号**：CI fail / review rejection / human rejection
每次结果都记录，orchestrator 学习什么 prompt 结构对什么类型的任务有效。

---

## Agent 选型指南

```
任务类型                    推荐 Agent        原因
─────────────────────────────────────────────────────
后端逻辑 / 复杂 bug         Codex             推理能力强，跨文件分析
多文件重构                  Codex             全局理解好
前端 / UI 实现              Claude Code       速度快，前端能力强
Git 操作 / 脚本             Claude Code       权限问题少
UI 设计稿 / 美学            Gemini → CC       Gemini 出设计，CC 实现
文档 / Changelog            Claude Code       写作能力好
简单 fix / 配置修改          任意              哪个便宜用哪个
```

---

## Orchestrator 主动扫描模式

不只是被动接受任务，orchestrator 可以主动发现工作：

| 时间 | 扫描源 | 行为 |
|------|--------|------|
| 早晨 | Sentry 错误 | 发现 4 个新错误 → spawn 4 个修复 agent |
| 会后 | 会议纪要 | 提取 3 个功能需求 → spawn 3 个 Codex agent |
| 晚间 | Git log | 更新 changelog 和客户文档 |

---

## 硬件考量

每个 agent = 1 个 worktree + node_modules + 编译器 + 测试运行器

| 配置 | 并发 Agent 数 | 备注 |
|------|-------------|------|
| 16GB RAM | 4-5 | 容易 swap，编译冲突 |
| 32GB RAM | 8-10 | 日常够用 |
| 64GB+ RAM | 15+ | 重度使用 |

**月成本参考**：Claude ~$100 + Codex ~$90，入门可从 $20 起。

---

## 文件清单

本 template 包含以下可直接使用的文件：

| 文件 | 说明 |
|------|------|
| `agent-config.yaml` | 全局配置 |
| `active-tasks.json` | 任务注册表（初始为空） |
| `scripts/spawn-agent.sh` | 启动 agent 脚本 |
| `scripts/check-agents.sh` | 监控 cron 脚本 |
| `scripts/cleanup-worktrees.sh` | 清理脚本 |
| `scripts/notify.sh` | 通知脚本 |
| `prompt-templates/*.md` | Prompt 模板 |

把 `.clawdbot/` 目录复制到任意 repo 即可使用。
