# ADR-0000：技术栈与运行边界基线

- 状态：Accepted
- 日期：2026-03-07
- 阶段：Phase 0 Baseline

## 背景

OpenStaff 当前目标是先落地“可运行的最小空应用 + 可持续扩展的核心架构基线”，为后续采集、知识建模、技能转换与执行闭环提供统一技术约束。

Phase 0 需要明确三件事：
1. macOS GUI 技术方案。
2. 核心服务主语言。
3. OpenClaw 集成边界。

## 决策

### 1) macOS GUI：SwiftUI（必要时桥接 AppKit）

- GUI 主体采用 SwiftUI。
- 需要系统级能力时（权限检测、事件监听、窗口信息）通过 AppKit/Quartz 桥接。
- 当前最小壳应用位于 `apps/macos`，统一启动命令为：

```bash
make dev
```

### 2) 核心服务语言：Swift 6（单语言优先）

- `core/*` 目录后续核心模块（capture / knowledge / orchestrator / executor / storage）统一采用 Swift。
- `scripts/*` 允许使用脚本语言（如 Python）作为工具链，但不承载核心运行时职责。

### 3) OpenClaw 集成方式：文件驱动优先 + 进程调用补充

- 第一优先：文件驱动。
  - OpenStaff 生成可审计 skill 文件，写入约定目录（例如 `data/skills/pending`）。
  - 执行器按任务状态移动文件并记录日志。
- 第二优先：进程调用。
  - 当本地存在 OpenClaw 可执行入口时，执行器通过子进程触发并回收 stdout/stderr。
- 设计目标：先解耦数据协议，再解耦执行入口，降低 vendor 版本变更风险。

## 运行边界

- 运行平台：macOS（首版仅面向本地单机）。
- 数据策略：默认本地存储，不上传原始操作事件。
- 权限策略：采集/执行能力必须可见、可停、可审计。

## 备选方案与取舍

- Electron：跨平台更强，但首期需要额外 Node GUI 依赖链，系统事件桥接复杂度更高。
- Tauri：资源占用好，但当前环境缺少 Rust 工具链，不适合作为 Phase 0 立即落地方案。
- SwiftUI：与 macOS 系统能力贴合度最高，可最快验证采集与权限路径，因此被选用。

## 影响

- `apps/macos` 已新增 Swift Package 最小应用壳。
- 根目录新增统一命令入口（`make build` / `make dev`）。
- 后续 ADR 将围绕事件 schema、存储策略、安全策略继续细化。

## 后续关联 ADR（待补）

- `ADR-0001-event-schema.md`
- `ADR-0002-storage-strategy.md`
- `ADR-0004-execution-safety.md`
- `ADR-0007-openclaw-companion-boundary.md`
