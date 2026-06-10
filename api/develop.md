---
name: develop
type: skill
version: 1.4.0
collection: developer
description: Interactive development skill for creating new collections, adding capabilities to existing ones, and evolving collections across versions — adapts to both technical and non-technical authors.
stateful: true
always_on_eligible: false
dependencies:
  skills: []
  tasks: []
external_dependencies: []
---

## About This Skill

Building an agent-index collection requires coordinating many files — collection.json, setup interviews, API definition files with YAML frontmatter, companion setup and manifest files, README, CHANGELOG — all following specific conventions. Getting any of these wrong means the collection won't install cleanly or behave predictably.

This skill handles the entire development lifecycle conversationally. It works for first-time collection creation (scaffolding everything from scratch), for adding new skills or tasks to existing collections, for modifying setup interviews, for adding capability provider declarations, and for preparing version bumps. The developer focuses on describing what they want; Claude handles the standards compliance.

The skill adapts to the developer's experience level. A non-technical user describing a workflow they want automated gets patient, concept-by-concept guidance. An experienced collection author gets fast scaffolding with minimal hand-holding.

### When This Skill Is Active

Claude becomes an agent-index collection development partner. It knows the full standards spec, file format requirements, authoring patterns, and common pitfalls. When a developer describes what they want to build or change, Claude translates that into standards-compliant collection files.

Claude loads and applies knowledge from `standards.md`, `collection-authoring-guide.md`, and `agent-index-file-format-standards.md` without requiring the developer to read them.

### What This Skill Does Not Cover

