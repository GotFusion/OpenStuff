# OpenStaff 用户使用说明书

版本：v0.6.4  
更新时间：2026-03-10

## 1. 产品简介

OpenStaff 是“老师-学生”式个人助理：
- 老师：你（用户）。
- 学生：OpenStaff 软件。

软件通过记录并学习你的桌面操作，沉淀为知识条目，然后在三种模式中协助你：
- 教学模式：观察并学习。
- 辅助模式：预测下一步并经确认后执行。
- 学生模式：根据知识自主执行并输出审阅报告。

## 2. 运行前准备

### 2.1 系统要求
- macOS（建议 14+）。
- Swift toolchain / Xcode Command Line Tools。
- Python 3.10+（用于脚本与测试）。

### 2.2 仓库准备
在项目根目录执行：

```bash
make build
```

### 2.3 环境变量
复制环境变量模板：

```bash
cp .env.example .env.local
```

按需填写：
- `OPENAI_API_KEY`：使用在线 OpenAI provider 时必填。
- `OPENCLAW_CLI_PATH`：OpenClaw 可执行文件路径；阶段 8.2 的 `OpenClawRunner` / `OpenStaffOpenClawCLI` 会优先使用它，未设置时回退到本地 gateway。

### 2.4 配置文件
- 默认配置：`config/default.yaml`
- 开发覆盖：`config/dev.yaml`
- 发布模板：`config/release.example.yaml`

## 3. 三种模式使用方法

### 3.1 教学模式（Learning）
目标：采集你的操作并形成知识。

推荐方式（已集成到 OpenStaff App）：
- 打开 OpenStaff 控制台。
- 选择“教学模式”并点击“开始”。
- 点击“停止”后会自动执行：事件切片 + 知识条目生成（不再需要手动跑 `slice/knowledge`）。
- 教学模式停止后的内置切片策略默认按“整段会话”生成单任务（从开始到停止），跨应用跳转/空闲不再强制切分；干扰步骤交由 LLM 在后处理阶段筛选。
- 在“状态工作台 -> 教学后处理（LLM / Skill）”选择转换方式：
  - `自动 API`：程序自动调用 ChatGPT API 并生成 OpenClaw Skill。
  - `手动粘贴`：程序生成提示词预览，用户手动复制到 ChatGPT，再把返回结果粘贴回程序执行。

兼容调试命令（仅排障/回归使用）：

```bash
make capture ARGS="--max-events 20"
make slice ARGS="--session-id session-20260309-a1 --date 2026-03-09"
make knowledge ARGS="--task-chunk data/task-chunks/2026-03-09/task-session-20260309-a1-001.json"
```

### 3.2 辅助模式（Assist）
目标：学生预测下一步，经你确认后执行。

推荐方式（已集成到 OpenStaff App）：
- 选择“辅助模式”并点击“开始”。
- App 会直接在模式内执行“预测 -> 确认（默认集成确认）-> 执行 -> 写日志”。

兼容调试命令：
```bash
make assist ARGS="--knowledge-item core/knowledge/examples/knowledge-item.sample.json --auto-confirm yes"
```

### 3.3 学生模式（Student）
目标：学生根据目标自主执行并生成审阅报告。

推荐方式（已集成到 OpenStaff App）：
- 选择“学生模式”并点击“开始”。
- App 会直接执行“规划 -> 执行 -> 审阅报告写入”。

兼容调试命令：
```bash
make student ARGS="--goal 在 Safari 中复现点击流程 --knowledge core/knowledge/examples/knowledge-item.sample.json"
```

## 4. LLM 与 Skill 工作流

### 4.0 App 内置双路径（推荐）
在“状态工作台 -> 教学后处理（LLM / Skill）”可切换：
- `自动 API`：教学停止后自动执行 `LLM 解析 -> Skill 映射`。
- `手动粘贴`：教学停止后自动生成提示词，支持复制/粘贴闭环执行。

### 4.0.1 手动粘贴流程（无 API 场景）
1. 先完成一次教学模式并点击停止。  
2. 在“教学后处理”选择 `手动粘贴`。  
3. 点击“复制提示词与数据”，粘贴到 ChatGPT 对话框。  
4. 等 ChatGPT 返回 JSON 后，复制返回内容。  
5. 粘贴到 App 的“LLM 结果输入”文本框，点击“执行手动结果”。  
6. App 会生成 OpenClaw Skill，并显示输出目录路径。  

### 4.1 提示词渲染与校验
```bash
make llm-prompts
make llm-validate
```

### 4.2 调用适配层
```bash
make llm-call
make llm-retry
```

### 4.3 Skill 生成与校验
```bash
make skills-sample
make skills-validate-sample
```

### 4.4 通过 OpenClaw Runner 执行已生成 skill
```bash
make openclaw ARGS="--skill-dir scripts/skills/examples/generated/openstaff-task-session-20260307-a1-001 --json-result"
```

说明：
- 该入口会通过 `OpenClawRunner` 拉起 OpenClaw CLI / gateway 子进程。
- 执行日志会写入 `data/logs/{yyyy-mm-dd}/{sessionId}-openclaw.log`。
- 若执行失败，会返回结构化 `errorCode/stdout/stderr/exitCode` 结果，便于审阅与排障。

## 5. 发布前检查

### 5.1 执行发布回归
```bash
make release-regression
```

### 5.2 一键执行发布预检
```bash
make release-preflight
```

## 6. 常见问题

### 6.1 提示权限不足
- 采集功能依赖 macOS 辅助功能权限。
- 请在系统设置中授权后重试。

### 6.2 Swift 构建失败
- 检查 `xcode-select -p` 指向有效开发工具链。
- 保证当前用户对项目目录和缓存目录有写权限。

### 6.3 回归步骤失败
- 先运行 `make build` 确保必需 CLI 已编译。
- 查看回归输出目录内的错误日志定位失败原因。

## 7. 进阶建议

1. 使用真实采集会话替换样例知识条目，观察模型效果变化。  
2. 在 `config/release.example.yaml` 中细化 `safety.blockedActionKeywords`。  
3. 将 `make release-preflight` 接入 CI，作为发布门禁。  
