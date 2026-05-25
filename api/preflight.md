---
name: preflight
type: task
version: 1.4.0
collection: developer
description: Systematic release-readiness check for a collection — validates standards compliance, version consistency, cross-reference integrity, changelog hygiene, and catches the loose ends that slip through during development.
stateful: false
produces_artifacts: false
produces_shared_artifacts: false
dependencies:
  skills: []
  tasks: []
external_dependencies: []
reads_from: null
writes_to: null
---

## About This Task

validate-collection in agent-index-core checks structural compliance — are the required files present, is the frontmatter valid? Preflight goes further. It checks whether a collection is actually ready to ship: did you bump the version? Does the changelog reflect what changed? Are there stale cross-references? Do the manifest and frontmatter agree? Is the README current?

This distinction matters because collections can be structurally valid but not release-ready. A collection where every file parses correctly but the version in collection.json is still 1.0.0 after adding three new API members will pass validate-collection and fail in production. Preflight catches that.

The task produces a report organized by severity: errors (must fix before release), warnings (should fix, may cause problems), and notes (suggestions for improvement). It explains each finding and how to fix it.

### Inputs

A path to the collection directory to check. If not specified, Claude asks which collection to check.

Optionally:
- Strictness level override (`marketplace` or `org`) — defaults to the org-configured `preflight_strictness`
- A specific check category to run in isolation (e.g., "just check versions" or "just check frontmatter")

### Outputs

A preflight report displayed to the developer. No files written. The report is structured as:

1. Summary line: pass/fail with counts of errors, warnings, notes
2. Errors section (if any): each error with location, description, and fix instructions
3. Warnings section (if any): each warning with location, description, and recommendation
4. Notes section (if any): suggestions for improvement

### Cadence & Triggers

On demand, or automatically after develop skill operations when `auto_preflight` is enabled. Should be run before any version bump, marketplace submission, or org deployment.

---

## Workflow

### Step 1: Locate and Load the Collection

Read the collection directory. Confirm `collection.json` exists and is valid JSON.

Parse `collection.json` and extract: name, version, api array, dependencies, category.

Read the `/setup/collection-setup.md` and all files in `/api/`.

**On success:** Proceed to Step 2 with the full file inventory.
**On failure:** Report "Cannot read collection at {path}" with the specific error (missing directory, malformed JSON, etc.) and stop.

---

### Step 2: File Completeness Check

Verify every required file exists:

**Collection-level files:**
- [ ] `collection.json` exists and is valid JSON
- [ ] `README.md` exists
- [ ] `CHANGELOG.md` exists
- [ ] `/setup/collection-setup.md` exists
- [ ] `/upgrade/` directory exists (may be empty at v1.0.0)

**Per-API-member files:** For every name in the `collection.json` `api` array:
- [ ] `/api/{name}.md` exists
- [ ] `/api/{name}-setup.md` exists
- [ ] `/api/{name}-manifest.json` exists

**Cross-check:** Flag any files in `/api/` that are NOT referenced in the `api` array (orphaned files). Flag any names in the `api` array that have no corresponding files (missing implementations).

**On success:** Proceed to Step 3.
**On failure:** Record each missing or orphaned file as an error. Continue checking remaining items.

---

### Step 3: Frontmatter Validation

For every `.md` file in `/api/` and `/setup/`:

**Parse frontmatter:** Verify valid YAML. Record parse errors.

**Required fields by type:**

For `type: skill`:
- [ ] `name` present and matches filename (without `.md`)
- [ ] `type` is exactly `skill`
- [ ] `version` present and valid semver
- [ ] `collection` present and matches `collection.json` `name`
- [ ] `description` present (non-empty string)
- [ ] `stateful` present (boolean)
- [ ] `always_on_eligible` present (boolean)
- [ ] `dependencies` present with `skills` and `tasks` sub-arrays
- [ ] `external_dependencies` present (array)

