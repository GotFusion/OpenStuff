# scripts/skills/

OpenClaw skill 转换工具目录（Phase 3.3）。

## 已实现（TODO 3.3）
- `openclaw_skill_mapper.py`
  - 输入 `KnowledgeItem` + LLM 结构化输出，生成 OpenClaw skill 目录。
  - 输出 `SKILL.md`（OpenClaw 可读取格式）和 `openstaff-skill.json`（`openstaff.openclaw-skill.v1` 审计映射产物）。
  - 内置字段校验与 fallback（LLM 输出不完整时回退到 `KnowledgeItem`）。
  - 统一写出 provenance：`knowledge` / `sourceTrace` / `skillBuild` / `stepMappings`。
- `validate_openclaw_skill.py`
  - 校验 skill 目录完整性（frontmatter、步骤段落、映射文件一致性），并兼容历史 `v0` 产物。
- `schemas/openstaff-openclaw-skill.schema.json`
  - 映射产物 `openstaff-skill.json` 的 schema 约束。
- `examples/*`
  - 三条示例输入（含一条故意无效 LLM 输出，用于 fallback 验证）。
  - `examples/generated/*`：三条示例转换后的 OpenClaw skill 目录（可直接审阅）。

## 输出目录约定
- 默认输出根目录：`data/skills/pending/`
- 每个 skill 目录结构：
  - `<skillName>/SKILL.md`
  - `<skillName>/openstaff-skill.json`

## 使用方式

### 1) 生成单条 skill

```bash
python3 scripts/skills/openclaw_skill_mapper.py \
  --knowledge-item core/knowledge/examples/knowledge-item.sample.json \
  --llm-output scripts/llm/examples/knowledge-parse-output.sample.json \
  --skills-root data/skills/pending \
  --overwrite
```

### 2) 校验单条 skill

```bash
python3 scripts/skills/validate_openclaw_skill.py \
  --skill-dir data/skills/pending/openstaff-task-session-20260307-a1-001
```

### 3) 运行三条示例转换（含 fallback 案例）

见根目录 `Makefile` 的 `make skills-sample` 与 `make skills-validate-sample`。
