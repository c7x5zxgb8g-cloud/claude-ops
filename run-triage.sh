#!/usr/bin/env bash
# 定时运维循环：以 headless 模式跑一轮 triage。
# 由 cron / systemd timer 周期性调用。放在仓库根目录（与 CLAUDE.md 同级）。
set -euo pipefail

# 仓库根目录 = 本脚本所在目录
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO"

# --- cron 环境很干净，下面几件事必须显式处理，否则线上必踩 ---
# 1) PATH 里通常没有 claude，补上常见安装位置
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
# 2) 订阅制鉴权：用订阅登录，不要用 API key（设了 API key 会强制走 API 按量计费）。
#    cron 无法浏览器登录，所以先在你自己终端跑一次：claude setup-token
#    它生成一个长期 OAuth token；把它放进下面（更稳妥是放进只有你能读的 env 文件再 source）。
export CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:?请先用 claude setup-token 生成订阅 OAuth token 并在此设置}"
# 3) 防止环境里残留的 ANTHROPIC_API_KEY 抢占（一旦存在，-p 必定优先用它并走 API 计费）
unset ANTHROPIC_API_KEY || true
# 4) 工作目录已在上面 cd 好。配完可用交互会话里的 /status 确认当前走的是订阅。

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
