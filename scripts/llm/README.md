# scripts/llm/

LLM 解析与提示词模板工具目录（Phase 3.1）。

## 已实现（TODO 3.1）
- `prompts/system-knowledge-parser-v0.md`
  - 系统提示词模板，定义角色、字段映射与稳定性规则。
- `prompts/task-knowledge-parser-v0.md`
  - 任务提示词模板，注入 `KnowledgeItem` 与输出 schema。
- `schemas/knowledge-parse-output.schema.json`
  - LLM 输出结构约束（`llm.knowledge-parse.v0`）。
- `render_knowledge_prompts.py`
  - 读取 `KnowledgeItem`，渲染稳定的 system/user prompts。
- `validate_knowledge_parse_output.py`
  - 强制 JSON 提取与严格校验（可选与原始 `KnowledgeItem` 做一致性比对）。
- `examples/knowledge-parse-output.sample.json`
  - 结构化输出样例。

## 使用方式

### 1) 渲染提示词

```bash
python3 scripts/llm/render_knowledge_prompts.py \
  --knowledge-item core/knowledge/examples/knowledge-item.sample.json \
  --out-dir /tmp/openstaff-llm-prompts
```

输出：
- `/tmp/openstaff-llm-prompts/system.prompt.md`
- `/tmp/openstaff-llm-prompts/user.prompt.md`

### 2) 校验 LLM 输出

```bash
python3 scripts/llm/validate_knowledge_parse_output.py \
  --input scripts/llm/examples/knowledge-parse-output.sample.json \
  --knowledge-item core/knowledge/examples/knowledge-item.sample.json
```

可选参数：
- `--normalized-output <path>`：输出提取后的规范化 JSON 文件。

## 约束说明
- 模型响应必须只包含 JSON 对象。
- 必须匹配 `schemas/knowledge-parse-output.schema.json` 的字段和枚举约束。
- 当传入 `--knowledge-item` 时，会额外检查：
  - ID、上下文、步骤顺序、源事件引用一致性。
  - `objective == KnowledgeItem.goal`。
  - `safetyNotes` 与约束描述顺序一致。
