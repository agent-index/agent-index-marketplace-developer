# Developer Collection — Changelog

## [1.2.4] — 2026-05-07

### Fixed

- **`preflight.md` frontmatter version bumped to match the manifest.** The 1.2.3 release expanded `preflight.md` substantially with two new Step 4 sub-checks (adapter supported-ops vs bundle implementation, shipped shell-script line endings) and bumped `preflight-manifest.json` from 1.2.2 to 1.2.3, but left `preflight.md`'s frontmatter `version` field at 1.2.2. This is the exact drift that 1.2.2's preflight Step 5 is supposed to catch — and would have, if the developer collection had been preflighted against itself before the 1.2.3 release. Caught post-publish during dev_install upgrade verification on 2026-05-07. Filed as bug `20260507-8d20ea22-8` (release-discipline bug; the next release author should always run preflight against the developer collection itself before pushing).

## [1.2.3] — 2026-05-05

### Added

- **`preflight` task Step 4 — Adapter supported-ops vs bundle implementation.** New release-artifact integrity check. For every op name in `adapter.json` → `supported_operations`, search the bundle file for at least one of three recognizable implementation signatures (literal op name, canonical `aifs_<snake_case_op>` wrapper, or handler-pattern match like `case '<op>':` or `async <op>(`). Zero matches → ERROR with the bundle path, the manifest path, the missing op names, and the patterns that were tried. Catches the failure mode in bug `20260502-8d20ea22-2`: gdrive 2.2.0's `adapter.json` declared `share`/`unshare`/`getPermissions`/`search`/`transferOwnership` while the bundle was byte-identical to 2.1.3 (no implementations). The pre-1.2.3 freshness checks (timestamp + checksum) couldn't catch it because the broken state was self-consistent. Grep-based for portability across bundling formats; asymmetric (false positives are the dangerous case, false negatives are recoverable by adjusting search patterns). Also surfaces a WARNING when `contract_version >= 2.0.0` but `supported_operations` is empty or absent — the v2.0 contract requires at least the read ops.

- **`preflight` task Step 4 — Shipped shell-script line endings.** New release-artifact integrity check. Walks the collection's `lib/`, `bin/`, and any subdirectories; for every `*.sh` file, scans for `0x0D` bytes (CR characters). Any hit → ERROR with the file path. Closes bug `20260504-8d20ea22-7`: `mcp-servers/permission-helper/show-plan.sh` shipped with CRLF line endings from a Windows host commit and bash refused to execute it (`bash: $'\r': command not found`). The fix is mechanical — convert to LF (`dos2unix`, `sed -i 's/\r$//'`, or "Save With Unix Line Endings"). Shell-script-only by design; other text formats tolerate either line ending.

### Closes

