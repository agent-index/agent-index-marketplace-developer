---
name: developer-tutorial-setup
type: setup
version: 1.0.0
collection: developer
description: Setup interview for the developer-tutorial skill — minimal configuration.
target: developer-tutorial
target_type: skill
upgrade_compatible: true
---

## Setup Interview

### `starting_mode` [member-defined]

Preferred tutorial mode.

Ask: "How would you like to use the tutorial?"

- `guided` — Walk through all topics in order. Best for first-time developers.
- `questions` — Jump to any topic. Best if you already know some concepts and want to fill in gaps.
- Default: `guided`

---

## Setup Completion

1. Write `setup-responses.md` to the member's skill directory with all configured parameters in YAML format
2. Write `manifest.json` to the member's skill directory
3. Confirm to member: "Tutorial is ready. Say '@ai:developer-tutorial' to start learning about collection development."

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