For `type: task`:
- [ ] `name` present and matches filename (without `.md`)
- [ ] `type` is exactly `task`
- [ ] `version` present and valid semver
- [ ] `collection` present and matches `collection.json` `name`
- [ ] `description` present (non-empty string)
- [ ] `stateful` present (boolean)
- [ ] `produces_artifacts` present (boolean)
- [ ] `produces_shared_artifacts` present (boolean)
- [ ] `dependencies` present with `skills` and `tasks` sub-arrays
- [ ] `external_dependencies` present (array)
- [ ] `reads_from` present (string or null)
- [ ] `writes_to` present (string or null)

For `type: setup`:
- [ ] `name` present and matches filename (without `.md`)
- [ ] `type` is exactly `setup`
- [ ] `version` present and valid semver
- [ ] `collection` present and matches `collection.json` `name`
- [ ] `description` present
- [ ] `target` present (name of the skill/task this setup serves)
- [ ] `target_type` present (`skill` or `task`)
- [ ] `upgrade_compatible` present (boolean)

For `type: collection-setup`:
- [ ] `name` present
- [ ] `type` is exactly `collection-setup`
- [ ] `version` present and valid semver
- [ ] `collection` present and matches `collection.json` `name`
- [ ] `description` present
- [ ] `upgrade_compatible` present (boolean)

**On success:** Proceed to Step 4.
**On failure:** Record each frontmatter issue as an error. Continue checking.

---

### Step 4: Version Consistency Check

This is where preflight goes beyond validate-collection. Check:

**collection.json version vs. CHANGELOG:**
- [ ] The version in `collection.json` has a corresponding entry in `CHANGELOG.md`
- [ ] The newest CHANGELOG entry matches the `collection.json` version
- [ ] If they don't match, this is an ERROR: either the version wasn't bumped or the changelog wasn't updated

**API member versions vs. collection version:**
- [ ] No API member has a MAJOR version higher than the collection's MAJOR version (warning — unusual, may indicate a version bump was missed at collection level)
- [ ] If collection version is > 1.0.0, check that at least one API member version has changed since the prior changelog entry (warning if nothing changed — did you mean to bump?)

**collection.json version vs. setup versions:**
- [ ] `collection-setup.md` version is consistent (same MAJOR as collection, or explicitly documented as stable across versions)

**Upgrade directory check:**
- [ ] If collection version MAJOR > 1, verify `/upgrade/` contains at least one migration file
- [ ] Migration files follow naming convention (e.g., `1-to-2.md`)

**ROADMAP version match (if `ROADMAP.md` exists):**
- [ ] If the ROADMAP contains a `Current version: X.Y.Z` line, it matches `collection.json` `version`
- [ ] Mismatch is a WARNING (the ROADMAP is supplementary; the CHANGELOG is canonical), but it usually means the ROADMAP was forgotten during the version bump

**Adapter manifest bundle freshness (if `adapter.json` exists at the collection root):**
- [ ] If `adapter.json` declares `exec_bundle_entry`, verify the file at that path exists
- [ ] Compare `adapter.json` `bundle_built_at` (ISO timestamp) against the actual mtime of the bundle file. If the bundle is newer than `bundle_built_at` by more than a minute, ERROR — the adapter manifest is referencing a stale build timestamp
- [ ] If `adapter.json` declares `exec_bundle_checksum` (`sha256:<hex>`), compute the bundle's actual sha256 and compare. Mismatch is an ERROR — the manifest's checksum is stale, members will see verification failures
- [ ] If `adapter.json` exists but `bundle_built_at` or `exec_bundle_checksum` is absent, WARNING — these fields are required for trustable distribution

**Adapter supported-ops vs bundle implementation (added in preflight v1.2.3, closes bug `20260502-8d20ea22-2`):**

