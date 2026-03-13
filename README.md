# OpenStaff

OpenStaff 是一个运行在 macOS 图形界面环境中的“老师-学生”伴侣软件项目。

当前阶段目标：
- 完成阶段 0 基线准备（技术栈、命名规范、最小可运行应用）。
- 在 `docs/` 内持续维护整体方案与实现进展。

## 快速开始

```bash
make build
make dev
make xcode-open
make capture
make slice
make knowledge
make orchestrator
make assist
make student
make llm-prompts
make llm-validate
make llm-call
make llm-retry
make skill-build
make skills-sample
make skills-validate-sample
make test
make test-unit
make test-integration
make test-e2e
make release-regression
make release-preflight
```

### Xcode 一键运行

1. 双击打开 `apps/macos/Package.swift`（或运行 `scripts/dev/open_xcode_workspace.sh`）。
2. 在 Xcode Scheme 选择 `OpenStaffApp`，Destination 选择 `My Mac`。
3. 点击 Run（`Cmd+R`）即可自动构建并启动。

- `make build`：构建 `apps/macos` 最小壳应用。
- `make dev`：启动 macOS 最小空应用（Phase 0 验收命令）。
- `make xcode-open`：在 Xcode 中打开 `apps/macos/Package.swift`，可直接点击 Run 启动 `OpenStaffApp`。
- `make capture`：启动 Phase 1.3 采集 CLI（全局点击监听 + 上下文抓取 + JSONL 落盘轮转）。
- `make slice`：启动 Phase 2.1 任务切片 CLI（session raw-events -> task chunks）。
- `make knowledge`：启动 Phase 2.3 知识构建 CLI（task chunks -> knowledge items + rule summary）。
- `make orchestrator`：启动 Phase 4.1 模式状态机 CLI（模式切换守卫 + 能力白名单 + 结构化日志）。
- `make assist`：启动 Phase 4.2 辅助模式闭环 CLI（规则预测 -> 弹窗确认 -> 执行 -> 回写日志）。
- `make student`：启动 Phase 4.3 学生模式闭环 CLI（输入目标 -> 自动规划 -> 技能执行 -> 结构化审阅报告）。
- `make llm-prompts`：渲染 Phase 3.1 提示词模板（KnowledgeItem -> system/user prompts）。
- `make llm-validate`：校验 LLM 结构化输出样例（强制 JSON + 一致性检查）。
- `make llm-call`：运行 Phase 3.2 调用适配层（默认离线 `text` provider，输出到 `/tmp/openstaff-llm-call-output.json`）。
- `make llm-retry`：离线模拟 2 次瞬时失败，验证重试与错误报告链路。
- `make skill-build`：运行 Phase 3.3 单条 skill 映射（KnowledgeItem + LLM 输出 -> OpenClaw skill）。
- `make skills-sample`：运行 3 条示例任务映射（含 1 条 fallback 案例）。
- `make skills-validate-sample`：校验 `skills-sample` 输出技能的可读性与一致性。
- `python3 scripts/validation/validate_skill_bundle.py --skill-dir <path>`：执行 skill 预检（schema / locator / 风险 / App 白名单）。
- `make test`：一键执行 unit + integration + e2e 测试并输出汇总。
- `make test-unit`：仅执行单元测试。
- `make test-integration`：仅执行集成测试。
- `make test-e2e`：仅执行 E2E 测试。
- `make release-regression`：执行发布回归检查并输出报告。
- `make release-preflight`：一键执行发布回归预检（现已包含 skill bundle preflight）。

## 目录概览

- `apps/macos/`：桌面端 GUI 应用（SwiftUI 最小壳已落地）。
- `core/`：核心能力（采集、知识建模、调度、执行、存储）。
- `core/contracts/`：跨模块共享数据契约与错误/状态码定义入口。
- `modules/`：三大工作模式（教学、辅助、学生）。
- `scripts/`：脚本与工具（知识解析、技能转换、自动化任务）。
- `config/`：配置模板与环境变量说明。
- `data/`：本地开发数据（raw events / task chunks / knowledge / logs）。
- `tests/`：测试策略与未来测试用例组织。
- `docs/`：项目方案、阶段计划、编码规范与 ADR。
- `assets/`：UI 原型、图标、演示素材。
- `vendors/openclaw/`：OpenClaw 源码（main 分支 vendor）。
