SHELL := /bin/zsh
APP_PACKAGE_PATH := apps/macos
APP_TARGET := OpenStaffApp
CAPTURE_TARGET := OpenStaffCaptureCLI
SLICE_TARGET := OpenStaffTaskSlicerCLI
KNOWLEDGE_TARGET := OpenStaffKnowledgeBuilderCLI
ORCHESTRATOR_TARGET := OpenStaffOrchestratorCLI
ASSIST_TARGET := OpenStaffAssistCLI
REPLAY_VERIFY_TARGET := OpenStaffReplayVerifyCLI
OPENCLAW_TARGET := OpenStaffOpenClawCLI
STUDENT_TARGET := OpenStaffStudentCLI
ARGS ?=

.PHONY: build dev xcode-open capture slice knowledge orchestrator assist replay-verify openclaw student llm-prompts llm-validate llm-call llm-retry skill-build skills-sample skills-validate-sample test test-unit test-integration test-e2e release-regression release-preflight

build:
	swift build --package-path $(APP_PACKAGE_PATH)

dev:
	swift build --package-path $(APP_PACKAGE_PATH) --product $(APP_TARGET)
	"$$(swift build --package-path $(APP_PACKAGE_PATH) --show-bin-path)/$(APP_TARGET)"

xcode-open:
	./scripts/dev/open_xcode_workspace.sh

capture:
	swift run --package-path $(APP_PACKAGE_PATH) $(CAPTURE_TARGET) $(ARGS)

slice:
	swift run --package-path $(APP_PACKAGE_PATH) $(SLICE_TARGET) $(ARGS)

knowledge:
	swift run --package-path $(APP_PACKAGE_PATH) $(KNOWLEDGE_TARGET) $(ARGS)

orchestrator:
	swift run --package-path $(APP_PACKAGE_PATH) $(ORCHESTRATOR_TARGET) $(ARGS)

assist:
	swift run --package-path $(APP_PACKAGE_PATH) $(ASSIST_TARGET) $(ARGS)

replay-verify:
	swift run --package-path $(APP_PACKAGE_PATH) $(REPLAY_VERIFY_TARGET) $(ARGS)

openclaw:
	swift run --package-path $(APP_PACKAGE_PATH) $(OPENCLAW_TARGET) $(ARGS)

student:
	swift run --package-path $(APP_PACKAGE_PATH) $(STUDENT_TARGET) $(ARGS)

llm-prompts:
	python3 scripts/llm/render_knowledge_prompts.py --knowledge-item core/knowledge/examples/knowledge-item.sample.json --out-dir /tmp/openstaff-llm-prompts

llm-validate:
	python3 scripts/llm/validate_knowledge_parse_output.py --input scripts/llm/examples/knowledge-parse-output.sample.json --knowledge-item core/knowledge/examples/knowledge-item.sample.json

llm-call:
	python3 scripts/llm/chatgpt_adapter.py --provider text --knowledge-item core/knowledge/examples/knowledge-item.sample.json --output /tmp/openstaff-llm-call-output.json $(ARGS)

llm-retry:
	python3 scripts/llm/chatgpt_adapter.py --provider text --knowledge-item core/knowledge/examples/knowledge-item.sample.json --simulate-transient-failures 2 --max-retries 3 --output /tmp/openstaff-llm-retry-output.json $(ARGS)

skill-build:
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item core/knowledge/examples/knowledge-item.sample.json --llm-output scripts/llm/examples/knowledge-parse-output.sample.json --skills-root /tmp/openstaff-skills --overwrite $(ARGS)

skills-sample:
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item core/knowledge/examples/knowledge-item.sample.json --llm-output scripts/llm/examples/knowledge-parse-output.sample.json --skills-root /tmp/openstaff-skills-sample --overwrite
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item scripts/skills/examples/knowledge-item.sample.finder.json --llm-output scripts/skills/examples/llm-output.sample.finder.json --skills-root /tmp/openstaff-skills-sample --overwrite
	python3 scripts/skills/openclaw_skill_mapper.py --knowledge-item scripts/skills/examples/knowledge-item.sample.terminal.json --llm-output scripts/skills/examples/llm-output.sample.terminal-invalid.txt --skills-root /tmp/openstaff-skills-sample --overwrite

skills-validate-sample: skills-sample
	python3 scripts/skills/validate_openclaw_skill.py --skill-dir /tmp/openstaff-skills-sample/openstaff-task-session-20260307-a1-001
	python3 scripts/skills/validate_openclaw_skill.py --skill-dir /tmp/openstaff-skills-sample/openstaff-task-session-20260307-b2-001
	python3 scripts/skills/validate_openclaw_skill.py --skill-dir /tmp/openstaff-skills-sample/openstaff-task-session-20260307-c3-001

test:
	python3 scripts/tests/run_all.py --suite all

test-unit:
	python3 scripts/tests/run_all.py --suite unit

test-integration:
	python3 scripts/tests/run_all.py --suite integration

test-e2e:
	python3 scripts/tests/run_all.py --suite e2e

release-regression:
	python3 scripts/release/run_regression.py --suite all

release-preflight:
	python3 scripts/release/run_regression.py --output-root /tmp/openstaff-release-preflight/regression --suite all
