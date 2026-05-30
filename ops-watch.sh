#!/usr/bin/env bash
# 向常驻的 tmux 运维会话定时注入一轮 triage。
# 前提：已有名为 $SESSION 的 tmux 会话，里面跑着交互式 claude。
# 用法：./ops-watch.sh [间隔秒数]   例：./ops-watch.sh 1800
set -euo pipefail

SESSION="ops"
INTERVAL="${1:-1800}"   # 默认 30 分钟一轮

# 注意：send-keys 是“盲打”——它把字直接敲进当前 pane，不判断 claude 是否在忙。
# 因此把 INTERVAL 设得明显长于一轮 triage 的耗时，避免上一轮没跑完就被插队。
while true; do
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux send-keys -t "$SESSION" "/triage" Enter
  else
    echo "tmux 会话 '$SESSION' 不存在，等待下一周期。" >&2
  fi
  sleep "$INTERVAL"
done
