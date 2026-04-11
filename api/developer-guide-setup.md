---
name: developer-guide-setup
type: setup
version: 1.0.0
collection: developer
description: Setup interview for the developer-guide skill — minimal configuration for the reference skill.
target: developer-guide
target_type: skill
upgrade_compatible: true
---

## Setup Interview

### `detail_level` [member-defined]

How detailed answers should be by default.

Ask: "When you ask reference questions, how detailed should the answers be?"

- `concise` — Short, direct answers with spec references. Good for experienced developers who just need a quick lookup.
- `explained` — Answers with context, examples, and rationale. Good for developers learning the system.
- Default: `explained`

---

## Setup Completion

1. Write `setup-responses.md` to the member's skill directory with all configured parameters in YAML format
2. Write `manifest.json` to the member's skill directory
3. Confirm to member: "Developer Guide is ready. You can ask agent-index development questions at any time when this skill is active."

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
