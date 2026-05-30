#!/usr/bin/env bash
# PreToolUse 守卫：从结构上拦截危险动作，不依赖 agent 自觉。
# 退出码 2 = 拦截该工具调用，并把 stderr 反馈给 Claude。
set -euo pipefail

# 允许 subagent 改动的路径前缀（相对仓库根目录），按你的仓库调整。
ALLOWED_PREFIXES=("services/" "src/" "lib/" "ops-state/")

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name')"

block() { printf 'BLOCKED by ops guard: %s\n' "$1" >&2; exit 2; }

case "$tool" in
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
    # 禁止合并 / 推送到主干
    if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(merge|push)([[:space:]].*)?\b(main|master|origin/(main|master))\b'; then
      block "禁止合并 / 推送到主干。修复只能停留在 autofix/* 分支。"
    fi
    # 禁止 force push
    if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push([[:space:]].*)?(--force|-f)\b'; then
      block "禁止 force push。"
    fi
    ;;
  Edit|Write|MultiEdit)
    path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')"
    [ -z "$path" ] && exit 0
    rel="${path#"$PWD"/}"
    for p in "${ALLOWED_PREFIXES[@]}"; do
      case "$rel" in "$p"*) exit 0 ;; esac
    done
    block "文件 $rel 不在允许修改的范围内（见 guard.sh 的 ALLOWED_PREFIXES）。"
    ;;
esac

exit 0
