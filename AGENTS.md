# Repository Guidelines

## Project Structure & Module Organization
This repository is an Agent Swarm template, not an application service. Most files live at the root:
- `setup.sh`: installs template assets into a target repo (`.clawdbot/`).
- `spawn-agent.sh`, `check-agents.sh`, `cleanup-worktrees.sh`, `notify.sh`: core automation scripts (intended to run from `.clawdbot/scripts/` after install).
- `agent-config.yaml`: default configuration template.
- `backend-feature.md`, `bugfix.md`, `AGENT-SWARM-TEMPLATE.md`: prompt and architecture docs.

When installed, runtime state lives in `.clawdbot/active-tasks.json`, `.clawdbot/learnings.jsonl`, and `.clawdbot/monitor.log`.

## Build, Test, and Development Commands
- `bash setup.sh /path/to/repo`: create `.clawdbot/` structure in a target repository.
- `bash setup.sh .`: bootstrap the current repo for local testing.
- `bash spawn-agent.sh --help`: list task-launch options (`--name`, `--agent`, `--prompt`, `--prompt-file`).
- `bash check-agents.sh`: run one monitoring pass (normally scheduled via cron).
- `bash cleanup-worktrees.sh`: remove completed worktrees and task records.
- `bash -n *.sh`: syntax-check shell scripts quickly.
- `shellcheck *.sh`: lint scripts (recommended before PRs).

## Coding Style & Naming Conventions
- Use Bash with strict mode: `#!/usr/bin/env bash` and `set -euo pipefail`.
- Prefer 2-space indentation and readable section blocks.
- Use `UPPER_SNAKE_CASE` for constants/global config, lower-case function names (for example, `log()`).
- Keep script filenames in kebab-case: `check-agents.sh`.
- Keep JSON/YAML keys stable and descriptive (for example, `max_concurrent_agents`, `notifyOnComplete`).

## Testing Guidelines
There is no formal unit-test suite in this template. Minimum validation for changes:
- Run `bash -n *.sh` and `shellcheck *.sh`.
- Smoke-test in a temporary repo by running `setup.sh`, spawning one task, and running `check-agents.sh`.
- For bug fixes, include a reproducible scenario and expected result in the PR description.

## Commit & Pull Request Guidelines
Project templates and prompts require Conventional Commits; follow `type(scope): summary` (for example, `fix(monitor): handle missing PR checks`).
Use task branches like `feat/<task-name>` to match `spawn-agent.sh` behavior.
PRs should include:
- What changed and why.
- Validation steps/command output.
- Linked issue/task.
- Screenshots when UI behavior changes (required by the template’s Definition of Done).
