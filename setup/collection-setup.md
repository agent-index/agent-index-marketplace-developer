---
name: developer-collection-setup
type: collection-setup
version: 1.1.0
collection: developer
description: Org-level configuration for the Developer collection — sets defaults for where collections are authored and what preflight strictness level to enforce.
upgrade_compatible: true
---

## Collection Setup Interview

This interview configures org-level defaults for the Developer collection. Most developers can start working immediately with sensible defaults; this interview exists for orgs that want to standardize their development practices.

### `default_output_path` [org-mandated]

Where newly authored collections are written on the local filesystem.

Ask: "Where should new collections be created by default? This is a local path on each developer's machine where Claude will scaffold new collection directories."

- Default: the workspace root (same directory as the member's agent-index installation)
- Accept any valid local path
- This can be overridden per-session by the developer when invoking the develop skill

### `preflight_strictness` [org-mandated]

How strict the preflight task should be when checking collections.

Ask: "What strictness level should preflight checks use by default?"

- `marketplace` — Full marketplace-eligibility checks. Every requirement in standards.md is enforced. Use this if you plan to publish collections to the marketplace.
- `org` — Slightly relaxed. Skips marketplace-specific requirements (like `marketplace_url` validation and naming prefix checks) but enforces all structural and behavioral standards.
- Default: `marketplace`

### `auto_preflight` [member-overridable]

Whether the develop skill should automatically run preflight checks after generating or modifying collection files.

Ask: "Should preflight checks run automatically after every authoring operation, or only when explicitly requested?"

- `auto` — Run preflight after every develop operation that modifies files
- `manual` — Only run when the developer explicitly asks for it
- Default: `auto`

---

## Setup Completion

1. Write `collection-setup-responses.md` to the collection's setup directory with all configured parameters in YAML format
2. Confirm to admin: "Developer collection is configured. Developers can invoke `@ai:develop` to start building collections, `@ai:preflight` to check release readiness, and `@ai:developer-guide` for reference."

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
