#!/usr/bin/env bash
# 按场景设定的周期，反复触发一轮 headless triage。
# 关键：每轮都调用 run-triage.sh，那是一个全新的 claude -p 进程——
# 上下文从零开始，所以周期再短也不会 rot。频率就是下面这一个旋钮。
#
# 用法：
#   MODE=prod ./triage-loop.sh       # 稳定运行：默认 1 小时一轮
#   MODE=dev  ./triage-loop.sh       # 开发联调：默认 5 分钟一轮（2–10 分钟自己调）
#   INTERVAL=120 ./triage-loop.sh    # 直接给秒数，覆盖 MODE
#
# 前提：启动本脚本的环境里已 export CLAUDE_CODE_OAUTH_TOKEN（run-triage.sh 会用）。
set -uo pipefail   # 故意不加 -e：单轮失败不应拖垮整个调度循环
cd "$(dirname "${BASH_SOURCE[0]}")"

MODE="${MODE:-prod}"
case "$MODE" in
  prod) DEFAULT=3600 ;;   # 稳定运行：一小时
  dev)  DEFAULT=300  ;;   # 开发联调：五分钟
  *)    DEFAULT=3600 ;;
esac
INTERVAL="${INTERVAL:-$DEFAULT}"

echo "triage-loop 启动：MODE=$MODE INTERVAL=${INTERVAL}s（每轮一个全新 headless 进程）"
while true; do
  echo "[$(date -u '+%H:%M:%SZ')] 触发一轮 triage…"
  ./run-triage.sh || echo "  本轮 run-triage 退出非零（详见 ops-state/run-logs/），继续。"
  sleep "$INTERVAL"
done
