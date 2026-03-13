# modules/assist/

辅助模式模块。

## 当前实现（Phase 4.2 + 9.1）
- 已实现辅助模式闭环：历史知识检索预测下一步 -> 模拟弹窗确认 -> 执行器执行 -> 结构化日志回写。
- 支持按 `app / window / goal / recent steps / 历史偏好` 检索相似知识，并输出来源证据。
- 运行入口：`make assist ARGS="--knowledge-item core/knowledge/examples/knowledge-item.sample.json --auto-confirm yes"`

## 后续实现
- 下一步预测策略继续从规则化检索扩展到模型重排/置信度校准。
- 弹窗从 CLI mock 升级为 GUI 原生对话框。
- 与 OpenClaw 执行器联动真实动作执行。