If `adapter.json` declares `supported_operations`, every op name listed must actually be implemented in the bundle. Pre-1.2.3 the freshness checks above caught manifest-vs-bundle drift on timestamps and checksums, but not on the *content* of the bundle relative to the manifest's claims. The gdrive 2.2.0 release shipped with `supported_operations` declaring `share`, `unshare`, `getPermissions`, `search`, `transferOwnership` while the bundle was byte-identical to 2.1.3 (no implementations) — and timestamp/checksum agreed with each other, so the freshness check passed. This new check closes that gap.

- [ ] Read `adapter.json` `supported_operations` (array of strings).
- [ ] Read the bundle file (path from `adapter.json` `exec_bundle_entry`, or `dist/aifs-exec.bundle.js` as the v3 default).
- [ ] For each op name in `supported_operations`, search the bundle's text content for at least one of these patterns (case-insensitive substring match is sufficient):
  - the literal op name (e.g., `share`)
  - the canonical wrapper name `aifs_<snake_case_op>` (e.g., `aifs_share`)
  - a handler-pattern match: `case '<op>':`, `'<op>'\s*:\s*(async\s*)?function`, `async\s+<op>\s*\(`
- [ ] If any op name has zero matches across all three patterns: ERROR with the bundle path, the `adapter.json` path, the missing op name(s), and the patterns that were tried. The author has either declared an op the bundle doesn't implement, or named the op differently in the bundle than in the manifest. Either way, the manifest is lying about its bundle's capabilities.
- [ ] If `supported_operations` is empty or absent but `adapter.json` declares `contract_version >= 2.0.0`: WARNING — the v2.0 contract requires at least the read ops (`read`, `write`, `list`, `exists`, `stat`, `delete`, `copy`); an empty `supported_operations` array is suspicious.

The check is grep-based rather than AST-based for portability — the bundle could be in any of several JS bundling formats, and parsing it correctly is much more work than substring-matching. False positives from substring matching are theoretically possible (e.g., "share" appears in some unrelated comment) but extremely unlikely to coincide with all the v2.0 op names simultaneously. The check is asymmetric: false positives (claiming the bundle has an op when it doesn't) are the dangerous case; false negatives (incorrectly flagging a bundle that does have the op under a name we don't recognize) are recoverable by adjusting the search patterns.

**Shipped shell-script line endings (added in preflight v1.2.3, closes bug `20260504-8d20ea22-7`):**

Shell scripts shipped in a collection's runtime artifact directories must have LF line endings, regardless of the host OS the author is committing from. Pre-1.2.3 nothing prevented a Windows-host commit from including `\r\n` line endings in `*.sh` files; the resulting script fails to execute under bash with a confusing error (`bash: script.sh: $'\r': command not found`). The 2026-05-04 helper smoke-test on dev_install hit this exact failure — `mcp-servers/permission-helper/show-plan.sh` shipped with CRLF and bash refused it.

- [ ] Walk the collection's shipped-artifact directories: `lib/`, `bin/`, and any subdirectories. Collect every file whose name ends in `.sh`.
- [ ] For each `*.sh` file, read the file as bytes and search for any `0x0D` byte (CR character).
- [ ] If any `0x0D` byte is present (whether as part of a CRLF sequence or a standalone CR): ERROR with the file path and a count of the offending lines. The fix is mechanical — convert to LF-only line endings (`dos2unix`, `sed -i 's/\r$//'`, or "Save With Unix Line Endings" in any text editor) before commit.

The check is shell-script-only. Other text files (markdown, JSON, etc.) tolerate either line ending without breaking — they're out of scope. Shell scripts that legitimately need CR characters are rare enough to warrant explicit `# allow-crlf` markers (out of scope for this version — flag as ERROR universally; the rare false-positive is acceptable cost for catching the much-more-common Windows-host accident).

**Resource-listings broadcast freshness (added in preflight v1.2):**

The `agent-index-resource-listings` repo holds three directory files that broadcast version availability to `check-updates`, `edit-org`'s adapter-update flow, and `refresh-marketplace-cache`. Whenever a release ships, the relevant directory entry MUST be updated. Preflight checks this for the collection currently under review:

