---
name: preflight-setup
type: setup
version: 1.0.0
collection: developer
description: Setup interview for the preflight task — configures default strictness and reporting preferences.
target: preflight
target_type: task
upgrade_compatible: true
---

## Setup Interview

### `strictness` [member-overridable]

Default strictness level for preflight checks.

Ask: "What strictness level should preflight use by default?"

- Default: inherited from collection-setup `preflight_strictness`
- `marketplace` — Full marketplace-eligibility checks. Every requirement in standards.md is enforced.
- `org` — Slightly relaxed. Skips marketplace-specific requirements but enforces structural and behavioral standards.

### `verbose_report` [member-defined]

How detailed the preflight report should be.

Ask: "When preflight finds issues, how detailed should the report be?"

- `full` — Show every check that was run, including passed checks. Useful for understanding what preflight verified.
- `issues_only` — Show only errors, warnings, and notes. Skip passed checks. More concise.
- Default: `issues_only`

---

## Setup Completion

1. Write `setup-responses.md` to the member's task directory with all configured parameters in YAML format
2. Write `manifest.json` to the member's task directory
3. Confirm to member: "Preflight is ready. Say '@ai:preflight' to check a collection's release readiness."

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
