# scripts/release/

发布前回归检查工具（TODO 6.3）。

## 包含内容
- `run_regression.py`
  - 执行发布回归检查：
    1. 原始事件校验（sample strict + data compat）。
    2. 知识条目校验（sample strict + data compat）。
    3. LLM 输出样例校验。
    4. 三条 skill 映射 + skill 目录校验。
    5. 三条 skill bundle preflight（schema / locator / 风险 / App 白名单）。
    6. replay verify sample。
    7. personal desktop benchmark。
    8. 测试套件（`scripts/tests/run_all.py`）。
  - 输出结构化回归报告 JSON。

## 推荐命令
```bash
python3 scripts/release/run_regression.py --suite all
```

或直接使用根目录 Makefile：

```bash
make release-regression
make release-preflight
```

如需复用已构建 CLI，加快本地门禁：

```bash
make release-preflight ARGS="--openclaw-executable apps/macos/.build/debug/OpenStaffOpenClawCLI --replay-verify-executable apps/macos/.build/debug/OpenStaffReplayVerifyCLI"
```