- [ ] **Marketplace collections:** if the collection is one listed in `marketplace-directory.json` (any entry under `collections[]`), check that the entry's `current_version` matches `collection.json` `version`. ERROR on mismatch — the broadcast is stale, admins won't see the upgrade.
- [ ] **Filesystem adapters:** if the collection has an `adapter.json` at root, check that the entry in `filesystem-adapter-directory.json` matches both `current_version` and (where applicable) `contract_version`. ERROR on mismatch.
- [ ] **Infrastructure (core, marketplace):** if the collection name matches an entry in `infrastructure-directory.json` (`agent-index-core`, `agent-index-marketplace`), check that the entry's `current_version` matches `collection.json` `version`. ERROR on mismatch — without this update, admins can't discover that core/marketplace has a new release.
- [ ] If the collection isn't represented in any directory: NOTE only (org-internal collections aren't required to publish, but a newly-published collection that should be discoverable but isn't listed will fall through this check; the cross-package coordination reminder picks it up).

The check works by reading the directory files via a relative path (`../agent-index-resource-listings/`) when run from a sibling clone of the resource-listings repo, or via a configurable `resource_listings_path` parameter when not. If neither is reachable, surface a NOTE: "Could not locate agent-index-resource-listings; skipped broadcast freshness check. Verify manually."

**`inherit: false` spec usage vs adapter contract version (added in preflight v1.4.0, closes section 4 of idea `helper-spec-needs-inherit-passthrough`):**

The permission-helper v1.1 spec format added an `inherit: boolean` field to share operations. The adapter contract version (`contract_version` in `adapter.json`, distinct from `adapter_version`) governs whether the adapter actually honors the field. Pre-2.0 adapters silently ignore `inherit`, applying the share with default-additive semantics instead of override semantics — degraded behavior, not a failure. Forward-compatible specs targeting future post-2.0 adapter rollouts must remain authorable, so this check is a WARNING (not an ERROR).

- [ ] Read the adapter's `contract_version` from `mcp-servers/filesystem/adapter.json` (NOT `adapter_version` from `agent-index.json` — they're different fields). Resolution order: `ADAPTER_CONTRACT_OVERRIDE` env var override (for CI / synthetic tests), then candidate install layouts (`$COLL/../mcp-servers/...`, `$COLL/../../mcp-servers/...`, `$AGENT_INDEX_INSTALL_DIR/mcp-servers/...`).
- [ ] If no `contract_version` can be resolved: skip the check with a notice. (Preflight may be running outside an install context where no adapter is materialized.)
- [ ] If resolved `contract_version` MAJOR is `>= 2`: pass silently. The org's adapter honors `inherit`; no warning needed.
- [ ] If resolved `contract_version` MAJOR is `< 2`: scan the collection's `api/*.md` for `"inherit": false` (JSON form) or `inherit: false` (YAML form). For each match, surface a WARNING with file path and line number, naming the resolved contract version and the requirement (≥ 2.0.0).

Implemented in `lib/preflight-cli.sh` as Check 8.

**On success:** Proceed to Step 5.
**On failure:** Record version inconsistencies. Errors for hard mismatches, warnings for suspicious patterns.

---

### Step 5: Cross-Reference Integrity

**API array vs. files:**
- [ ] Every name in `collection.json` `api` array has all three companion files (.md, -setup.md, -manifest.json)
- [ ] Every API member's frontmatter `name` field matches its filename
- [ ] Every API member's frontmatter `collection` field matches `collection.json` `name`

**Dependency references:**
- [ ] Every collection listed in `collection.json` `dependencies` is a real collection (check against known marketplace collections if available, otherwise warn)
- [ ] Every skill/task listed in any API member's `dependencies.skills` or `dependencies.tasks` exists (either in this collection's api array or in a declared dependency collection)

**Setup target references:**
- [ ] Every setup template's `target` field references a skill or task that exists in this collection's `/api/` directory

