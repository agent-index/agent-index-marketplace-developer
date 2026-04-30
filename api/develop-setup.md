---
name: develop-setup
type: setup
version: 1.0.0
collection: developer
description: Setup interview for the develop skill — configures the developer's working preferences and defaults.
target: develop
target_type: skill
upgrade_compatible: true
---

## Setup Interview

### `output_path` [member-overridable]

Default directory where new collections are created.

Ask: "Where should new collections be created on your machine? This is the directory where Claude will scaffold collection directories when you start a new project."

- Default: inherited from `default_output_path` in collection-setup
- Accept any valid local path
- The developer can override this per-session when invoking the develop skill

### `experience_level` [member-defined]

The developer's self-assessed experience with agent-index collection development.

Ask: "How familiar are you with building agent-index collections?"

- `beginner` — "I'm new to this. I'd like explanations along the way."
- `intermediate` — "I understand the basics but haven't built many collections."
- `advanced` — "I know the system well. Just scaffold and let me review."

This controls the default verbosity of the develop skill. Developers can always ask for more or less explanation regardless of this setting.

### `auto_preflight` [member-overridable]

Whether preflight checks run automatically after develop operations.

Ask: "Should preflight checks run automatically after every authoring operation, or only when you ask?"

- Default: inherited from collection-setup `auto_preflight`
- Options: `auto`, `manual`

---

## Setup Completion

1. Write `setup-responses.md` to the member's skill directory with all configured parameters in YAML format
2. Write `manifest.json` to the member's skill directory
3. Confirm to member: "Developer skill is ready. Say '@ai:develop' to start building or evolving a collection."

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
