#!/usr/bin/env bash
# 一键摆好运维布局（tmux ≥ 3.1，因用到 -l 百分比）：
#
#   +------------------+--------------------+
#   |  仪表盘 dashboard |                    |
#   |  (左上)           |   日志流 logs      |
#   +------------------+   (右列, 全高)     |
#   |  交互式 claude    |                    |
#   |  (左下)           |                    |
#   +------------------+--------------------+
#
# 用法：./scripts/start-ops.sh
# 可选：export LOG_GLOB='logs/**/*.log'   指定右列要 tail 的日志
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO"
SESSION="${SESSION:-ops}"
LOG_GLOB="${LOG_GLOB:-logs/**/*.log}"

# 已存在就直接接入，不重复搭
if tmux has-session -t "$SESSION" 2>/dev/null; then
  exec tmux attach -t "$SESSION"
fi

# 初始 pane = 左上（仪表盘）
tmux new-session -d -s "$SESSION" -c "$REPO"
dash="$(tmux display-message -p -t "$SESSION" '#{pane_id}')"

# 向右切出右列（日志），占 60% 宽，全高
logs="$(tmux split-window -h -l 60% -t "$dash" -c "$REPO" -P -F '#{pane_id}')"

# 把左列再纵向切，下半 = 交互式 claude（占左列 55% 高）
chat="$(tmux split-window -v -l 55% -t "$dash" -c "$REPO" -P -F '#{pane_id}')"

# 给 pane 打上稳定标题，便于 scripts/ops-watch.sh 精确注入 /triage。
tmux select-pane -t "$dash" -T dashboard
tmux select-pane -t "$logs" -T logs
tmux select-pane -t "$chat" -T claude

# 启动各窗格
tmux send-keys -t "$dash" './scripts/dashboard.sh 60' Enter
tmux send-keys -t "$logs" "LOG_GLOB='$LOG_GLOB' ./scripts/logs-tail.sh" Enter
tmux send-keys -t "$chat" 'claude' Enter

# 焦点落在对话窗格
tmux select-pane -t "$chat"
exec tmux attach -t "$SESSION"
