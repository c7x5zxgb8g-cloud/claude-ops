# 多 Agent 系统 · Claude Code 运维控制台

这是一个围绕 **Claude Code 交互式 CLI** 搭建的多 agent 运维助手脚手架：人在项目根目录启动 `claude`，Claude Code 自动加载本仓库的 orchestrator 指令、slash commands、subagents 和安全 hook；之后你在交互式会话里执行 `/onboard`、`/triage`，系统就会读日志、判断状态、去重问题、必要时派 `bug-fixer` subagent 修复，并把报告写回磁盘。

核心不是“后台 API 定时调用 Claude”，而是一个可长期使用的交互式运维控制台：

- **交互式 Claude pane**：你发起 `/onboard`、`/triage`、追问和人工判断。
- **日志 pane**：实时看多 agent 原始日志流。
- **仪表盘 pane**：零 token 读取 `ops-state/`，展示当前问题和历史报告。

真正的记忆落在磁盘（`ops-state/`），所以 Claude 会话上下文可随时 `/clear`，不会丢掉项目实况、问题状态和历史报告。修复工作交给独立 subagent，脏上下文不会污染运维主会话。

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
    scripts/                   人执行的辅助脚本，避免污染目标项目根目录
      run-triage.sh            可选：headless 跑一轮 triage（无人值守/cron 场景）
      triage-loop.sh           可选：周期性调用 run-triage.sh（无人值守/实验场景）
      heartbeat.sh             极简状态心跳（零 token 只读）
      dashboard.sh             报告汇总仪表盘：状态计数 + 历次诊断时间线 + 最新报告预览
      logs-tail.sh             日志流窗格：tail -F 多 agent 日志
      start-ops.sh             一键摆好 tmux 三窗格布局
      ops-watch.sh             可选：往已有交互式 tmux 会话注入 /triage

## 前置依赖

- Claude Code CLI，并已完成正常交互式登录（`claude` 后按 Claude Code 的提示登录）
- `python3`、`jq`、`grep`
- `tmux` ≥ 3.1（`scripts/start-ops.sh` 用到 `-l 百分比`）
- 目标项目是一个 git 仓库

## 安装

1. 把本目录所有内容（含 `.claude/`、`ops-state/`）复制到你项目的根目录。
2. 赋予脚本执行权限：

       chmod +x scripts/*.sh .claude/hooks/guard.sh

3. 按你的仓库改 `.claude/hooks/guard.sh` 里的 `ALLOWED_PREFIXES`（允许 subagent 改动的目录）。
4. 重启（或新开）Claude Code 会话——`.claude/agents/` 下的 agent 只在启动时加载。

## 默认工作流：交互式 Claude Code

推荐从一个 tmux 控制台启动：

    ./scripts/start-ops.sh

它会打开三块区域：

1. 左上：`scripts/dashboard.sh`，只读 `ops-state/issues.json` 和 `ops-state/reports/`。
2. 右侧：`scripts/logs-tail.sh`，实时 tail 多 agent 日志。
3. 左下：交互式 `claude`，这是主控台。

在左下 Claude pane 里执行：

    /onboard
    /triage

`/onboard` 负责把目标项目的结构、日志源、健康判断和测试命令写入 `ops-state/project-facts.md`。之后每次 `/triage` 都先读这份落盘实况，再做日志分析、问题去重、派发修复和报告产出。

## 启动顺序

1. **熟悉项目并落盘**：执行 `./scripts/start-ops.sh`，在交互式 Claude pane 中执行 `/onboard`。它探索代码、查清多 agent 系统的所有日志在哪、怎么读、怎么判断健康，写进 `ops-state/project-facts.md`。审一下，按它建议手动调 `guard.sh` 的允许路径。
2. **手动验证一轮**：放几条真实日志样本，执行 `/triage`。确认报告落到 `ops-state/reports/`、`issues.json` 更新、需修问题生成了 `autofix/*` 分支、并且 `guard.sh` 真的拦得住（可故意试 `git push origin main`）。
3. **日常运维**：保持三窗格控制台常驻。平时看仪表盘 + 看日志流 + 随时在 Claude pane 对话或手动 `/triage`。
4. **可选自动触发**：如果希望定时往已有交互式会话里注入 `/triage`，用 `scripts/ops-watch.sh`。如果希望完全无人值守启动新 Claude 进程，再看下面的 headless 模式。

## 三种节奏，各管一摊

- **看（高频、零 token）**：`scripts/heartbeat.sh` / `scripts/dashboard.sh`，只读磁盘状态刷新，不调 LLM、不会 rot。
- **做（调 LLM + subagent）**：在交互式 Claude pane 里执行 `/triage`。这是默认路径，最容易观察、纠偏和人工确认。
- **问（按需）**：继续在同一个交互式 Claude pane 里追问、深挖、要求重跑局部诊断。

## tmux 布局（`./scripts/start-ops.sh`）

    +----------------------+----------------------------+
    |  仪表盘 dashboard.sh  |                            |
    |  状态 + 诊断汇总      |   日志流 logs-tail.sh      |
    |  + 最新报告预览       |   tail -F 多 agent 日志    |
    +----------------------+   （右列，全高）           |
    |  交互式 claude        |                            |
    |  /triage、问答、/clear |                            |
    +----------------------+----------------------------+

日志流要 tail 哪些文件由 `LOG_GLOB` 指定（默认 `logs/**/*.log`，实际路径见 `ops-state/project-facts.md`）：

    LOG_GLOB='logs/**/*.log' ./scripts/start-ops.sh

## 可选：自动触发已有交互式会话

`scripts/ops-watch.sh` 不启动新的 Claude 进程，只是定时向 `./scripts/start-ops.sh` 创建的 `claude` pane 发送 `/triage`：

    ./scripts/ops-watch.sh 1800

它适合“我已经开着 `./scripts/start-ops.sh`，想半小时自动触发一次”的场景。注意它是 tmux `send-keys`，不会判断 Claude 是否正忙，所以间隔要明显长于一轮 triage 的耗时。

## 可选：headless 无人值守模式

`scripts/run-triage.sh` / `scripts/triage-loop.sh` 是另一条支线：它们会用 `claude -p` 启动一个全新的非交互 Claude 进程来跑 triage，适合 cron/systemd 这类无人值守场景。

只有在这条模式下，才需要关心非交互环境里的 `claude -p` 是否能正常运行。如果你使用默认的交互式 Claude Code 控制台，这些不是主流程问题。

    # 实验/无人值守时才使用
    MODE=dev ./scripts/triage-loop.sh
    MODE=prod ./scripts/triage-loop.sh

## 安全红线

- 修复只落 `autofix/*` 新分支，绝不合并/推送 main；交付的是待人工审的分支，不是已生效改动。
- subagent 只能改 `guard.sh` 允许的目录；越界写入与推 main 由钩子硬拦。
- 高风险变更（迁移、依赖升级、配置）不自动碰，标 `needs_human` 进报告。

## 数据流闭环

右列肉眼看原始日志 → 对话窗格 `/triage` 触发 LLM 分析，把诊断写进 `reports/`、状态写进 `issues.json` → 左上仪表盘下次刷新即反映。三块各看一个层次（原始流 / 当前结论 / 历史趋势），都只读同一份磁盘记忆，互不污染上下文。