**Manifest-frontmatter agreement:**
- [ ] For each API member, verify the manifest's name, type, version, collection, stateful, dependencies, and external_dependencies match the frontmatter in the corresponding `.md` file. This is a **value-equality** check, not a presence check — the values must be byte-for-byte identical (after JSON/YAML parsing). In particular: the manifest `version` field must equal the `.md` frontmatter `version` field exactly. The `.md` frontmatter is the canonical source of truth for the capability version (it's what `member-index.json` records at install/upgrade time, what `org-setup`'s "Needs Attention" comparison reads, and what `check-updates` Step 4 compares against). A drifted manifest `version` is silently wrong — `member-index` and `org-setup` don't read the manifest, so authors who bump the `.md` frontmatter sometimes forget to bump the manifest, leaving the manifest stale. ERROR with the path to both files and the two values when any field disagrees.

**Manifest collection_version sync (added in preflight v1.2.2):**
- [ ] For each API member's manifest, verify `collection_version` exactly equals the `version` field in `collection.json`. Each release should bump every manifest's `collection_version` to the new collection version so consumers reading the manifest can correctly attribute the capability to its release. ERROR with the path and the two values when they disagree. (Authors who bump `collection.json` `version` without re-running their manifest-sync step are the typical cause.)

The two checks above are paired: together they catch both *vertical* drift (manifest version vs `.md` frontmatter version, the per-capability version) and *horizontal* drift (manifest `collection_version` vs `collection.json` `version`, the collection-level version). Both are forms of "two declared facts that must agree" — the same hazard class as bug `20260430-8d20ea22` (where a comparison read the wrong version field). Closes developer-collection idea `per-capability-manifest-vs-md-version-drift`.

**Capability provider references (if applicable):**
- [ ] If `collection.json` has a `provides` array, every `implemented_by` value references a name in the `api` array
- [ ] If `collection.json` has a `requires` array, every capability type referenced exists as a well-known type or is properly namespaced as a custom type

**On success:** Proceed to Step 6.
**On failure:** Record each broken reference as an error.

---

### Step 6: Setup Template Quality

For every setup template (`-setup.md` and `collection-setup.md`):

**Provenance annotations:**
- [ ] Every parameter section has exactly one provenance annotation: `[org-mandated]`, `[role-suggested]`, `[member-overridable]`, or `[member-defined]`
- [ ] No parameter lacks an annotation (error)
- [ ] No parameter has multiple annotations (error)

**Required sections:**
- [ ] `Setup Completion` section exists and lists at least one write operation
- [ ] `Upgrade Behavior` section exists with all four required subsections:
  - [ ] `Preserved Responses`
  - [ ] `Reset on Upgrade`
  - [ ] `Requires Member Attention`
  - [ ] `Migration Notes`

**Manifest parameter agreement:**
- [ ] Every parameter in the setup template appears in the corresponding manifest's `parameter_provenance` object
- [ ] Every parameter in the manifest's `parameter_provenance` appears in the setup template

**On success:** Proceed to Step 7.
**On failure:** Record setup template issues. Missing provenance annotations are errors. Missing sections are errors.

---

### Step 7: Content Quality Checks

These are warnings and notes, not hard errors:

**README completeness:**
- [ ] Contains a plain-language description of what the collection does
- [ ] Lists all skills and tasks with one-line descriptions
- [ ] Lists prerequisites (other collections, external systems) — or explicitly states none
- [ ] Describes the lifecycle or workflow the collection supports
- [ ] References CHANGELOG.md for version history

