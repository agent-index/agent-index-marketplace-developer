# Agent-Index File Format Standards
## Template Definitions & Authoring Conventions

**Status:** Released
**Authors:** Bill Salak
**Last Updated:** 2026-11-03

---

## Table of Contents

1. [Overview](#1-overview)
2. [Shared Conventions](#2-shared-conventions)
3. [Skill Definition Template](#3-skill-definition-template)
4. [Task Definition Template](#4-task-definition-template)
5. [Setup Template](#5-setup-template)
6. [Role Definition Template](#6-role-definition-template)
7. [Collection Setup Template](#7-collection-setup-template)
8. [Validation Rules](#8-validation-rules)

---

## 1. Overview

This document defines the required format for every file type in the agent-index system. These formats are the contract that makes the system interoperable — the installer, the Session Start Task, and Claude's runtime behavior all depend on files being well-formed.

There are five file types:

| File Type | Authored By | Read By | Purpose |
|---|---|---|---|
| **Skill definition** | Collection author | Claude at invocation | Tells Claude how to perform a category of work |
| **Task definition** | Collection author | Claude at task run | Defines a workflow with steps and behavioral rules |
| **Setup template** | Collection author | Claude at member install | Interview definition for personalizing a skill or task |
| **Role definition** | Collection or org author | Claude at onboarding | Describes a member's function and bootstrap configuration |
| **Collection setup template** | Collection author | Claude at collection install | Org-admin configuration interview for a collection |

All five file types share common conventions defined in Section 2. Type-specific templates follow in Sections 3–7.

---

## 2. Shared Conventions

### YAML Frontmatter

Every file begins with a YAML frontmatter block. Frontmatter is machine-readable by Claude and by the installer. It is the authoritative source for metadata — never infer metadata from filename or location alone.

```yaml
---
# required fields present in all five file types
name: {kebab-case-identifier}
type: skill | task | setup | role | collection-setup
version: {MAJOR.MINOR.PATCH}
collection: {collection-name}
description: {one sentence, plain language}
---
```

All frontmatter fields are lowercase kebab-case keys. Values are strings unless noted. No field may be omitted — use `null` for fields that do not apply rather than omitting them.

### Markdown Body

The body following frontmatter is structured markdown. Section headers use `##` as the top level within the file body — `#` is reserved for the document title if present, but files in the system do not require a top-level title (the frontmatter `name` and `description` serve that purpose).

### Kebab-Case Naming

All `name` values in frontmatter are kebab-case: lowercase, hyphen-separated, no spaces, no special characters other than hyphens. Examples: `writing-style`, `email-manager`, `request-time-off`.

### Versioning

All files use semantic versioning (`MAJOR.MINOR.PATCH`) in their frontmatter. The collection version and the individual file version are not required to match — a collection at `2.0.0` may contain a skill at `1.3.0` that has not changed since the collection's last major bump. However, any breaking change to a file's interface requires a MAJOR bump in both the file and the collection.

### Cross-References

References to other skills or tasks within definition files use the agent-index reference syntax:

```
run agent-index skill {skill-name}
run agent-index task {task-name}
```

For references to API members of a specific collection (used when calling across collections):

```
run {collection-name}:{skill-or-task-name}
```

Never use filesystem paths in cross-references. Paths are resolved at runtime from `member-index.json`.

### Authoring Notes

Lines beginning with `# NOTE:` are authoring notes — guidance for collection authors reading the template. They must be removed in any published collection file. They are not instructions to Claude.

---

## 3. Skill Definition Template

### Purpose

A skill definition tells Claude how to perform a category of work. It is loaded into session context when the skill is invoked (either explicitly by the member or automatically as an always-on skill). Once loaded, Claude applies the skill's directives to any relevant work in the session.

### File Location

```
/{collection-name}/api/{skill-name}.md       ← public skills
/{collection-name}/internal/{skill-name}.md  ← private skills
```

### Template

```markdown
---
name: {skill-name}
type: skill
version: {MAJOR.MINOR.PATCH}
collection: {collection-name}
description: {one sentence describing what this skill enables Claude to do}
stateful: true | false
always_on_eligible: true | false
dependencies:
  skills: []
  tasks: []
external_dependencies: []
---

## About This Skill

# NOTE: This section is for human understanding. Claude reads it to answer
# questions like "what does this skill do?" and "when should I use it?"
# Write in plain language. Describe what the skill does, what kinds of work
# it applies to, what output or behavior changes when it is active, and any
# important constraints or limitations.

{2–5 paragraphs. Plain language. No implementation detail.}

### When This Skill Is Active

{Describe what changes about Claude's behavior when this skill is loaded.
What does Claude do differently? What does a member notice?}

### What This Skill Does Not Cover

{Explicit scope boundaries. What adjacent work is out of scope and why.
This prevents overreach and sets member expectations correctly.}

---

## Directives

# NOTE: This section is Claude's operating instructions. Write precisely and
# imperatively. Claude reads and follows these instructions when the skill
# is active. Avoid ambiguity. Use sub-sections to organize by concern.
# Do not include rationale or explanation here — that belongs in About This Skill.

### Behavior

# NOTE: This subsection is REQUIRED and must be the first heading under
# Directives. Even if your skill has complex internal structure (invocation
# patterns, operation lists, topic flows), Behavior comes first. It captures
# the skill's overall operating posture in 2-4 sentences. Skill-specific
# subsections follow after it.

{Core behavioral instructions. What Claude does when this skill is active.
Be specific. Use imperative voice: "Always...", "Never...", "When X, do Y."}

### Style & Tone

# NOTE: Include only if this skill affects how Claude writes or communicates.
# Omit this sub-section entirely if not applicable.

{Instructions about voice, tone, formality, length, format of outputs
produced while this skill is active.}

### Constraints

{Hard rules. Things Claude must never do while this skill is active.
Things Claude must always do. Non-negotiable boundaries.}

### Edge Cases

# NOTE: Document known edge cases and how Claude should handle them.
# These will grow over time as the skill is used in practice.

{Specific situations that require non-obvious handling. One per paragraph
or bullet. Format: "If {condition}, then {action}."}
```

### Frontmatter Field Reference

| Field | Required | Type | Notes |
|---|---|---|---|
| `name` | Yes | string | Kebab-case. Must match filename. |
| `type` | Yes | string | Always `skill` |
| `version` | Yes | string | Semantic version |
| `collection` | Yes | string | Parent collection name |
| `description` | Yes | string | One sentence, plain language |
| `stateful` | Yes | boolean | Whether the skill maintains state across sessions |
| `always_on_eligible` | Yes | boolean | Whether this skill can be designated always-on in preferences |
| `dependencies.skills` | Yes | array | Names of required skills. Empty array if none. |
| `dependencies.tasks` | Yes | array | Names of required tasks. Empty array if none. |
| `external_dependencies` | Yes | array | External systems required. Empty array if none. |

### Well-Formed Skill Checklist

- [ ] Frontmatter complete with no omitted fields
- [ ] `name` matches filename (without `.md`)
- [ ] `About This Skill` section written for a human reader, no implementation detail
- [ ] `When This Skill Is Active` clearly describes observable behavior change
- [ ] `What This Skill Does Not Cover` defines scope boundaries explicitly
- [ ] `Directives` section present with `### Behavior` as its first subsection
- [ ] `Directives` written in imperative voice
- [ ] No authoring notes (`# NOTE:`) remaining in published file
- [ ] All cross-references use `run agent-index` syntax, not filesystem paths

### Convention: Tutorial Skills

Collections should include a tutorial skill named `{collection-name}-tutorial`. This is an established pattern followed by all current marketplace collections (projects-tutorial, strategy-tutorial, capture-tutorial).

A tutorial skill is a guided tour of the collection's concepts and workflows. It explains but does not perform operations or modify data. The standard structure:

- **Type:** skill (not task — tutorials are conversational, not workflow-producing)
- **Two modes:** guided tour (sequential topic walkthrough) and question-answering (jump to any topic)
- **Context-aware:** reads the member's setup and org config to know which features are enabled, so it can reference their actual configuration rather than speaking generically
- **Topic count:** typically 6–8 topics covering: what the collection does, each major capability, how things connect, and tips for getting the most out of the system
- **Tone:** conversational and practical, not documentation-style — the tutorial should feel like a knowledgeable colleague walking you through the system

Tutorial skills are optional but strongly recommended. They significantly reduce the learning curve for new members and serve as a reference members can revisit.

---

## 4. Task Definition Template

### Purpose

A task definition tells Claude what work to do, in what sequence, and how to behave while doing it. It is the operative document for a workflow. It is read at the start of any session where the task is active (if state loading is eager) or when the task is explicitly invoked.

### File Location

```
/{collection-name}/api/{task-name}.md       ← public tasks
/{collection-name}/internal/{task-name}.md  ← private tasks
```

### Template

```markdown
---
name: {task-name}
type: task
version: {MAJOR.MINOR.PATCH}
collection: {collection-name}
description: {one sentence describing what this task does}
stateful: true | false
produces_artifacts: true | false
produces_shared_artifacts: true | false
dependencies:
  skills: []
  tasks: []
external_dependencies: []
reads_from: null | {path pattern}
writes_to: null | {path}
---

## About This Task

# NOTE: This section is for human understanding. Claude reads it to answer
# questions about what this task does, when to use it, what it produces,
# and how it fits into the member's workflow. Write for a non-technical reader.

{2–5 paragraphs. What problem does this task solve? What does a member
get when they run it? How does it relate to other tasks or skills?}

### Inputs

{What does this task need to run? Member-provided inputs, files, external
data, state from prior sessions. Be explicit about what is required vs.
optional.}

### Outputs

{What does this task produce? Describe each artifact type, its format,
where it goes (personal vs. shared artifacts), and how it might be used
downstream. If this task feeds an aggregation task, say so explicitly.}

### Cadence & Triggers

# NOTE: Include if this task is intended to run on a schedule or in response
# to specific triggers. Omit if purely on-demand.

{How often is this task typically run? What prompts a member to run it?
What signals that it should be run again?}

---

## Workflow

# NOTE: This section defines the explicit sequence of steps Claude executes.
# Steps are numbered. Each step has a title and a description of what Claude
# does and what decisions it makes. Steps should be granular enough to be
# unambiguous but not so granular they become implementation code.
# Steps may reference skills: "Apply run agent-index skill {name} here."

### Step 1: {Step Title}

{What Claude does in this step. What it reads, processes, decides, or
produces. What constitutes successful completion of this step.}

**On success:** {proceed to Step 2 | produce artifact X | notify member}
**On failure or missing input:** {how Claude handles the failure — ask member, skip, abort}

### Step 2: {Step Title}

{...}

**On success:** {...}
**On failure or missing input:** {...}

### Step N: {Step Title}

{Final step. Typically: write current-state.md, produce summary for member,
write shared artifact if applicable.}

**On success:** {session complete}
**On failure or missing input:** {...}

---

## Directives

# NOTE: Behavioral instructions that apply throughout the entire task —
# not step-specific logic, which belongs in the Workflow section.
# These are standing rules Claude follows for the duration of the task.

### Behavior

{How Claude behaves throughout this task. Tone, level of autonomy vs.
member check-ins, how to handle ambiguity, what decisions Claude makes
independently vs. escalates.}

### Output Standards

{Requirements for any artifacts this task produces. Format, structure,
naming conventions, required sections. If a schema exists, reference it:
"Shared artifacts must conform to {task-name}-schema.json."}

### State Management

{Instructions for how Claude maintains and writes current-state.md.
What must always be recorded. What constitutes a meaningful state change
worth persisting. How to handle interrupted sessions.}

### Constraints

{Hard rules. Things Claude must never do within this task. Non-negotiable
boundaries around data handling, external system interaction, artifact
production.}

### Edge Cases

{Specific situations requiring non-obvious handling.
Format: "If {condition}, then {action}."}
```

### Frontmatter Field Reference

| Field | Required | Type | Notes |
|---|---|---|---|
| `name` | Yes | string | Kebab-case. Must match filename. |
| `type` | Yes | string | Always `task` |
| `version` | Yes | string | Semantic version |
| `collection` | Yes | string | Parent collection name |
| `description` | Yes | string | One sentence, plain language |
| `stateful` | Yes | boolean | Whether the task maintains state in `current-state.md` |
| `produces_artifacts` | Yes | boolean | Whether the task produces any artifacts |
| `produces_shared_artifacts` | Yes | boolean | Whether any artifacts are written to the remote `/shared/` namespace via `aifs_write` |
| `dependencies.skills` | Yes | array | Required skills. Empty array if none. |
| `dependencies.tasks` | Yes | array | Required tasks. Empty array if none. |
| `external_dependencies` | Yes | array | External systems required. Empty array if none. |
| `reads_from` | Yes | string or null | Remote path pattern (under `/shared/`) for aggregation task inputs. `null` if not reading shared data. |
| `writes_to` | Yes | string or null | Remote path (under `/shared/`) for shared artifact output. `null` if not writing shared data. |

### Well-Formed Task Checklist

- [ ] Frontmatter complete with no omitted fields
- [ ] `name` matches filename (without `.md`)
- [ ] `About This Task` section written for a human reader
- [ ] `Inputs` and `Outputs` sections explicit about required vs. optional
- [ ] Every step has a title, body, and explicit on-success and on-failure handling
- [ ] Final step always writes `current-state.md` (if `stateful: true`)
- [ ] `Directives` contains no step-specific logic (that belongs in `Workflow`)
- [ ] `Output Standards` references schema file if `produces_shared_artifacts: true`
- [ ] No authoring notes (`# NOTE:`) remaining in published file
- [ ] All cross-references use `run agent-index` syntax

---

## 5. Setup Template

### Purpose

A setup template defines the interview Claude conducts with a member when they install a skill or task. It produces a personalized installed instance and a `setup-responses.md` file that persists the member's answers across upgrades.

Setup templates are the mechanism by which org-mandated constraints, role-suggested defaults, and member customizations are applied. Every parameter collected in a setup template must be annotated with its level.

### File Location

```
/{collection-name}/api/{skill-or-task-name}-setup.md
/{collection-name}/internal/{skill-or-task-name}-setup.md
```

### Parameter Level Annotations

Every parameter in a setup template is annotated inline with its level using a YAML-style tag:

```
[org-mandated]      ← fixed; not presented to member for input
[role-suggested]    ← default derived from role; member may override
[member-overridable] ← explicitly customizable; setup step presents for confirmation
[member-defined]    ← no default; member must provide a value
```

### Template

```markdown
---
name: {skill-or-task-name}-setup
type: setup
version: {MAJOR.MINOR.PATCH}
collection: {collection-name}
description: Setup interview for {skill-or-task-name}
target: {skill-or-task-name}
target_type: skill | task
upgrade_compatible: true | false
---

## Setup Overview

# NOTE: Explain to the member (via Claude) what this setup step will do,
# roughly how long it takes, and what they will have at the end.
# Claude reads this to frame the setup conversation naturally.

{1–2 sentences. What will the member configure? What will they get when done?}

---

## Pre-Setup Checks

# NOTE: List any conditions Claude must verify before beginning the interview.
# Examples: required skills already installed, external system access confirmed,
# member profile has a role assigned. If a check fails, define what Claude does.

- {Check description} → {action if fails}
- {Check description} → {action if fails}

---

## Parameters

# NOTE: Each parameter is a named configuration value the setup interview
# collects or assigns. Parameters are grouped by level — org-mandated first,
# then role-suggested, then member-overridable, then member-defined.
# Within each group, parameters appear in the order Claude should address them.

### Org-Mandated Parameters [org-mandated]

# NOTE: These are fixed values set at the org level during collection setup.
# Claude does NOT ask the member for these — they are injected from the
# collection's org-level setup responses. List them here for transparency
# so members understand what has been pre-configured for them.
# Claude should be able to tell a member "this is set by your org" if asked.

**{parameter-name}** [org-mandated]
- Description: {what this parameter controls}
- Value source: injected from collection org-setup-responses
- Member visibility: read-only (Claude may explain the value if asked)

---

### Role-Suggested Parameters [role-suggested]

# NOTE: These parameters have defaults derived from the member's role.md.
# Claude presents the suggested value and asks the member to confirm or change it.
# The interview phrasing should make the role context natural:
# "Based on your role as {role}, I'd suggest {value} — does that work for you?"

**{parameter-name}** [role-suggested]
- Description: {what this parameter controls}
- Role source: {which field in role.md provides the default, or "role name match"}
- Default logic: {how the default is derived — e.g., "Engineering role → daily at 9am; Sales role → twice daily"}
- Interview prompt: "{exact question or prompt Claude uses with the member}"
- Accepted values: {enumerated options, format, or free text description}
- If no role match: {fallback behavior — use a hardcoded default, ask member directly}

---

### Member-Overridable Parameters [member-overridable]

# NOTE: These parameters have org or system defaults but are explicitly
# designated as member-customizable. Claude presents the current default
# and invites the member to change it. Keep the invitation light —
# most members will accept defaults.

**{parameter-name}** [member-overridable]
- Description: {what this parameter controls}
- Default: {the value if member does not override}
- Interview prompt: "{question Claude uses — optional, can be presented as 'you can change this if you like'}"
- Accepted values: {options, format, or free text description}

---

### Member-Defined Parameters [member-defined]

# NOTE: These parameters have no default. Claude must collect a value from
# the member before setup can complete. Mark required vs. optional clearly.
# If optional and not provided, define the skip behavior.

**{parameter-name}** [member-defined]
- Description: {what this parameter controls}
- Required: true | false
- Interview prompt: "{exact question or prompt Claude uses}"
- Accepted values: {options, format, or free text description}
- If skipped (optional only): {behavior when member skips this parameter}

---

## Setup Completion

# NOTE: Define what Claude does when all parameters are collected.
# Always includes: write setup-responses.md, write the installed instance,
# write entry to member-index.json. May also include: run a verification
# step, surface an external dependency notice, confirm alias assignment.

1. Write all collected parameter values to `setup-responses.md`
2. Generate the personalized installed instance from the template using collected values
3. Write the installed instance to `members/{member_hash}/installed/{collection}/{type}/{name}/` (`{type}` is `skill` or `task`; core `org-setup.md`)
4. Write manifest.json with parameter provenance for each field
5. Register entry in `member-index.json` with assigned alias
6. {Any additional completion steps specific to this skill or task}
7. Confirm completion to member: "{summary of what was configured and how to invoke}"

---

## Upgrade Behavior

# NOTE: This section governs how setup-responses.md is handled when a member
# upgrades to a new version. It is read by Claude during the upgrade flow.

### Preserved Responses
{List parameters whose prior responses are carried forward unchanged during upgrade.}

### Reset on Upgrade
{List parameters that are reset to defaults on upgrade — typically when the
parameter definition has changed in a way that makes the old response invalid.}

### Requires Member Attention
{List parameters that Claude must explicitly surface to the member during upgrade —
typically new parameters added in this version, or parameters whose meaning has
changed significantly.}

### Migration Notes
# NOTE: Free-form notes for Claude about non-obvious migration logic.
# Add version-specific notes here as the setup template evolves.

- v{X.Y} → v{X.Y}: {description of what changed and any special handling}
```

### Frontmatter Field Reference

| Field | Required | Type | Notes |
|---|---|---|---|
| `name` | Yes | string | `{target-name}-setup` |
| `type` | Yes | string | Always `setup` |
| `version` | Yes | string | Semantic version — should track target's version |
| `collection` | Yes | string | Parent collection name |
| `description` | Yes | string | One sentence |
| `target` | Yes | string | Name of the skill or task this setup serves |
| `target_type` | Yes | string | `skill` or `task` |
| `upgrade_compatible` | Yes | boolean | Whether upgrade flow can auto-migrate prior responses |

### Well-Formed Setup Template Checklist

- [ ] Every parameter has an explicit level annotation
- [ ] Org-mandated parameters are listed but not presented as interview questions
- [ ] Role-suggested parameters include role source and fallback behavior
- [ ] Member-defined required parameters are clearly marked
- [ ] Setup Completion section defines all writes explicitly
- [ ] Upgrade Behavior section present (even if all fields are "none")
- [ ] No authoring notes (`# NOTE:`) remaining in published file

---

## 6. Role Definition Template

### Purpose

A role definition describes a member's function within the org. It provides Claude with context about who the member is, pre-selects a relevant starting set of skills and tasks for onboarding, and supplies role-suggested parameter defaults for setup interviews.

Role definitions are authored in YAML frontmatter plus markdown body. The frontmatter carries the machine-readable configuration; the markdown body provides the rich context Claude carries about the role.

**Relationship to org-level roles:** The agent-index system has two complementary role layers. **Org roles** are defined in `org-config.json` by org admins and determine which collections a member is prompted to install during onboarding (e.g., an "Engineer" org role might default to the Projects and Developer Tools collections). **Per-collection roles** (defined here) operate within a single collection and determine which skills and tasks within that collection are recommended for the member, along with parameter defaults. During onboarding, a member first selects an org role (if defined), which narrows the collection focus, and then selects per-collection roles within those collections for fine-grained configuration.

### File Location

```
/{collection-name}/roles/{role-name}.md
```

### Template

```yaml
---
name: {role-name}
type: role
version: {MAJOR.MINOR.PATCH}
collection: {collection-name}
description: {one sentence describing this role}
extends: {parent-role-name} | null
display_name: {Human Readable Role Name}

# Skills recommended for this role at onboarding
# Format: collection-name/skill-name
recommended_skills:
  - {collection-name}/{skill-name}
  - {collection-name}/{skill-name}

# Tasks recommended for this role at onboarding
# Format: collection-name/task-name
recommended_tasks:
  - {collection-name}/{task-name}
  - {collection-name}/{task-name}

# Role-suggested parameter defaults
# These are injected into setup interviews as role-suggested defaults.
# Key format: {collection-name}/{skill-or-task-name}/{parameter-name}
parameter_defaults:
  {collection-name}/{task-name}/{parameter-name}: {value}
  {collection-name}/{task-name}/{parameter-name}: {value}
  {collection-name}/{skill-name}/{parameter-name}: {value}

# Skills and tasks explicitly excluded from this role
# Used when this role extends a parent and needs to remove items
# Format: collection-name/skill-or-task-name
exclusions: []
---
```

```markdown
## Role Context

# NOTE: This is the rich context Claude carries about this role throughout
# every session for a member assigned this role. Write it as a briefing —
# what Claude needs to understand about this person's function, priorities,
# working patterns, and how they interact with the rest of the org.
# This is not a job description — it is operational context for Claude.

### Function
{What does a person in this role do day to day? What are their primary
responsibilities? What outcomes are they accountable for?}

### Working Patterns
{How does this role typically work? Asynchronous or synchronous? High email
volume? Lots of cross-functional coordination? Heavy document production?
Describe the patterns that affect how Claude should behave.}

### Key Relationships
{Who does this role work with most closely? Who do they report to? Who
reports to them? What external parties do they interact with?}

### Priorities & Defaults
{What should Claude understand about this role's priorities? What kinds of
work get elevated attention? What communication style is typical for this role?}
```

### Inheritance Behavior

When a role has `extends: {parent-role-name}`, the following rules apply at flattening time:

- `recommended_skills` and `recommended_tasks`: child items are appended to parent items
- `parameter_defaults`: child values override parent values for the same key
- `exclusions`: items listed in child exclusions are removed from the flattened set, including items inherited from the parent
- `extends` field: removed in the flattened output — the installed `role.md` in the member profile has no inheritance references
- Org-mandated parameters (from setup templates) cannot be overridden by role defaults regardless of inheritance

### The Installed Role (`role.md`)

The file written to `/members/{member_hash}/profile/role.md` at onboarding is the fully flattened version. It contains:

- The complete `recommended_skills` and `recommended_tasks` lists (inheritance resolved)
- The complete `parameter_defaults` map (inheritance resolved, exclusions applied)
- The full markdown body from the deepest role in the chain (child body takes precedence; parent body appended if child body does not explicitly supersede)
- No `extends` field

### Well-Formed Role Definition Checklist

- [ ] `extends` is either a valid role name or `null` — never omitted
- [ ] All `recommended_skills` and `recommended_tasks` entries use `collection/name` format
- [ ] All `parameter_defaults` keys use `collection/skill-or-task/parameter` format
- [ ] `exclusions` is present (empty array if none)
- [ ] Markdown body has all four sections: Function, Working Patterns, Key Relationships, Priorities & Defaults
- [ ] Body is written as operational context for Claude — not a job description
- [ ] No authoring notes (`# NOTE:`) remaining in published file

---

## 7. Collection Setup Template

### Purpose

The collection setup template defines the interview Claude conducts with an **org admin** when a collection is installed via the marketplace. This is distinct from the per-skill and per-task setup templates — it operates at the collection level and establishes the org-mandated parameter values that flow down into all skill and task setup interviews for members.

Values collected here become the `[org-mandated]` values in every skill and task setup template within the collection.

### File Location

```
/{collection-name}/setup/collection-setup.md
```

### Template

```markdown
---
name: {collection-name}-collection-setup
type: collection-setup
version: {MAJOR.MINOR.PATCH}
collection: {collection-name}
description: Org-admin setup interview for the {collection display name} collection
upgrade_compatible: true | false
---

## Collection Setup Overview

# NOTE: This is read by Claude to frame the setup conversation with the org admin.
# Explain what this setup does, what decisions the admin will make, and what
# the collection will be able to do once setup is complete.

{2–3 sentences. What will this setup configure? What will the org get when done?
Roughly how many questions or decisions are involved?}

---

## Prerequisites

# NOTE: Conditions that must be true before setup can proceed.
# Claude verifies these before starting the interview.

- Admin has org admin credentials in agent-index
- {External system access required, if any}
- {Other prerequisites}

---

## Org-Level Parameters

# NOTE: These are the parameters the admin configures at the org level.
# They become [org-mandated] values in member-level setup interviews.
# Group them logically — by concern, not by level (everything here is org-level).
# For each parameter: describe what it controls, what the accepted values are,
# and what the implication of each choice is. Admins may not be technical —
# write prompts that a non-technical admin can answer confidently.

### {Parameter Group Name}

**{parameter-name}**
- Description: {what this parameter controls across the org}
- Applies to: {which skills/tasks in this collection use this value}
- Interview prompt: "{exact question or prompt Claude uses with the admin}"
- Accepted values: {enumerated options with plain-language descriptions, or format}
- Default: {recommended default and why}
- Implication of choices: {brief description of what each major choice means for the org}

**{parameter-name}**
- Description: {...}
- Applies to: {...}
- Interview prompt: "{...}"
- Accepted values: {...}
- Default: {...}
- Implication of choices: {...}

---

## External System Configuration

# NOTE: Include this section only if the collection requires external system
# access. For each external dependency, define what the admin must provide
# and how Claude should handle the case where access is not yet available.

### {External System Name}

- Access required: {description of what access is needed}
- Configuration required: {API keys, OAuth, webhook URLs, etc. — at a conceptual level, not implementation}
- Interview prompt: "{how Claude asks the admin to confirm or provide access details}"
- If not available: {behavior — install proceeds but affected skills/tasks flagged as inoperable until configured}

---

## Setup Completion

1. Write all collected parameter values to `collection-setup-responses.md`
2. Confirm to admin: "{summary of what was configured}"
3. Surface list of skills and tasks now available for members to install
4. Surface any external dependencies not yet configured, with next steps
5. {Any additional completion steps specific to this collection}

---

## Upgrade Behavior

### Preserved Responses
{Parameters carried forward unchanged when the collection is upgraded.}

### Reset on Upgrade
{Parameters reset to defaults on upgrade.}

### Requires Admin Attention
{Parameters that must be explicitly reviewed by the admin during upgrade —
new parameters, changed meanings, deprecated options.}

### Migration Notes
- v{X.Y} → v{X.Y}: {description of what changed and any special handling}
```

### Frontmatter Field Reference

| Field | Required | Type | Notes |
|---|---|---|---|
| `name` | Yes | string | `{collection-name}-collection-setup` |
| `type` | Yes | string | Always `collection-setup` |
| `version` | Yes | string | Semantic version — should track collection version |
| `collection` | Yes | string | Parent collection name |
| `description` | Yes | string | One sentence |
| `upgrade_compatible` | Yes | boolean | Whether upgrade flow can auto-migrate prior responses |

### Well-Formed Collection Setup Checklist

- [ ] All org-level parameters have `applies-to` declared
- [ ] Every parameter has an interview prompt written for a non-technical admin
- [ ] Implications of choices are described, not just the options
- [ ] External system configuration section present if any external dependencies exist
- [ ] Setup Completion section defines all writes explicitly
- [ ] Upgrade Behavior section present
- [ ] No authoring notes (`# NOTE:`) remaining in published file

---

## 8. Validation Rules

### Checked at Collection Install Time (marketplace `download-collection` and `install-collection`)

These are the only checks the marketplace installer makes when an org admin downloads and installs a collection. Each one stops the install.

| Check | Where | Result |
|---|---|---|
| `collection.json` is readable and its `name` matches the collection | `download-collection` Step 5, `install-collection` Step 1 | Error — download is removed, or install halts |
| `setup/collection-setup.md` is present | `install-collection` (Edge Cases) | Error — install halts |
| On an org on core 4.0.0 or later: the collection is at least its minimum version and doesn't call the retired permission helper | `install-collection` Step 1 | Error — install halts; the admin downloads a newer version |

The installer does not validate the rest of `collection.json`, the `api/` files or their frontmatter. External dependencies declared in `collection.json` are shown to the admin as a reminder after setup; they are not validated.

### Required Before Publishing (not checked at install)

These are authoring requirements. Nothing blocks an install that breaks them, so authors must meet them before publishing. They are defined in `marketplace-eligibility.md` § "Required File Structure", § "API Member Requirements" and § "Skill and Task File Requirements" (this collection); preflight covers parts of them.

| Rule | Scope |
|---|---|
| `collection.json` present with all required fields | Collection root |
| All `api[]` entries have a corresponding `.md` file | Collection |
| All `.md` files in `api/` and `internal/` have valid frontmatter | Per file |
| `name` in frontmatter matches filename | Per file |
| `type` value matches expected type for location | Per file |
| All `dependencies` reference installable skills/tasks | Per file |
| All `external_dependencies` declared in `collection.json` | Collection |
| `CHANGELOG.md` present | Collection root |
| `README.md` present | Collection root |

### Rules Enforced at Member Install Time (by Org Setup Skill)

These rules are checked when a member installs an individual skill or task.

| Rule | Scope | Severity |
|---|---|---|
| All `[member-defined]` required parameters have values | Per setup | Error — blocks completion |
| All `[org-mandated]` parameters have values from collection setup | Per setup | Error — blocks completion |
| All declared skill dependencies are installed | Per task | Warning — flags as incomplete |
| Schema file present if `produces_shared_artifacts: true` | Per task | Warning — flags as incomplete |

### Rules Enforced at Runtime (by Claude)

These rules apply during task and skill execution.

| Rule | Scope | Enforcement |
|---|---|---|
| Skills are loaded before tasks that depend on them | Session | Claude surfaces error and offers to load |
| Shared artifacts validated against schema before write | Per artifact | Claude blocks write until required fields satisfied |
| `current-state.md` written at end of stateful task session | Per task | Claude writes automatically — not author-implemented |
| Audit log entry written at task run completion | Per task | Written automatically by task lifecycle |

---

## Person Field Schema

Any file that references people — owners, assignees, team members, reviewers, or similar — must use the structured person field schema rather than bare name strings. This applies to all collection data files (project records, task outputs, shared artifacts, etc.).

### Schema

```yaml
owner:
  display_name: "Bill Salak"
  member_hash: "a7f3b2c1d4e5f698"    # or null if unregistered
  email: "bill@agent-index.ai"        # or null if unregistered
```

For arrays of people:

```yaml
members:
  - display_name: "Sarah Kim"
    member_hash: "a1b2c3d4e5f6a7b8"
    email: "sarah@example.com"
    role: Contributor
  - display_name: "Alex"
    member_hash: null
    email: null
    role: Reviewer
```

### Rules

- `display_name` is always required and always populated
- `member_hash` and `email` are populated from the members registry when a match is found, or set to `null` for unregistered people
- The resolution process (searching the registry, confirming matches, handling unregistered people) is defined in `marketplace-eligibility.md` § "Member Resolution in Collection Workflows" (this collection)
- Collections that support editing should provide a way to retroactively link unregistered members to their registry entries

---

*These format standards are maintained in the developer collection. A breaking change to an existing file format affects every collection that uses it and the core flows that read it (install, update, setup), so coordinate it with the core maintainers before releasing it, and version it under `marketplace-eligibility.md` § "Versioning Requirements" (this collection).*
