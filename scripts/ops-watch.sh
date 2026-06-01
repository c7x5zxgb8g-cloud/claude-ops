#!/usr/bin/env bash
# 可选：向已有的交互式 tmux 运维会话定时注入一轮 /triage。
#
# 这条路径不启动新的 Claude 进程；它复用 ./scripts/start-ops.sh 创建的交互式 Claude pane。
# 前提：已有名为 $SESSION 的 tmux 会话，里面跑着交互式 claude。
# 用法：./scripts/ops-watch.sh [间隔秒数]   例：./scripts/ops-watch.sh 1800
set -euo pipefail

SESSION="ops"
INTERVAL="${1:-1800}"   # 默认 30 分钟一轮

# 注意：send-keys 不知道 claude 是否在忙。
# 因此把 INTERVAL 设得明显长于一轮 triage 的耗时，避免上一轮没跑完就被插队。
while true; do
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    pane="$(tmux list-panes -t "$SESSION" -F '#{pane_id} #{pane_title}' | awk '$2 == "claude" { print $1; exit }')"
    if [ -n "$pane" ]; then
      tmux send-keys -t "$pane" "/triage" Enter
    else
      echo "tmux 会话 '$SESSION' 中找不到标题为 claude 的 pane；请先用 ./scripts/start-ops.sh 启动。" >&2
    fi
  else
    echo "tmux 会话 '$SESSION' 不存在，等待下一周期。" >&2
  fi
  sleep "$INTERVAL"
done
