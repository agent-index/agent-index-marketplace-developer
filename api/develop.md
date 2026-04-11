---
name: develop
type: skill
version: 1.0.0
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

### New Collection Flow

#### Phase 1: Understand the Collection

Ask the developer to describe what the collection does. Accept anything from a rough paragraph to a detailed specification.

From their description, identify:
- The core workflow or problem being solved
- Who configures it (org admin) vs. who uses it (members)
- What distinct capabilities the collection needs (potential skills and tasks)
- Whether data is local-only, shared, or mixed
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
8. If mechanical steps were identified in Phase 4:
   - `/apps/{script-name}.py` (or `.js`) — Generated scripts for each mechanical workflow step, following authoring guide script conventions (shebang, dependency check, `--dry-run`, structured JSON output, exit codes).
   - `/apps/requirements.txt` (Python) or `/apps/package.json` (Node) — Pinned dependencies.
   - Task workflow steps that call these scripts are written with explicit script invocations, argument mappings, output parsing instructions, and error handling based on exit codes.

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
4. Update `CHANGELOG.md` with a new entry at the top. Use the standard format: `## [X.Y.Z] — YYYY-MM-DD` with changes listed under appropriate headings (Added, Changed, Deprecated, Removed, Fixed).
5. If MAJOR bump: remind the developer they need an upgrade script in `/upgrade/` and must set `eol_date` on the prior major version.
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

### Constraints

- Never modify files outside the collection directory being worked on.
- Never modify agent-index-core files, standards.md, or the authoring guide.
- Never invent new frontmatter fields not in the file format standards.
- Never omit required frontmatter fields — use `null` rather than omitting.
- Never generate files with authoring notes (`# NOTE:`) — those are for the templates only.
- Always confirm the proposed API surface with the developer before generating files.
- Always use today's date for new CHANGELOG entries and collection metadata.

### Edge Cases

If the developer asks to build a collection in the `infrastructure` category, explain that this category is reserved for agent-index-core and agent-index-marketplace. Suggest `developer-tools` or another appropriate category.

If the developer asks to build a collection whose name starts with `agent-index-`, explain that this prefix is reserved for official agent-index collections. Suggest an alternative name.

If the developer describes something that's better served by an existing collection, mention that collection and confirm they still want to build a new one.

If the developer wants to add capability provider declarations, read `capability-provider-spec.md` for the full specification and walk them through provider and consumer declarations, including the operation mapping and binding setup.

If the collection being evolved has inconsistencies (e.g., api array doesn't match actual files), flag them before making changes. Offer to fix them as part of the current operation.
