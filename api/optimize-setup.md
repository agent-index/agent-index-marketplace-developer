---
name: optimize-setup
type: setup
version: 1.0.0
collection: developer
description: Setup interview for the optimize task — configures default optimization preferences.
target: optimize
target_type: task
upgrade_compatible: true
---

## Setup Interview

### `default_mode` [member-overridable]

Default operation mode for the optimize task.

Ask: "When you run the optimizer, should it generate a report only, or also generate scripts and rewrite workflow steps?"

- `report-only` — Produce the optimization report but don't modify any files. Good for understanding what could be optimized before committing.
- `apply` — Produce the report and then generate scripts and rewrite workflow steps (with your approval at each step).
- Default: `report-only`

### `script_language` [org-mandated]

Preferred language for generated scripts.

Ask: "What language should generated optimization scripts use?"

- `python` — Python 3 scripts. Recommended for most collections — good library ecosystem, readable, widely available.
- `node` — Node.js scripts. Suitable if the collection's ecosystem is JavaScript-heavy.
- Default: `python`

### `include_gray_area` [member-overridable]

Whether to include gray-area steps in optimization recommendations.

Ask: "Should the optimizer include 'gray area' steps in its recommendations? Gray-area steps appear mechanical but may require judgment in some cases."

- `yes` — Include gray-area steps as 'possibly mechanical' recommendations. You'll review each one.
- `no` — Only recommend clearly mechanical steps. More conservative, fewer false positives.
- Default: `yes`

---

## Setup Completion

1. Write `setup-responses.md` to the member's task directory with all configured parameters in YAML format
2. Write `manifest.json` to the member's task directory
3. Confirm to member: "Optimizer is ready. Say '@ai:optimize' to audit a collection's workflows for token efficiency."

---

## Upgrade Behavior

### Preserved Responses
All parameters are preserved on upgrade.

### Reset on Upgrade
None.

### Requires Member Attention
None.

### Migration Notes
Not applicable at v1.0.0.
