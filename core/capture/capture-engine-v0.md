# Capture Engine v0（TODO 1.2 / 1.3）

## 1. 范围

当前实现为 CLI 采集器：`OpenStaffCaptureCLI`。

能力覆盖：
- 辅助功能权限检查。
- 全局鼠标点击与键盘事件监听。
- 前台应用、窗口稳定签名、焦点元素可读属性采集。
- 操作前后轻量截图锚点采集（仅保存派生指纹，不落原始截图）。
- 原始事件 JSONL 落盘（append-only）。
- 按日期 + session 分片存储与按大小/时间轮转。
- 进程异常中断后的续写恢复（同日期同 session 自动续写最后可写分片）。

## 2. 运行方式

仓库根目录执行：

```bash
make capture
```

常用参数：

```bash
# 捕获 20 条后自动停止（用于验收）
make capture ARGS="--max-events 20"

# 输出 JSONL 行到终端（同时仍会落盘）
make capture ARGS="--json --max-events 20"

# 自定义落盘目录与轮转阈值
make capture ARGS="--output-dir data/raw-events --rotate-max-bytes 1048576 --rotate-max-seconds 1800"
```

## 3. 权限策略

启动时执行 Accessibility 权限检查：
- 未授权时返回 `CAP-PERMISSION-DENIED`，并输出系统设置指引。
- 可通过 `--no-permission-prompt` 禁止弹出系统授权提示。

截图锚点权限策略：
- 若未授予 Screen Recording 权限，不中断采集。
- 事件中写入 `contextSnapshot.captureDiagnostics[]`，错误码为 `CTX-SCREENSHOT-PERMISSION-DENIED`。

## 4. 存储行为

- 默认落盘目录：`data/raw-events/{yyyy-mm-dd}/`。
- 文件命名：
  - 主分片：`{sessionId}.jsonl`
  - 轮转分片：`{sessionId}-r0001.jsonl`、`{sessionId}-r0002.jsonl` ...
- 轮转触发：
  - 大小触发：写入后将超过 `--rotate-max-bytes`（默认 `1048576`）。
  - 时间触发：分片打开时长超过 `--rotate-max-seconds`（默认 `1800`，设置 `0` 表示禁用时间轮转）。
- 恢复续写：重启后会扫描同目录同 session 分片，若最新分片仍在阈值内则继续追加，否则新建下一分片。

## 5. 控制台输出行为

- 默认输出人类可读日志（点击类型、前台 app、窗口标题、坐标、计数）。
- `--json` 额外输出 `RawEvent` JSON 行，字段与 `capture.raw.v0` 对齐。

## 6. 已知限制

- 键盘事件在 `AXSecureTextField` 等高敏感场景下会脱敏，不保留原文字符。
- 窗口 ID 与焦点元素依赖 AX 属性，部分应用可能为空。
- 截图锚点依赖 Screen Recording 权限，未授权时只记录降级错误码。
- 暂未接入写盘前 schema 校验（计划在 `scripts/validation` 补齐）。

## 7. 手动验收命令（TODO 1.3）

```bash
# 1) 跑一次采集（需要本机点击）
make capture ARGS="--session-id session-20260307-a1 --max-events 5"

# 2) 校验 JSONL 可被 jq 解析
find data/raw-events -name "*.jsonl" -print0 | while IFS= read -r -d '' f; do
  jq -e -c . "$f" >/dev/null
done

# 3) 复用同一 session 再跑一次，确认继续追加而非覆盖
make capture ARGS="--session-id session-20260307-a1 --max-events 5"
wc -l data/raw-events/$(date +%F)/session-20260307-a1*.jsonl
```
