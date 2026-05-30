---
description: 跑一轮日志分析 → 去重 → 派发修复 → 产出报告
---

执行一轮完整运维循环，严格按 `CLAUDE.md` 里定义的工作流：

1. 先读 `ops-state/project-facts.md` 拿到日志源清单，再按清单逐个读取各日志最新内容，提取异常信号。
2. 用 `ops-state/issues.json` 去重，更新各问题状态。
3. 对每个值得修复的新问题，调用 `bug-fixer` subagent 处理，prompt 按 CLAUDE.md 的 Task Spec 格式构造（务必自包含）。可选：先用 `diagnoser` 确认根因再决定是否派修复。
4. 收齐所有 Result Summary，写回 `ops-state/issues.json`。
5. 产出系统运行状态报告，写入 `ops-state/reports/<UTC时间戳>.md`，并在对话里输出。

只汇报结论，不要把 subagent 的中间过程贴出来。

额外关注点（如有）：$ARGUMENTS