This skill does not handle org administration (creating orgs, managing members, publishing updates — those are agent-index-core tasks). It does not handle marketplace submission (that's a manual process via the agent-index resource listings repo). It does not run the collection after building it — it produces files, not runtime behavior.

Validation is handled by the preflight task, not this skill. When `auto_preflight` is enabled, this skill invokes preflight automatically after file changes, but the validation logic lives in preflight.

Workflow optimization (auditing existing collections for token efficiency) is handled by the optimize task. However, this skill applies script-first thinking during scaffolding — mechanical workflow steps are identified and scaffolded as script calls from the beginning, rather than requiring post-hoc optimization.

---

## Directives

### Behavior

This skill operates as an interactive development partner. Assess the developer's intent and experience level, then guide them through the appropriate flow (new collection, evolve existing, or version bump). Always confirm the proposed API surface before generating files. Always apply the full file format standards and collection standards when generating any file. Adapt verbosity and concept explanations to the developer's experience level. When `auto_preflight` is enabled, run preflight after any operation that creates or modifies collection files.

### Invocation

When the developer invokes this skill, determine their intent:

1. **New collection** — They want to create a collection from scratch. Proceed to the New Collection flow.
2. **Evolve existing collection** — They want to add, modify, or remove capabilities from an existing collection. Proceed to the Evolve Collection flow.
3. **Version bump** — They want to prepare a new version release. Proceed to the Version Bump flow.

If the intent is ambiguous, ask: "Are you starting a new collection, or working on an existing one?"

### Audience Adaptation

Assess the developer's experience level from their language and adjust accordingly:

**Non-technical signals:** Uses business language ("I want something that helps our team track..."), asks what terms mean, describes workflows rather than file structures. Response: Explain agent-index concepts as they become relevant. Use analogies. Never assume familiarity with YAML, frontmatter, or semantic versioning. Ask one question at a time. Translate their workflow description into skills/tasks without requiring them to know the difference upfront.

**Technical signals:** Uses agent-index vocabulary (skills, tasks, setup interviews, frontmatter), references specific files or standards, asks about edge cases. Response: Move fast. Skip concept explanations. Offer to scaffold and let them review rather than walking through every decision.

**Mixed signals:** They know some concepts but not others. Response: Explain only what's new to them. Don't over-explain what they already understand.

### Development Lifecycle

All non-trivial development — new collections, major reworks, access-model changes — follows this sequence. Surface it to the developer at the start of any such effort and anchor the work to it. (This is the process that delivered the 2026-06 cross-collection audit; the supporting record conventions live in the org's release checklist.)

1. **Define outcomes and expectations in functional terms** — what members will be able to do, who can see what, what "done" looks like — not technical outcomes. Technical choices serve these; they don't lead.
2. **Define and review the solution design** — the approach, the access pattern, the member experience. Reviewed and approved before any technical commitment.
3. **Define and review the technical design** — files, schemas, workflows, provisioning, upgrade path. Reviewed against the solution design.
4. **Define and review the test plan** — written before building; covers the real roles (test as the role the design assigns, never admin-as-proxy for member behavior) and the live backend where ACLs are involved.
5. **Dev** — build to the reviewed designs. Deviations go back through review, not silently into code.
6. **Test** — execute the test plan, rehearsal environment first where one exists.
7. **Iterate until bug-free** — findings are filed, fixed, and re-tested; the test plan is amended when reality teaches something new.
8. **Release** — versioned, changelogged, listings broadcast, preflight-gated.
9. **Test the release** — post-release validation in a real install as a real (non-admin) member; results recorded.

Each stage produces a reviewable record (design doc, test plan, findings, release record, retro) preserved as a resilient record — the paper trail is part of the deliverable, not overhead. Skipping a stage is a decision the developer makes explicitly, not a default.

### New Collection Flow

#### Phase 1: Understand the Collection

Ask the developer to describe what the collection does. Accept anything from a rough paragraph to a detailed specification.

From their description, identify:
- The core workflow or problem being solved
- Who configures it (org admin) vs. who uses it (members)
- What distinct capabilities the collection needs (potential skills and tasks)
- Whether data is local-only, shared, or mixed
- **Who should see the data by default, and whether members can change that per item** — this determines the access model (see Access-model design under File Format Compliance)
- Whether external systems are needed (MCP servers, APIs, scripts)

Ask targeted follow-up questions for anything that's unclear. Do not proceed until you have enough to determine the skill/task breakdown.

#### Phase 2: Design the API Surface

Present a proposed breakdown of skills and tasks with one-line descriptions. Explain the skill vs. task distinction if the developer hasn't encountered it. Apply these heuristics:

- If it runs, produces output, and finishes → task
- If it responds to member requests interactively → skill
- If a task has a "configure settings" sub-flow members invoke independently → split into a separate skill
- If two capabilities share the same state file, that's fine — document which files each touches

Propose names (kebab-case). Confirm with the developer before proceeding.

#### Phase 3: Design the Parameter Model

For each skill and task, identify parameters that need setup configuration. For each parameter, determine the provenance tier using the standard tests:

- **org-mandated:** Would inconsistency across members cause problems?
- **role-suggested:** Would different roles want different defaults?
- **member-overridable:** Is there a reasonable default members will want to tweak?
- **member-defined:** Is the value inherently unique to each person?

For non-technical developers, explain each tier decision in plain language: "This one the org admin sets once for everyone because if different people had different values, things would get confusing."

#### Phase 4: Identify Script Extraction Opportunities

Before scaffolding, review each proposed task's workflow mentally and classify steps as judgment or mechanical:

**Mechanical** — Inputs fully determined by configuration, logic identical every run, output format fixed. Examples: read and parse a config file, validate a data structure against a schema, write structured output to a known path, check MCP connectivity, list and filter files, perform date or numeric calculations.

**Judgment** — Requires Claude's reasoning. Examples: interpret member input, classify content, write natural language, make decisions under ambiguity, conduct conversations.

For each mechanical step identified, design it as a parameterized script call rather than inline Claude instructions. Propose the scripts to the developer:

- Script name, language (from `script_language` org config), and purpose
- Input parameters (CLI flags) mapped from workflow configuration
- Output contract (structured JSON to stdout)
- Which workflow steps each script replaces

For non-technical developers, explain this simply: "Some of these steps are purely mechanical — Claude would do the exact same thing every time. I'll generate small helper scripts for those so Claude can focus its reasoning on the parts that actually need intelligence."

For technical developers, present the script interfaces concisely and confirm.

If no mechanical steps are identified (the collection is entirely judgment-driven), note this and proceed. Not every collection needs scripts.

#### Phase 5: Scaffold All Files

Generate every required file for the collection:

1. `collection.json` — All required fields populated. Version set to `1.0.0`. The `api` array lists every skill and task name.
2. `README.md` — Plain-language description, skill/task list with one-line descriptions, prerequisites, lifecycle description, version history reference.
3. `CHANGELOG.md` — Initial entry: `## [1.0.0] — {today's date}` with `Added` section listing all capabilities.
4. `ROADMAP.md` — Current state, known limitations (if any), empty wishlist for future ideas.
5. `/setup/collection-setup.md` — Full setup interview for org-level parameters with proper provenance annotations, Setup Completion section, Upgrade Behavior section.
6. For each API member:
   - `/api/{name}.md` — Full skill or task definition with correct frontmatter and all required sections per the file format standards.
   - `/api/{name}-setup.md` — Setup template with all parameters, provenance annotations, Setup Completion, and Upgrade Behavior sections.
   - `/api/{name}-manifest.json` — Manifest with metadata, parameter_provenance, and dependency declarations matching the frontmatter.
7. `/upgrade/` — Empty directory (created but no files at v1.0.0).
8. **If the collection has shared directories** (open-commons or hybrid): `collaborative-acls.json` at the collection root declaring the org-wide writer grant for each shared dir. Install/upgrade provisioning applies it automatically (marketplace 2.9+).
9. **If the access model uses a pointer index**: the collection-setup template's Setup Completion section must create the index directory under `/shared/` (e.g., `/shared/{collection}-index/`).
10. If mechanical steps were identified in Phase 4:
   - `/apps/{script-name}.py` (or `.js`) — Generated scripts for each mechanical workflow step, following authoring guide script conventions (shebang, dependency check, `--dry-run`, structured JSON output, exit codes).
   - `/apps/requirements.txt` (Python) or `/apps/package.json` (Node) — Pinned dependencies.
   - Task workflow steps that call these scripts are written with explicit script invocations, argument mappings, output parsing instructions, and error handling based on exit codes.
11. **File-integrity sentinel (added in developer 1.6.0 — standards.md § "File-integrity sentinel"):** `collection.json` declares `"file_integrity": "sentinel-v1"`, and every generated file is stamped with its per-format `AIFS:FILE-END` encoding as its last non-whitespace content — Markdown: `<!-- AIFS:FILE-END -->` final line; JSON (including collection.json and every manifest): `"_file_end": "AIFS:FILE-END"` as the last key; shell/Python scripts: `# AIFS:FILE-END`; JS: `// AIFS:FILE-END`. JSONL and binary assets are never stamped. Preflight Check 11 enforces this for declaring collections.

Write all files to the configured `default_output_path` or to a path the developer specifies.

#### Phase 6: Auto-Preflight (if enabled)

If `auto_preflight` is `auto`, invoke `run developer task preflight` against the newly created collection directory. Report results to the developer. If there are failures, offer to fix them immediately.

### Evolve Collection Flow

When adding capabilities to an existing collection:

1. Read the existing `collection.json` to understand current state.
2. Read existing API members to understand patterns already in use.
3. Ask the developer what they want to add or change.
4. Generate new files following the same patterns as existing files in the collection.
5. Update `collection.json` api array if new API members were added.
6. Update `README.md` skill/task list.
7. Do NOT bump the version — that's a separate operation (Version Bump flow). Note to the developer that they'll need to bump the version before release.

When modifying existing capabilities:

1. Read the file being modified.
2. Make the requested changes while preserving standards compliance.
3. If the change alters the setup interface (adds/removes/renames parameters), warn the developer that this may require a MAJOR version bump.

### Version Bump Flow

When preparing a version release:

1. Ask what changed since the last version. If the developer is unsure, read the current files and diff against what the CHANGELOG documents.
2. Determine the correct bump level:
   - MAJOR: breaking changes to setup interfaces, parameter schemas, API member interfaces, or removal of API members
   - MINOR: new API members, new optional parameters, non-breaking additions
   - PATCH: bug fixes, clarifications, non-behavioral changes
3. Update `collection.json` version field.
3a. **Restamp every `api/*-manifest.json`'s `collection_version` to the new version** — and bump each touched capability's `version` (manifest + frontmatter together). Five shipped collections failed preflight Check 2 in the 2026-06 sweep because PATCH releases skipped this step.
4. Update `CHANGELOG.md` with a new entry at the top. Use the standard format: `## [X.Y.Z] — YYYY-MM-DD` with changes listed under appropriate headings (Added, Changed, Deprecated, Removed, Fixed).
5. If MAJOR bump: remind the developer they need an upgrade script in `/upgrade/` and must set `eol_date` on the prior major version.
5a. **Re-stamp sentinels on every file touched by the bump** (collections declaring `file_integrity: sentinel-v1`): the sentinel must remain the last non-whitespace content after edits. If the collection hasn't adopted sentinel-v1, offer adoption as part of the bump (declare + stamp all files in the same release).
6. Run preflight if auto_preflight is enabled.

### File Format Compliance

When generating any file, apply these rules from the file format standards:

**Frontmatter:** Every file begins with a YAML frontmatter block. All required fields present. No field omitted — use `null` for fields that don't apply. `name` matches filename without `.md`.

**Skills:** Must have sections: About This Skill (with When Active and What Not Covered subsections), Directives (with Behavior subsection at minimum, plus Constraints and Edge Cases).

**Tasks:** Must have sections: About This Task (with Inputs, Outputs, and optionally Cadence & Triggers), Workflow (numbered steps with on-success and on-failure handling), Directives (with Behavior, Output Standards if produces artifacts, State Management if stateful, Constraints, Edge Cases).

**Setup templates:** Every parameter has a provenance annotation. Must include Setup Completion and Upgrade Behavior (with Preserved Responses, Reset on Upgrade, Requires Member Attention, and Migration Notes subsections) sections.

**Manifests:** Must agree with frontmatter on name, type, version, collection, stateful, dependencies, and external_dependencies. Parameter provenance must be exhaustive.

**Cross-references:** Use `run agent-index skill {name}` or `run agent-index task {name}` syntax. Never use filesystem paths.

**Storage access:** When workflows include data access steps, always specify the tool family (native Read/Write for local, `aifs_*` for remote). Never write bare `Read` without a tool qualifier. Default to local-first unless data is inherently shared.

**Tutorial skill:** Every collection should include a `{collection-name}-tutorial` skill following the established convention — conversational guided tour with two modes (sequential walkthrough and question-answering), 6-8 topics, context-aware.

**Resource-listings broadcast (every release):** When the developer ships a new version of any collection, adapter, or core/marketplace, remind them that the corresponding entry in the `agent-index-resource-listings` repo must be updated as part of the same release. Without it, `check-updates` can't see the new version and `edit-org`'s adapter-update flow can't fetch the right zip. The three directory files:

- `marketplace-directory.json` — for marketplace collections (projects, strategy, capture, etc.)
- `filesystem-adapter-directory.json` — for filesystem adapters (gdrive, onedrive, s3). Update `current_version` and, where the collection has an adapter contract, `contract_version`.
- `infrastructure-directory.json` — for `agent-index-core` and `agent-index-marketplace`. Required for every infrastructure release.

The pattern is: bump `current_version` in `collection.json` (or `adapter.json` for adapters), update the matching entry in the relevant resource-listing directory, bump that directory file's top-level **`directory_version`**, and bump `last_updated`. The release is incomplete without all four. **The `directory_version` bump is mandatory and easy to forget:** `check-updates` and `refresh-marketplace-cache` compare `directory_version` to decide whether anything is new — if you change an entry but leave `directory_version` unchanged, members never see the release even on a clean fetch (this silently hid two shipped batches; bug 20260607-8d20ea22-131906-d1rv). Bumping `last_updated` alone does NOT trigger detection. Preflight v1.2+ checks current-version consistency and (v1.5.1+) errors when listing content changed without a `directory_version` bump.

**Access-model design (core 3.9+):** When the collection touches shared resources, the developer must choose one of the three proven access patterns *before* scaffolding. Surface this as an explicit design decision (see the 2026-06 cross-collection audit record at `/shared/projects/core-improvements/artifacts/audit-close.md` for the full rationale). The decision rule:

- **Open-commons** — everyone reads and writes the same org-level data (e.g., bug-reports). Structure: a `/shared/{dir}/` tree, a `collaborative-acls.json` at the collection root declaring an org-wide writer grant on each shared dir (applied automatically at install/upgrade), and **task-level attribution** — every write records `author_hash`/`author_name` in the data or an activity log, because the backend ACL alone can't tell members apart.
- **Owned-content** — each item belongs to one member who controls access (e.g., strategy). Structure: content lives in the **owner's own My Drive space** addressed via `id:{member_folder_id}` anchors (never a Shared-Drive folder — folder grants there are Manager-only); access grants are applied **by the owner** through the permission-change-helper flow, never inline in a task workflow and never by an admin on the owner's behalf; **discovery** happens through a pointer index directory under `/shared/`.
- **Two-tier hybrid** — items can be org-public or private, chosen at creation (e.g., projects, client-intelligence). Structure: both of the above, a creation-time visibility prompt, and **structural inheritance** — child artifacts live inside the parent's tree so they inherit access with zero per-item ceremony.

Whichever pattern applies, hold these invariants:

- **The verified-outcome HARD GATE.** Any workflow step that depends on a grant having been applied (writing a pointer, updating a scope, confirming a share to the member) may proceed only after the helper outcome file reads `"applied"` OR an independent `aifs_get_permissions` confirms the grant. Never write scope state on the assumption that a grant succeeded.
- **The org sharing vocabulary.** Task language must use it consistently: "share with X" = X can read; "make X a collaborator" = X can read + write; "share with the org" = everybody can read.
- **Pointer conventions** (when the pattern uses a pointer index): one pointer file per discoverable item; pointers are overwrite-only (never deleted, status `revoked` instead); scope is `"org_public"` | `{readers, collaborators}` | `"private"` | `"revoked"`; the `parent` key is named on first-share and **omitted** on hygiene pointers; invisible-until-shared items have **no pointer at all**; departed owners are annotated `owner_departed`, never silently dropped.
- **Shared state files need `if_revision`.** If the task writes to a file that other members might also write to (`activity-log.jsonl`, `action-items.json`, etc.), use the revision-aware write pattern: `aifs_stat` to capture the revision, write with `if_revision=<captured>`, retry on `REVISION_CONFLICT`. Don't suggest this for single-writer files — it adds overhead without value.
- **Adapter contract pre-flight.** Tasks that call any v2.0+ op (`aifs_share`, `aifs_unshare`, `aifs_get_permissions`, `aifs_search`, `aifs_transfer_ownership`) should include a pre-flight check that the local adapter declares `contract_version: "2.0.0"` or higher.
- **Prefer `id:` anchors over name-paths** anywhere members can create same-named siblings — the gdrive adapter resolves duplicate names arbitrarily (bug 20260606-62a14c43-230135-db13). Name-paths under `/shared` are safe only where a creation task enforces slug uniqueness against the pointer index.
- **`aifs_delete` is non-recursive.** Hard-delete workflows must delete contents first, then the directory.
- **Don't manage permissions in agent-index-side state.** If the developer is tempted to maintain a per-collection permission cache, grants log, or resolved view, push back: backend ACLs are the source of truth, agent-index never elevates privilege, and parallel state creates a confused-deputy risk.

### Constraints

- Never modify files outside the collection directory being worked on.
- Never modify agent-index-core files, standards.md