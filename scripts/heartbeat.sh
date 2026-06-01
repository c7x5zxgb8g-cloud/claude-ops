#!/usr/bin/env bash
# 上帝视角心跳：每隔 INTERVAL 秒刷新一次系统运行状态快照。
# 纯脚本、零 token、不碰 Claude 上下文——读的是 triage 已经算好并落盘的状态。
# 建议放在一个独立的 tmux 窗格里常驻；另一个窗格留给交互式 claude。
# 用法：./scripts/heartbeat.sh [间隔秒数]        例：./scripts/heartbeat.sh 120
# 可选：export LOG_GLOB='logs/**/*.log'  设了就顺带统计近期 error/exception 行数
# 依赖：python3（状态汇总）；可选 bash globstar（日志统计）
set -uo pipefail
shopt -s globstar nullglob 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO"

INTERVAL="${1:-120}"
REPORTS="ops-state/reports"
LOG_GLOB="${LOG_GLOB:-}"

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }  # GNU || BSD

while true; do
  clear
  printf '运维上帝视角 · %s\n' "$(date -u '+%Y-%m-%d %H:%M:%SZ')"
  printf '%s\n' "----------------------------------------"

  python3 - <<'PY'
import json, sys
from collections import Counter
try:
    issues = json.load(open("ops-state/issues.json")).get("issues", [])
except FileNotFoundError:
    print("尚无 issues.json（还没跑过 triage）"); sys.exit()
except Exception as e:
    print("issues.json 解析失败:", e); sys.exit()
c = Counter(i.get("status", "?") for i in issues)
print(f"问题总数: {len(issues)}   known:{c['known']}  fixing:{c['fixing']}  fixed:{c['fixed']}  gave_up:{c['gave_up']}")
for i in issues:
    if i.get("status") == "fixing":
        print(f"  修复中: {i.get('title','?')}  → {i.get('branch') or '?'}")
for i in issues:
    if i.get("needs_human"):
        print(f"  需人工: {i.get('title','?')}")
PY

  last_report="$(ls -t "$REPORTS"/*.md 2>/dev/null | head -1 || true)"
  if [ -n "$last_report" ]; then
    age=$(( ($(date +%s) - $(mtime "$last_report")) / 60 ))
    printf '\n最近一次 triage: %s（%d 分钟前）\n' "$(basename "$last_report")" "$age"
  else
    printf '\n暂无 triage 报告\n'
  fi

  if [ -n "$LOG_GLOB" ]; then
    files=( $LOG_GLOB )
    if [ "${#files[@]}" -gt 0 ]; then
      errs=$(grep -riE 'error|exception|traceback' "${files[@]}" 2>/dev/null | wc -l | tr -d ' ')
      printf '日志 error/exception 累计匹配: %s 行（%d 个文件）\n' "$errs" "${#files[@]}"
    fi
  fi

  printf '\n（每 %ss 刷新；只读快照。深度诊断 / 修复请在另一窗格对 claude 说 /triage）\n' "$INTERVAL"
  sleep "$INTERVAL"
done