- Idea `preflight-bundle-vs-supported-ops` (developer-collection) — both sub-checks shipped under the broadened scope.
- Bug `20260502-8d20ea22-2` (already resolved by gdrive 2.2.1) — preflight now prevents recurrence.
- Bug `20260504-8d20ea22-7` (already resolved in core 3.3.1's apply-updates LF normalization) — preflight now catches it at upstream-release time too.

## [1.2.2] — 2026-05-02

### Fixed / Added

- **`preflight` task Step 5 — Manifest-frontmatter agreement, tightened.** The pre-1.2.2 wording said "verify the manifest's name, type, version, collection, stateful, dependencies, and external_dependencies match the frontmatter." That was ambiguous about whether the comparison checked value equality or merely field presence; in practice it was being interpreted loosely and not catching real version drift (e.g., `projects/api/edit-project-manifest.json` `version: 1.0.0` vs `projects/api/edit-project.md` frontmatter `version: 2.0.0`). The check is now explicit: it is a **value-equality** comparison, with `version` called out specifically because the `.md` frontmatter is the canonical source of truth (it's what `member-index.json` records, what `org-setup`'s "Needs Attention" reads, and what `check-updates` Step 4 compares against). A drifted manifest `version` is silently wrong because no consumer reads it, so it must be caught at author time.
- **`preflight` task Step 5 — New manifest collection_version sync check.** Sibling check that verifies each API member manifest's `collection_version` field exactly equals the `version` field in `collection.json`. Catches the common author-forgot-to-resync case (bump `collection.json` but not the manifests). Closes developer-collection idea `per-capability-manifest-vs-md-version-drift`.
- Both checks are paired in the same Step 5 section: together they catch *vertical* drift (manifest version vs `.md` frontmatter version, per-capability) and *horizontal* drift (manifest `collection_version` vs `collection.json` `version`, collection-level). Same hazard class as bug `20260430-8d20ea22` — two declared facts that must agree.

### Changed

- `preflight` task v1.2.1 → v1.2.2.
- `collection.json` description leads with the v1.2.2 changes.
- All API-member manifests bumped to `collection_version: 1.2.2`.

---

## [1.2.1] — 2026-04-30

### Added

- **`infrastructure-directory.json`** awareness across the developer collection. The new index file in `agent-index-resource-listings` broadcasts the latest versions of `agent-index-core` and `agent-index-marketplace` so admins running `check-updates` can discover infrastructure releases the same way they discover collection and adapter releases.
- **`develop` skill (v1.2.1):** new "Resource-listings broadcast" subsection — every release of any collection, adapter, or core/marketplace must update the matching directory entry as part of the same release. Pattern: bump `version` in the collection / adapter, update `current_version` in the relevant directory file, bump `last_updated`. Release is incomplete without all three.
- **`developer-guide` skill (v1.2.1):** new common-question pattern: "How do I broadcast a new release so admins discover it?" — explains the three directory files and the consistency requirement.
- **`preflight` task (v1.2.1):** new check category "Resource-listings broadcast freshness" in Step 4. Errors when the matching directory entry's `current_version` (and `contract_version` for adapters) doesn't match the collection's actual version. Note-level when the resource-listings repo isn't reachable from the preflight context.

---

## [1.2.0] — 2026-04-30

### Added

- **`develop` skill: native permissions awareness (v3.1.0+).** When the developer is authoring a task that touches shared resources, `develop` proactively surfaces the right access-control patterns: tasks with `produces_shared_artifacts: true` need an `aifs_share` step in their workflow, shared state files need `if_revision`, tasks calling v2.0+ ops need an adapter `contract_version` pre-flight. Cross-references the new "Designing for Native Permissions" section in `collection-authoring-guide.md`. Pushes back on agent-index-side permission state (grants log, resolved view) — backend ACLs are the source of truth.
- **`developer-guide` skill: v3.1.0 awareness.** Updated priority-order list of source documents to flag the new "Designing for Native Permissions" section in the authoring guide and the `agent-index-filesystem/SPEC.md` v2.0.0 contract (with note about the gdrive-only contract status). Two new common-question patterns: "How do I share / check permissions / audit a resource?" and "What admin tasks ship with agent-index-core?" — both v3.1.0+.
- **`preflight` task: four new check categories** (v1.2.0):
  - **README freshness** — every name in `collection.json` `api` array appears in README; numerical claims like "All N tools" match the actual count; version mentions in the README don't drift from `collection.json` `version`.
  - **ROADMAP version match** — if `ROADMAP.md` exists with a `Current version: X.Y.Z` line, it must match `collection.json`.
  - **Adapter manifest bundle freshness** — if `adapter.json` exists at the collection root, `bundle_built_at` and `exec_bundle_checksum` are checked against the actual bundle file (mtime + sha256).
  - **CLAUDE.md template alias coverage** (agent-index-core only) — every `type: task` API entry should appear in the Core aliases table in `.claude/CLAUDE.md.template`.
  - **Cross-package coordination reminder** — if the CHANGELOG mentions adapter contracts, new ops, new tasks, OAuth scope changes, permission, or schema changes, emits a NOTE to remind the developer to consider whether the developer collection's docs reference the new patterns.

### Changed

- `develop` 1.1.0 → 1.2.0
- `developer-guide` 1.1.0 → 1.2.0
- `preflight` 1.1.0 → 1.2.0
- All API-member manifests bumped to `collection_version: 1.2.0`

---

## [1.1.1] — 2026-04-19

### Added
- **Natural language trigger phrases in `collection.json`.** API entries now include trigger arrays that map conversational phrases to capabilities, powering the routing layer introduced in agent-index-core 3.0.5. Members can say things like "develop a collection" or "run preflight" instead of using `@ai:` alias syntax. Triggers are customizable per-member via `routing.json`.

## [1.1.0] — 2026-04-06

### Added
- `optimize` task — workflow token efficiency auditor. Reads collection task workflows, classifies each step as judgment or mechanical, estimates token cost of mechanical steps, and produces an optimization report with script extraction recommendations. Apply mode generates parameterized scripts and rewrites workflow steps to call them.
- Script-first design phase in the develop skill (new Phase 4). During collection scaffolding, mechanical workflow steps are now identified and scaffolded as parameterized script calls from the beginning rather than inline Claude instructions.
- Token efficiency check in the preflight task (new Step 8). Flags mechanical workflow steps as optimization notes and validates existing script usage quality.

### Changed
- Develop skill workflow renumbered: Phase 4 (script extraction) inserted, Scaffold is now Phase 5, Auto-Preflight is now Phase 6.
- Preflight task workflow renumbered: Token Efficiency Check is Step 8, Marketplace Checks is Step 9, Generate Report is Step 10.

## [1.0.0] — 2026-04-06

### Added
- `develop` skill — interactive collection development partner. Supports new collection creation, evolving existing collections, and version bump workflows. Adapts to developer experience level (beginner through advanced).
- `preflight` task — release-readiness checker. Nine-step systematic validation covering file completeness, frontmatter validity, version consistency, cross-reference integrity, setup template quality, content quality, and marketplace-specific checks. Reports errors, warnings, and notes with fix instructions.
- `developer-guide` skill — always-available reference skill. Searches standards, authoring guide, file format specs, capability provider spec, and filesystem adapter spec to answer development questions.
- `developer-tutorial` skill — guided tour of collection development with eight topics. Supports guided tour mode (sequential) and question mode (jump to any topic).
- Collection-level setup interview with `default_output_path`, `preflight_strictness`, and `auto_preflight` parameters.
