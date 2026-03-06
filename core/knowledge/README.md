# core/knowledge/

负责将采集到的操作事件转换为“可学习知识”。

## 未来实现
- 定义知识文件格式（例如 JSONL / YAML / 自定义 schema）。
- 行为序列聚类、任务边界识别、操作意图抽取。
- 输出可供 LLM 解析的结构化提示上下文。
- 转换为 OpenClaw skills 所需中间格式。
