# OpenStaff

OpenStaff 是一个运行在 macOS 图形界面环境中的“老师-学生”伴侣软件项目。

当前阶段目标：
- 完成阶段 0 基线准备（技术栈、命名规范、最小可运行应用）。
- 在 `docs/` 内持续维护整体方案与实现进展。

## 快速开始

```bash
make build
make dev
make capture
make slice
make knowledge
make llm-prompts
make llm-validate
```

- `make build`：构建 `apps/macos` 最小壳应用。
- `make dev`：启动 macOS 最小空应用（Phase 0 验收命令）。
- `make capture`：启动 Phase 1.3 采集 CLI（全局点击监听 + 上下文抓取 + JSONL 落盘轮转）。
- `make slice`：启动 Phase 2.1 任务切片 CLI（session raw-events -> task chunks）。
- `make knowledge`：启动 Phase 2.3 知识构建 CLI（task chunks -> knowledge items + rule summary）。
- `make llm-prompts`：渲染 Phase 3.1 提示词模板（KnowledgeItem -> system/user prompts）。
- `make llm-validate`：校验 LLM 结构化输出样例（强制 JSON + 一致性检查）。

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
