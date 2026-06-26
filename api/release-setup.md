---
name: release-setup
type: setup
version: 1.0.0
collection: developer
description: Setup interview for the release task — configures default push order, tag convention, and dist-publish behavior.
target: release
target_type: task
upgrade_compatible: true
---

## Setup Interview

### `tag_convention` [org-mandated]

The git tag format the generated release script applies after a successful push. Must be consistent across the org because the `clone-script-generator` and `/shared/dist/manifest.json` pin to these exact tags.

Ask: "What tag format should releases use? (The clone script pins to these — keep it consistent org-wide.)"

- Default: `v<version>` — per-repo, e.g. `v3.18.0`. Recommended; matches the Release-C convention.
- Custom: a documented alternative (the org must update the clone-script-generator's pinning to match).

### `listings_repo_name` [org-mandated]

The resource-listings repo that must always push LAST.

- Default: `agent-index-resource-listings`

### `default_publishes_dist` [member-overridable]

Whether releases default to publishing `/shared/dist/` (Release-C backend distribution). The interview still confirms per release.

Ask: "Do your releases publish to the org backend's /shared/dist/ by default?"

- `true` — default to including the dist-publish handoff (orgs on Release-C backend distribution).
- `false` — default to push+tag only; ask per release.
- Default: `true`

### `preflight_gate` [org-mandated]

Whether the generated script makes preflight a hard, error-blocking gate before push.

- Default: `errors_block` — any preflight ERROR aborts the release; warnings may be continued past with confirmation. Strongly recommended; this is the `release-script-runs-preflight` contract.
- `advisory` — preflight runs but does not block. NOT recommended; only for emergency hotfix flows, and the script prints a prominent banner that the gate is disabled.

---

## Setup Completion

1. Write `setup-responses.md` to the member's task directory with all configured parameters in YAML format.
2. Write `manifest.json` to the member's task directory.
3. Confirm to member: "Release is ready. Say '@ai:release' (or 'generate a release script') when a version-bumped, preflight-clean release is ready to ship."

---

## Upgrade Behavior

### Preserved Responses
All parameters are preserved on upgrade.

### Reset on Upgrade
None.

### Requires Member Attention
If `preflight_gate` was set to `advisory`, an upgrade surfaces a reminder that error-blocking is the recommended default.

### Migration Notes
Not applicable at v1.0.0.

<!-- AIFS:FILE-END -->