**README freshness (added in preflight v1.2):**
- [ ] Every name in `collection.json` `api` array appears in `README.md` (case-insensitive substring match). If any API member is unmentioned, WARNING — the README is likely stale relative to the collection. Most often this is what happens when new tasks ship and the README isn't updated.
- [ ] If `README.md` contains numerical claims like "All N tools" or "N skills" or "N tasks," verify N matches the actual count in `collection.json`. Mismatch is a WARNING — README is stale.
- [ ] If `README.md` mentions a version number (e.g., "v3.0.0", "as of 2.1.0"), verify it isn't ahead of `collection.json` `version` (forward references suggest someone bumped the README without bumping the collection) and isn't trailing by more than one MINOR version (suggests README hasn't been touched for several releases). Mismatches are NOTES.

**CLAUDE.md template alias coverage (agent-index-core only — added in preflight v1.2):**

This check applies only when the collection being preflighted is `agent-index-core`:
- [ ] Read `.claude/CLAUDE.md.template`. Locate the "Core aliases" table (markdown table whose header includes `Request pattern` and `Route to`).
- [ ] For every API entry where `type: task`, verify the alias `@ai:{name}` appears somewhere in that table. WARNING for each task missing.
- [ ] The Core aliases table is supposed to be a fast-path index for member discoverability. New admin-side tasks shipped in this release that aren't in the table will resolve via the catch-all but won't surface in the documented routing.
- [ ] Skills are exempt from this check — most skills are reactive and don't have explicit `@ai:` invocation patterns.

**CHANGELOG format:**
- [ ] Entries in reverse chronological order (newest first)
- [ ] Format: `## [MAJOR.MINOR.PATCH] — YYYY-MM-DD`
- [ ] Changes listed under appropriate headings (Added, Changed, Deprecated, Removed, Fixed)
- [ ] For MAJOR versions: includes migration summary and upgrade script reference

**Naming conventions:**
- [ ] Collection name is kebab-case, lowercase, no special characters except hyphens
- [ ] Collection name does not start with `agent-index-` (unless it's an official collection — flag as note for non-official collections)
- [ ] All skill and task names within the collection are kebab-case
- [ ] All names are globally unique within the collection

**Task workflow quality:**
- [ ] Every task with `type: task` has a Workflow section with numbered steps
- [ ] Every step has an on-success and on-failure clause (warning if missing)
- [ ] If `stateful: true`, the final step writes `current-state.md` (warning if not mentioned)

**Skill directive quality:**
- [ ] Every skill with `type: skill` has a Directives section
- [ ] Directives section includes at minimum a Behavior subsection

**Storage access clarity:**
- [ ] If any workflow references `aifs_read`, `aifs_write`, or remote paths, verify that every data access step explicitly names the tool family (warning for bare `Read` or `Write` without qualifier in workflows that also use `aifs_*`)
- [ ] If `produces_shared_artifacts: true`, verify `writes_to` is not null

**Tutorial skill check:**
- [ ] Collection includes a `{collection-name}-tutorial` skill (note if missing — strongly recommended but not required)

**Authoring note remnants:**
- [ ] No lines beginning with `# NOTE:` remain in any file (error — these must be removed before publishing)

**Cross-package coordination reminder (added in preflight v1.2):**

If this collection's release introduces new behavior that other collections — particularly the developer collection — should know about, surface a NOTE-level reminder. Heuristics:
- [ ] If `CHANGELOG.md`'s newest entry mentions any of: "adapter contract", "new ops", "new operations", "new task" (admin or otherwise), "OAuth scope", "permission", "schema change" — emit a NOTE: "This release introduces behavior that the developer collection (`develop` skill, `developer-guide` skill, `preflight` task) may need to know about. Consider whether the developer collection's docs reference this collection's new patterns and bump it accordingly."
- [ ] This is intentionally a NOTE, not a warning — it's reminding the developer to think about cross-package coordination, not gating release on it.

**On success:** Proceed to Step 8.
**On failure:** Record each finding at the appropriate severity level.

---

### Step 8: Token Efficiency Check

Review each task's workflow steps and flag potential optimization opportunities. These are notes, not errors or warnings — they surface opportunities that the optimize task can act on.

**Mechanical step detection:**
For each workflow step in each task, assess whether the step appears mechanical (inputs fully determined by configuration, logic identical every run, output format fixed). Common indicators:
- [ ] Step reads a file from a known path and extracts specific fields with no interpretation
- [ ] Step validates data against a fixed schema
- [ ] Step writes structured output (JSON, YAML) to a known path with no content generation
- [ ] Step performs arithmetic, date calculation, or hash computation
- [ ] Step checks for file existence, MCP connectivity, or other boolean conditions
- [ ] Step lists and filters directory contents by fixed criteria

For each mechanical step found, emit a note:
```
Note: {task-name} Step {N} ({step title}) appears mechanical — inputs are determined
by configuration and the logic is identical every run. Consider extracting to a
parameterized script. Run `@ai:optimize` for a full efficiency audit.
```

**Existing script usage quality:**
If the collection has an `/apps/` directory with scripts:
- [ ] Every script call in a workflow step specifies the full command with `{variable}` placeholders
- [ ] Every script call describes how to parse the script's output
- [ ] Every script call has error handling based on exit codes
- [ ] Scripts in `/apps/` have `requirements.txt` or `package.json` with pinned dependencies (warning if missing)

**On success:** Proceed to Step 9.
**On failure:** Record each finding as a note.

---

### Step 9: Marketplace-Specific Checks (if strictness = marketplace)

These checks only run at `marketplace` strictness:

- [ ] `collection.json` `marketplace_url` is a valid URL
- [ ] `collection.json` `support_url` is a valid URL
- [ ] `collection.json` `license` is one of: `open`, `commercial`, `proprietary`, or a valid SPDX identifier
- [ ] Collection name does not conflict with any known marketplace collection name
- [ ] `ROADMAP.md` exists (recommended for marketplace collections)
- [ ] README includes clear installation prerequisites and any external system requirements

**On success:** Proceed to Step 10.
**On failure:** Record marketplace-specific issues.

---

### Step 10: Generate Report

Compile all findings into a structured report:

**Summary line:**
```
Preflight: {PASS|FAIL} — {N} errors, {N} warnings, {N} notes
```

PASS if zero errors. FAIL if one or more errors. Warnings and notes do not cause failure.

**Errors section:** Each error includes:
- File path where the issue was found
- Description of what's wrong
- How to fix it (specific, actionable)

**Warnings section:** Each warning includes:
- File path
- Description
- Recommendation

**Notes section:** Each note includes:
- Description
- Suggestion

Present the report to the developer. If there are errors, offer to fix them (invoke the develop skill for corrections).

**On success:** Report delivered. Task complete.

---

## Directives

### Behavior

Be thorough and systematic. Check every file, every field, every cross-reference. The value of preflight is that it catches things humans miss. Do not skip checks for files that "look fine" — run every check against every applicable file.

When reporting issues, be specific about location and fix. Don't say "frontmatter is incomplete" — say "preflight.md is missing the `produces_artifacts` field in frontmatter. Add `produces_artifacts: false` (or `true` if this task produces files)."

When the developer asks to fix issues, apply the minimum change needed. Don't reorganize files or rewrite content that passed checks.

### Output Standards

The report is delivered in chat, not written to a file. Use markdown formatting for readability. Group findings by severity, then by file within each severity level.

### Constraints

- This task is read-only. It examines files but never modifies them.
- Never skip a check category unless the developer explicitly requests a scoped run.
- Never mark a collection as passing if any errors were found, regardless of how minor they seem.
- Never invent new check categories beyond what's defined in the workflow steps.

### Edge Cases

If the collection directory is empty except for collection.json, report all missing files but don't produce an overwhelming list of frontmatter errors for files that don't exist — the missing file errors are sufficient.

If collection.json itself is malformed or missing required fields, report those errors first and note that many downstream checks cannot run without a valid collection.json.

If the developer asks to check a directory that isn't an agent-index collection (no collection.json), say so clearly and suggest they use the develop skill to create one.

If the collection uses capability providers, check provider/consumer declarations but note that full binding validation requires an org context (registered providers) that isn't available at preflight time.
