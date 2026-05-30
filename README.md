# 多 Agent 系统 · 上帝视角运维助手（基于 Claude Code）

一个常驻的运维助手：周期性读日志 → 判断系统状态与问题 → 自主派 subagent 修 bug 并提交到 `autofix/*` 分支 → 每轮产出运行状态 + 问题报告。修复的脏上下文隔离在 subagent 里，不污染运维主上下文。真正的记忆落在磁盘（`ops-state/`），所以会话上下文可随时 `/clear` 重置而不丢状态——这也是它能长期运行不“变糊”的关键。

## 目录结构

    CLAUDE.md                  运维 orchestrator 的“人格”与工作流（每次会话自动加载）
    .claude/
      agents/bug-fixer.md      修复 subagent：独立上下文 + 写权限，改完提交到 autofix/* 分支
      agents/diagnoser.md      可选：只读诊断 subagent（便宜，跑 Haiku）
      commands/onboard.md      /onboard：一次性熟悉项目，把发现写进 project-facts.md
      commands/triage.md       /triage：交互式触发一轮完整运维循环
      hooks/guard.sh           PreToolUse 守卫：硬拦推 main / 范围外改文件（安全底线）
      settings.json            注册 guard 钩子
    ops-state/
      issues.json              当前问题状态快照（去重 + 水合用，保持小）
      project-facts.md         /onboard 写的项目实况：日志源清单、健康判断、测试命令等
      reports/                 历次诊断报告（只追加）
    logs/                      默认日志位置占位；实际路径以 project-facts.md 为准
    run-triage.sh              headless 跑一轮 triage（全新进程，无上下文累积）
    triage-loop.sh             按 MODE/INTERVAL 周期反复调 run-triage.sh（开发/临时用）
    heartbeat.sh               极简状态心跳（零 token 只读）
    dashboard.sh               报告汇总仪表盘：状态计数 + 历次诊断时间线 + 最新报告预览
    logs-tail.sh               日志流窗格：tail -F 多 agent 日志
    start-ops.sh               一键摆好 tmux 三窗格布局
    ops-watch.sh               可选/旧：往常驻会话 send-keys 注入 /triage（已被 start-ops 取代）

## 前置依赖

- Claude Code CLI，并已用**订阅账号**登录（`claude` 然后 `/login`）
- `python3`、`jq`、`flock`、`grep`（Linux 一般自带）
- `tmux` ≥ 3.1（`start-ops.sh` 用到 `-l 百分比`）
- 目标项目是一个 git 仓库

## 安装

1. 把本目录所有内容（含 `.claude/`、`ops-state/`）复制到你项目的根目录。
2. 赋予脚本执行权限：

       chmod +x *.sh .claude/hooks/guard.sh

3. 按你的仓库改 `.claude/hooks/guard.sh` 里的 `ALLOWED_PREFIXES`（允许 subagent 改动的目录）。
4. 重启（或新开）Claude Code 会话——`.claude/agents/` 下的 agent 只在启动时加载。

## 鉴权（订阅制，重要）

不要用 API key。设了 `ANTHROPIC_API_KEY`，headless 的 `claude -p` 会强制走 API 按量计费、绕开订阅。
headless 在无浏览器环境下用订阅鉴权的正确方式：

    claude setup-token            # 在你自己终端跑一次，生成长期 OAuth token
    export CLAUDE_CODE_OAUTH_TOKEN=<上一步得到的 token>
    # 确保环境里没有 ANTHROPIC_API_KEY（run-triage.sh 也会主动 unset）

进交互会话用 `/status` 确认当前走的是订阅而非 API。

## 启动顺序

1. **熟悉项目并落盘**：在项目根目录起会话，执行 `/onboard`。它探索代码、查清多 agent 系统的所有日志在哪、怎么读、怎么判断健康，写进 `ops-state/project-facts.md`。审一下，按它建议手动调 `guard.sh` 的允许路径。
2. **手动验证一轮**：放几条真实日志样本，执行 `/triage`。确认报告落到 `ops-state/reports/`、`issues.json` 更新、需修问题生成了 `autofix/*` 分支、并且 `guard.sh` 真的拦得住（可故意试 `git push origin main`）。
3. **进入按场景的自动巡检**（见下）。
4. **日常**：`./start-ops.sh` 摆好三窗格，平时看仪表盘 + 看日志流 + 随时对话/手动 `/triage`。

## 三种节奏，各管一摊

- **看（高频、零 token）**：`heartbeat.sh` / `dashboard.sh`，只读磁盘状态刷新，不调 LLM、不会 rot。
- **做（按场景频率、调 LLM + subagent）**：`/triage`（交互）或 `run-triage.sh`（headless）。每轮都是全新进程，所以频率随便调都不会累积上下文。
  - 开发/临时：`MODE=dev ./triage-loop.sh`（默认 5 分钟）或 `INTERVAL=120 ./triage-loop.sh`
  - 稳定运行：`MODE=prod ./triage-loop.sh`（默认 1 小时），或交给 systemd timer（`OnUnitActiveSec` 即周期旋钮，`Persistent=true` 补跑）
- **问（按需）**：交互式 claude 窗格，做上帝视角问答与手动深挖。

## tmux 布局（`./start-ops.sh`）

    +----------------------+----------------------------+
    |  仪表盘 dashboard.sh  |                            |
    |  状态 + 诊断汇总      |   日志流 logs-tail.sh      |
    |  + 最新报告预览       |   tail -F 多 agent 日志    |
    +----------------------+   （右列，全高）           |
    |  交互式 claude        |                            |
    |  /triage、问答、/clear |                            |
    +----------------------+----------------------------+

日志流要 tail 哪些文件由 `LOG_GLOB` 指定（默认 `logs/**/*.log`，实际路径见 project-facts.md）：

    LOG_GLOB='logs/**/*.log' ./start-ops.sh

## 安全红线

- 修复只落 `autofix/*` 新分支，绝不合并/推送 main；交付的是待人工审的分支，不是已生效改动。
- subagent 只能改 `guard.sh` 允许的目录；越界写入与推 main 由钩子硬拦。
- 高风险变更（迁移、依赖升级、配置）不自动碰，标 `needs_human` 进报告。

## 数据流闭环

右列肉眼看原始日志 → 对话窗格 `/triage` 触发 LLM 分析，把诊断写进 `reports/`、状态写进 `issues.json` → 左上仪表盘下次刷新即反映。三块各看一个层次（原始流 / 当前结论 / 历史趋势），都只读同一份磁盘记忆，互不污染上下文。
