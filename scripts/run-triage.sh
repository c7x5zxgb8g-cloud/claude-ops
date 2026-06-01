#!/usr/bin/env bash
# 可选支线：以 headless 模式跑一轮 triage。
#
# 默认推荐路径是先运行 ./scripts/start-ops.sh，在交互式 Claude Code pane 中执行 /triage。
# 只有当你明确需要 cron / systemd 这类无人值守运行时，才使用本脚本。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO"

# --- 非交互环境很干净，下面几件事必须显式处理，否则无人值守时容易踩坑 ---
# 1) PATH 里通常没有 claude，补上常见安装位置
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
# 2) 鉴权不在这里替你选择：先确保当前环境里的 `claude -p` 能正常运行。
#    你可以使用 Claude Code 已有登录态，也可以按自己的部署方式配置环境变量。
# 3) 工作目录已在上面 cd 好。

LOG_DIR="ops-state/run-logs"
mkdir -p "$LOG_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$LOG_DIR/$STAMP.log"

# 防重入：上一轮没跑完就被再次拉起时，直接跳过（非阻塞锁）
exec 9>"$LOG_DIR/.lock"
if ! flock -n 9; then
  echo "[$STAMP] 上一轮仍在运行，跳过本次。" >>"$LOG"
  exit 0
fi

PROMPT='执行一轮完整运维循环，严格按 CLAUDE.md 的工作流：先读 ops-state/project-facts.md 确认日志源清单（多 agent 系统通常有多个日志文件）；按清单读取各日志的最新内容并提取异常信号；用 ops-state/issues.json 去重并更新状态；对每个值得修复的新问题用 bug-fixer subagent 处理（按 Task Spec 构造自包含 prompt）；收齐 Result Summary 后写回 issues.json；最后把系统运行状态报告写入 ops-state/reports/。只产出结论，不要贴 subagent 的中间过程。'

# --permission-mode acceptEdits：自动接受文件编辑，避免在无 TTY 的 cron 里卡在权限询问
# --allowedTools 含 Agent：让 orchestrator spawn subagent 时免去权限提示
# 真正的安全边界仍是 .claude/hooks/guard.sh（headless 下照常生效）
claude -p "$PROMPT" \
  --permission-mode acceptEdits \
  --allowedTools "Read,Grep,Glob,Edit,Write,Bash,Agent" \
  --output-format json \
  >>"$LOG" 2>&1

echo "[$STAMP] done" >>"$LOG"
