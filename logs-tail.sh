#!/usr/bin/env bash
# 日志流窗格（右列）：实时 tail 多 agent 的日志文件。
# 用法：LOG_GLOB='logs/**/*.log' ./logs-tail.sh   或   ./logs-tail.sh 'logs/**/*.log'
# 日志实际路径见 ops-state/project-facts.md（/onboard 写的清单）。
set -uo pipefail
shopt -s globstar nullglob 2>/dev/null || true
cd "$(dirname "${BASH_SOURCE[0]}")"

LOG_GLOB="${LOG_GLOB:-${1:-logs/**/*.log}}"
files=( $LOG_GLOB )

# 文件还没出现就等（多 agent 系统启动有先后）
if [ "${#files[@]}" -eq 0 ]; then
  echo "暂无匹配 $LOG_GLOB 的日志，等待文件出现…（按 project-facts.md 核对路径，或改 LOG_GLOB）"
  while [ "${#files[@]}" -eq 0 ]; do sleep 5; files=( $LOG_GLOB ); done
fi

echo "tail -F（${#files[@]} 个文件）：${files[*]}"
echo "----------------------------------------"
exec tail -n 40 -F "${files[@]}"
