#!/usr/bin/env bash
# 报告汇总仪表盘（左上窗格）：状态计数 + 历次诊断报告滚动汇总 + 最新报告预览。
# 纯脚本、零 token、只读磁盘——数据来自 triage 落盘的 issues.json 与 reports/。
# 用法：./dashboard.sh [刷新秒数]      例：./dashboard.sh 60
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
INTERVAL="${1:-60}"

while true; do
  clear
  python3 - <<'PY'
import json, sys, glob, os, re, time
from collections import Counter

# --- 当前状态计数 ---
try:
    issues = json.load(open("ops-state/issues.json")).get("issues", [])
    c = Counter(i.get("status", "?") for i in issues)
    print(f"运维上帝视角 · {time.strftime('%Y-%m-%d %H:%M:%SZ', time.gmtime())}")
    print("-" * 52)
    print(f"问题: 总 {len(issues)}  | known {c['known']}  fixing {c['fixing']}  fixed {c['fixed']}  gave_up {c['gave_up']}")
    for i in issues:
        if i.get("status") == "fixing":
            print(f"  修复中 {i.get('title','?')} -> {i.get('branch') or '?'}")
    for i in issues:
        if i.get("needs_human"):
            print(f"  需人工 {i.get('title','?')}")
except FileNotFoundError:
    print("尚无 issues.json（还没跑过 triage）")
except Exception as e:
    print("issues.json 解析失败:", e)

# --- 历次诊断报告滚动汇总（取最近 8 份，抽“总体状态”行）---
reps = sorted(glob.glob("ops-state/reports/*.md"), key=os.path.getmtime, reverse=True)
print("\n历次诊断（新→旧）")
if not reps:
    print("  暂无报告")
for p in reps[:8]:
    txt = open(p, encoding="utf-8", errors="replace").read()
    m = re.search(r"总体状态[:：]\s*(.+)", txt)
    state = m.group(1).strip() if m else "?"
    ncount = len(re.findall(r"^\s*\|", txt, re.M))  # 粗略数问题清单行
    age = int((time.time() - os.path.getmtime(p)) / 60)
    print(f"  {os.path.basename(p)[:20]:20}  {state:8}  ({age}m前)")

# --- 最新报告预览 ---
if reps:
    print("\n最新报告预览")
    head = open(reps[0], encoding="utf-8", errors="replace").read().splitlines()[:14]
    for line in head:
        print("  " + line[:70])
PY
  printf '\n（每 %ss 刷新；只读。深度诊断/修复在下方对话窗格说 /triage）\n' "$INTERVAL"
  sleep "$INTERVAL"
done
