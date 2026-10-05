# Agent-Index Marketplace Eligibility

**Maintained by:** agent-index
**Last Updated:** 2026-10-05

---

## About This Document

This document holds the requirements a collection must meet to be eligible for the agent-index marketplace, and the authoring rules collections are checked against. It sits in the developer collection beside the checkers that enforce it (`api/preflight.md` and `lib/preflight-cli.sh`).

**Citing it.** Cite as `marketplace-eligibility.md § "Exact Heading"`. Headings only — no line numbers, no bold labels.

**What used to be here.** This document and two others replace core's `standards.md`, which is retired (Core Improvements decision `2026-09-22-retire-standards-md`). Runtime rules are in the org's `CLAUDE.md` and core's `runtime-reference.md`; admin and distribution material is in core's `admin-distribution.md`.

---

## Overview

This document defines the requirements a collection must meet to be eligible for the agent-index marketplace. These standards exist to ensure that any collection an org installs behaves predictably, is maintainable over time, and integrates cleanly with agent-index-core infrastructure.

The standards are open. Any individual, team, or vendor may build and submit a marketplace-eligible collection.

---

## Required File Structure

Every marketplace-eligible collection must have the following files at its root:

```
/{collection-name}/
  collection.json              ← required
  README.md                    ← required
  CHANGELOG.md                 ← required
  ROADMAP.md                   ← recommended (known bugs, wishlist, future direction)
  /api/                        ← required (may be empty only if collection provides roles only)
  /apps/                       ← optional; required location if the collection ships scripts
    requirements.txt           ← required inside /apps/ if the scripts have dependencies
  /setup/
    collection-setup.md        ← required
    collection-setup-responses.md  ← written at install time, not authored
  /upgrade/                    ← required directory (may be empty at v1.0.0)
```

**`/apps/` placement is normative (core 3.29.0).** A collection that bundles helper scripts puts them
in `/apps/` at the collection root — a sibling of `/api/`, `/setup/` and `/upgrade/`, never nested
inside them and never under some other directory of the author's choosing. Skills and tasks both
live inside `/api/`; there are no `/skills/` or `/tasks/` directories at source level, so `/apps/` is
not nested under either.

The same shape carries to the member's machine. `org-setup` materializes `/apps/` to
`members/{member_hash}/installed/{collection}/apps/`, where it sits as a sibling of `skill/` and
`task/`. At both ends the rule is the same: **`apps/` is never inside the capability tree.** One
listing at the root answers "does this collection ship scripts," at source and on disk alike.

Nested structure *within* `/apps/` is the author's business — `apps/gmail-labeler/label_emails.py` is
fine, and materialization preserves it.

---

## `collection.json` Required Fields

All fields listed below are required. No field may be omitted.

| Field | Type | Description |
|---|---|---|
| `name` | string | Kebab-case identifier. Must match the collection directory name. Must be unique in the marketplace. |
| `display_name` | string | Human-readable name |
| `version` | string | Semantic version (MAJOR.MINOR.PATCH) |
| `description` | string | One sentence, plain language |
| `author` | string | Author or organization name |
| `license` | string | License type (`open`, `commercial`, `proprietary`, or SPDX identifier) |
| `category` | string | Functional category (see Category Registry below) |
| `agent_index_min_version` | string | Minimum agent-index-core version required |
| `api` | array | List of public skill/task names. Empty array if none. |
| `dependencies` | array | Names of other collections this collection depends on. Empty array if none. |
| `external_dependencies` | array | External systems required. Empty array if none. |
| `eol_date` | string or null | ISO date string or null |
| `marketplace_url` | string | URL of the collection's Git repository |
| `support_url` | string | URL for support or documentation |

### `collection.json` Optional Fields

The following fields are optional. If omitted, the collection is assumed to neither provide nor require any capability types.

| Field | Type | Description |
|---|---|---|
| `provides` | array | Capability types this collection implements. Each entry declares a capability type, version, and operation-to-skill mapping. Empty array or absent if none. See Capability Provider Requirements below. |
| `requires` | array | Capability types this collection needs from other providers. Each entry declares a capability type, required version range, operations needed, and fallback behavior. Empty array or absent if none. See Capability Provider Requirements below. |

---

## API Member Requirements

Every name listed in `collection.json` `api` array must have a corresponding `.md` file in `/api/`. Each API member file must:

- Have valid YAML frontmatter with all required fields for its type (skill or task)
- Have a `name` field in frontmatter that matches the filename (without `.md`)
- Have a `collection` field that matches the collection name
- Have a corresponding `-setup.md` file in `/api/`
- Have a corresponding `-manifest.json` file in `/api/`

---

## Skill and Task File Requirements

All skill and task definition files (in both `/api/` and `/internal/`) must conform to the agent-index file format standards defined in `agent-index-meta-docs/agent-index-file-format-standards.md`.

Required frontmatter fields for skills:

| Field | Required |
|---|---|
| `name` | Yes |
| `type` | Yes — must be `skill` |
| `version` | Yes |
| `collection` | Yes |
| `description` | Yes |
| `stateful` | Yes |
| `always_on_eligible` | Yes |
| `dependencies` | Yes |
| `external_dependencies` | Yes |

Required frontmatter fields for tasks:

| Field | Required |
|---|---|
| `name` | Yes |
| `type` | Yes — must be `task` |
| `version` | Yes |
| `collection` | Yes |
| `description` | Yes |
| `stateful` | Yes |
| `produces_artifacts` | Yes |
| `produces_shared_artifacts` | Yes |
| `dependencies` | Yes |
| `external_dependencies` | Yes |
| `reads_from` | Yes — null if not aggregating |
| `writes_to` | Yes — null if not aggregating |

---

## Setup Template Requirements

Every skill and task in `/api/` must have a corresponding `-setup.md` file. Setup templates must:

- Have valid YAML frontmatter with `name`, `type: setup`, `version`, `collection`, `description`, `target`, `target_type`, and `upgrade_compatible`
- Declare every parameter with an explicit level annotation (`[org-mandated]`, `[role-suggested]`, `[member-overridable]`, or `[member-defined]`) — **except core-injected parameters, which must NOT be declared at all** (see below)
- Include a `Setup Completion` section listing all writes
- Include an `Upgrade Behavior` section with `Preserved Responses`, `Reset on Upgrade`, `Requires Member Attention`, and `Migration Notes` subsections
- Write member-specific data only to `members/{member_hash}/{collection-name}/` — **never inside `members/{member_hash}/installed/`** (see "Member data placement" below)

---

## Core-Injected Parameters (core 3.29.0+)

A **core-injected parameter** is a value core computes and supplies to every capability's setup
context. Collections consume it as a `{placeholder}` in workflows and setup templates, but do not
declare it, do not describe how it is computed, and never ask a member for it.

This is a deliberate exception to "declare every parameter with an explicit level annotation" above.
Declaring one is a defect, not a style preference: a declared copy is a second source of truth for a
value core owns, it drifts silently the moment core's computation changes, and a `[member-defined]`
declaration additionally prompts the member to type a path core is about to overwrite.

The closed list, as of core 3.29.0:

| Parameter | Value | Available when |
|---|---|---|
| `apps_path` | Stored as `members/{member_hash}/installed/{collection}/apps` — **relative to `project_dir`**. Resolved to an absolute path at invocation. | The collection ships `/apps/` |

**Stored relative, consumed absolute (corrected in core 3.29.2 — `appspathsandboxleak`).** Two
different values are in play and conflating them is the defect this wording exists to prevent:

- **The stored record** in `setup-responses.md` is the *relative* path above. It contains no machine,
  user, drive or mount prefix, so it means the same thing on every host, in every Cowork sandbox, and
  in every session.
- **The consumed value** is resolved at invocation by joining the stored relative path onto whatever
  `project_dir` the current runtime actually has. Workflows use `{apps_path}` exactly as before —
  `python {apps_path}/forward-bug.py` still receives an absolute path and still works from any
  working directory. Nothing changes for collection authors.

3.29.0 and 3.29.1 specified the stored value as absolute, reasoning that bash commands cannot assume
a working directory. That reasoning is sound for the *consumed* value and wrong for the *stored* one.
In Cowork the agent's `project_dir` is a per-session sandbox mount (`/sessions/{session}/mnt/...`),
so an absolute record pinned a path that did not exist on the member's own machine, did not exist in
any other session, and changed on every run. Observed in production immediately after 3.29.1: all 24
recorded values named a sandbox from an already-finished session.

Re-resolve on every setup and upgrade run regardless. The stored record is a record of the last
resolution, not an input to the next one — it exists to be inspectable, not to be trusted.

Nothing else is core-injected today. `project_dir` and `member_workspace` are widely used and
currently declared ad hoc by individual collections; unifying them the same way is tracked in
`ROADMAP.md` and is deliberately out of scope for 3.29.0.

**For collection authors:** use `{apps_path}` freely in workflow bash commands and in Pre-Setup
existence gates. Do not add an `### apps_path` block to any setup template, and do not add an
`apps_path` entry to any manifest's `parameter_provenance`. `@ai:preflight` and
`@ai:validate-collection` both flag violations.

---

## Member Data Placement (normative)

Member-specific data written by a collection's setup or workflows goes under:

```
members/{member_hash}/{collection-name}/
```

It must **never** be written inside `members/{member_hash}/installed/`. That subtree belongs to the
installer: `org-setup` and `apply-updates` write it, replace it on upgrade, and archive it on
uninstall, without consulting the collection. In particular `installed/{collection}/apps/` is
replaced **wholesale** on every collection upgrade, so anything a collection stores there is lost.

This rule predates 3.29.0 — `api/author-collection.md` has stated it under "Local directory
structure" — and is promoted here to normative status because core's wholesale replacement of
`apps/` now depends on it.

---

## Collection Setup Template Requirements

`collection-setup.md` must:

- Have valid YAML frontmatter with `name`, `type: collection-setup`, `version`, `collection`, `description`, and `upgrade_compatible`
- Cover all org-level parameters that flow into member-level setup interviews as `[org-mandated]`
- Include a `Setup Completion` section
- Include an `Upgrade Behavior` section

---

## Unique names and optional namespaces

*Revised in core 3.31.0.* For collections offered through more than one subscribed catalog. Catalog subscriptions, provenance and collision handling at install time are admin material, in core's `admin-distribution.md` § "Marketplaces: catalogs, subscriptions, provenance (normative — core 3.30.0; collision rules revised in 3.31.0)".

The rule that makes multiple catalogs safe is **unique names**, not prefixes. Namespaces are an optional extra reservation on top of it.

- **Unique names.** A collection `name` may be offered by **at most one** enabled subscribed catalog. Two catalogs offering the same name is a **conflict**: that name is not installable from either until the admin resolves it (rename in one catalog, drop one entry, or disable one subscription). Only the conflicting name is affected — the rest of both catalogs stays usable. Refused at subscribe time; re-checked on every catalog read.
- **Namespaces are optional reservations.** A catalog may declare `namespace: "{ns}"`. No *other* catalog may offer a name starting with `{ns}-`; an entry that does is an **intrusion** — that entry is excluded and reported, and the reserving catalog keeps the prefix. The reserving catalog's own entries may use any names — `{ns}-*` or not.
- **Hyphen separator.** Collection names are kebab-case and are used verbatim as path segments (`/{collection}/api/…`, `members/{hash}/collections/{name}/`), so a reservation `{ns}` covers names starting `{ns}-`; no other separator is legal.
- **Reservations may not overlap:** `{a}-` must not be a prefix of `{b}-` or vice versa. Overlapping reservations are a configuration error — both catalogs are unavailable until one is changed.
- **Repo names are unconstrained.** Neither rule looks at git repository names; they appear only as an entry's `repo_url`.
- **No shadowing, by construction.** There is no precedence between catalogs, so a same-named collection in another catalog can never silently replace one: a conflict is always refused, never auto-resolved. To replace a public collection, fork and rename.

(3.30.0 required every entry of a namespaced catalog to start with `{ns}-`, and required every non-public catalog to declare a namespace. That forced a private catalog to hold a single naming family. Both requirements are removed in 3.31.0: shadowing is already prevented by the absence of precedence, and unique names prevent ambiguity. A 3.30.0-valid catalog is 3.31.0-valid unchanged.)

---

## File-integrity sentinel (`AIFS:FILE-END`)

Tail truncation — files cut mid-content by capped or interrupted writes — has corrupted both local and remote copies (bug `20260608-8d20ea22-003039-trunc`). The sentinel standard makes completeness a property of the file itself: a stamped file that does not end with its sentinel **is truncated**, deterministically, with no heuristics.

**Marker:** the logical marker is `AIFS:FILE-END`. The **last non-whitespace content** of a stamped file must be its per-format encoding:

| Format | Encoding (final line / final key) |
|---|---|
| Markdown, plain text | `<!-- AIFS:FILE-END -->` on its own line |
| JSON | top-level key `"_file_end": "AIFS:FILE-END"`, serialized last |
| Shell, Python | `# AIFS:FILE-END` |
| JavaScript | `// AIFS:FILE-END` |

Trailing whitespace/newlines after the marker are permitted. JSON consumers must tolerate (ignore) the `_file_end` key; schemas that enumerate keys must allow it.

**Stamped classes (v1):** collection source files (`collection.json`, `README.md`, `CHANGELOG.md`, `ROADMAP.md`, `api/*`, `setup/*`, `internal/*`, `apps/*` scripts); core/marketplace/developer infrastructure equivalents; task-written JSON state files (`org-config.json`, `member-index.json`, manifests, `published-state.json`, `latest.json`) — stamped opportunistically whenever a task rewrites them.

**Excluded:** JSONL/append-mode files (per-line parse validity is their integrity check), binary files, third-party files, member free-form content.

**Adoption:** a collection opts in by declaring `"file_integrity": "sentinel-v1"` in `collection.json`. Preflight then treats a missing sentinel on a stampable file as an ERROR (WARNING for non-declaring collections). New collections scaffolded by `develop` declare it from birth. Writers re-stamp on every rewrite; the adapter's write path (gdrive ≥ 2.6.0) verifies post-write that a sentinel present in written content survived, and fails loudly if it did not.

**Detection contract.** What a reader does on finding a stamped file without its sentinel — treat it as truncated, re-fetch before any heal decision, never overwrite a complete copy with a truncated one — is a runtime rule every session needs. It is authoritative in CLAUDE.md and not restated here.

---

## Collaborative Folder ACLs (`collaborative-acls.json`)

Under the least-privilege access model (adapter contract v2.0+, core 3.1.0+), a non-admin member is writer only on their own `/members/{hash}/` and `/shared/members/artifacts/{hash}/` and reader on everything else under `/shared/`. A collection whose members must **write shared collaborative state** (e.g., a shared bug log, a shared project tree) must therefore declare the ACLs it needs so they can be provisioned at install time. Collections that only read shared data, or whose members write only their own private namespace, omit this file.

**File:** optional, at the collection root: `/{collection}/collaborative-acls.json`.

**Schema:**

- `version` (string) — `"1.0"`.
- `acls[]` — each entry:
  - `path` (string) — target folder; supports `{param}` placeholders resolved at provisioning from `collection-setup-responses.md` and `org-config.json` (e.g., `{bug_log_path}`, `{all_members_group}`).
  - `recipient` (string) — email or group address (typically `{all_members_group}`).
  - `role` (string) — `reader` / `commenter` / `writer`.
  - `inherit` (boolean, optional, default `true`) — `true` = additive grant on top of parent inheritance (the normal collaborative-write case). `false` = explicit override that detaches the resource from parent inheritance (used to *restrict* a subfolder, e.g., keep a secrets dir out of a broad `all@ reader`); requires the applier to hold organizer/owner and the helper binary `permission-helper-go ≥ 0.3.0`.
  - `restrict` (boolean, optional) — documents that an `inherit:false` entry exists to remove inherited access rather than add it.
  - `rationale` (string, optional) — human-readable why.

**Provisioning contract:** `install-collection` Step 5.5 reads this file, resolves placeholders, filters already-satisfied entries (idempotent), and routes the remaining grants through the `permission-change-helper` skill for admin review + Accept. Collections and the installer **never** call `aifs_share`/`aifs_unshare`/`aifs_transfer_ownership` directly (see core's `runtime-reference.md` § "Permission-Modifying Operations"). The grant is applied under the admin's OAuth identity; members never grant themselves access. Member-facing task workflows must assume the grant is already in place and must not perform permission changes themselves; on an authorization failure they should direct the member to ask an admin to (re-)run `@ai:install-collection {name}`.

---

## Versioning Requirements

- All collections must use semantic versioning: `MAJOR.MINOR.PATCH`
- MAJOR version bumps are required for: breaking changes to setup interfaces, breaking changes to parameter schemas, breaking changes to API member interfaces, removal of API members
- MINOR version bumps are required for: new API members, new optional parameters, non-breaking additions
- PATCH version bumps are used for: bug fixes, clarifications, non-behavioral changes
- API members must maintain a stable interface across MINOR versions
- Upgrade scripts are required in `/upgrade/` for every MAJOR version boundary after v1.0.0

---

## EOL Policy Requirements

- When a new MAJOR version is published, an `eol_date` must be set on the prior MAJOR version
- Minimum EOL window: 90 days from the new MAJOR version publish date
- `eol_date` must be set in `collection.json` of the version being deprecated

---

## CHANGELOG Requirements

`CHANGELOG.md` must:

- Document every version in reverse chronological order (newest first)
- Use the format: `## [MAJOR.MINOR.PATCH] — YYYY-MM-DD`
- List changes under `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` headings as applicable
- For MAJOR versions: include a migration summary and link to the upgrade script

---

## Spec Document Currency

**Applies to** root-level specification and guide documents in a collection — for example `README.md`, `ROADMAP.md`, `*-spec.md`, `*-guide.md`, this document, and any document a collection's own `collection.json` names in a `documents` list. **Excluded:** everything under `api/`, `setup/`, `internal/` and `upgrade/`. Those carry YAML frontmatter, and their currency is governed by the frontmatter-to-manifest contract, not by a markdown header.

**The currency field is a date.** A currency header declares `Last Updated: YYYY-MM-DD`; `Last updated:` is an accepted alias, and bold and unbold forms are equivalent. Documents do not declare a document-level `Version` — that field is retired (Core Improvements decision `2026-09-21-retire-doc-level-version-field`), and the collection's release version is the document's version. A ROADMAP's `Current version:` names the collection's version, not the document's, and is checked separately. **The declared basis of currency is the header — not file mtime and not git history**, neither of which survives publication to a storage backend.

**Maintenance.** Any content edit to a document that declares `Last Updated` must update it in the same change, to the date of the release that ships the edit.

**Inline qualification.** A document that describes behavior the collection does not implement must say so **at the point of the claim**, not only in a status header. A reader who lands mid-document via a section link never sees the header.

**Archive banners.** A document that is no longer maintained must carry an archive banner at its top naming the live authority. An archived document must not assert primacy over a maintained one.

Preflight checks this set: see the developer collection's `preflight` task, Check 16. The check is advisory by design — a hard release gate on document headers gets routed around.

This section moved here from core's `standards.md` when that document was retired (Core Improvements decision `2026-09-22-retire-standards-md`).

---

## README Requirements

`README.md` must include:

- A plain-language description of what the collection does
- A list of included skills and tasks with one-line descriptions
- Any prerequisites (external systems, other collections)
- The lifecycle or workflow the collection supports, if applicable
- A version history reference pointing to CHANGELOG.md

---

## Category Registry

Collections must declare one of the following categories. New categories may be proposed via the agent-index GitHub repository.

| Category | Description |
|---|---|
| `infrastructure` | Core system components (reserved for agent-index-core and agent-index-marketplace) |
| `project-management` | Project tracking, planning, and coordination |
| `hris` | Human resources information systems |
| `ats` | Applicant tracking and recruiting |
| `crm` | Customer relationship management |
| `finance` | Finance, accounting, and expense management |
| `communication` | Email, messaging, and notification workflows |
| `document-management` | Document creation, storage, and lifecycle |
| `reporting` | Analytics, dashboards, and reporting workflows |
| `developer-tools` | Engineering and development workflows |
| `sales` | Sales process and pipeline management |
| `marketing` | Marketing workflows and content management |
| `customer-success` | Customer support and success workflows |
| `productivity` | General productivity and personal workflow tools |
| `strategy` | Strategy development, competitive intelligence, and opportunity tracking |
| `personal-productivity` | Personal capture, task management, and individual workflow tools |

---

## Naming Conventions

- Collection names: kebab-case, lowercase, no special characters except hyphens
- Collection names must not start with `agent-index-` (reserved for official agent-index collections)
- Collection names must be globally unique within the marketplace
- Collection directory name must match the `name` field in `collection.json`. For marketplace collections distributed via Git, the repository name may use a prefix (e.g., `agent-index-marketplace-{name}`), but the collection directory on the remote filesystem and the `name` field must match.
- Skill and task names within a collection: kebab-case, globally unique within the collection

---

## Member Resolution in Collection Workflows

Any collection whose skills or tasks reference people — project owners, team members, assignees, reviewers, approvers, or similar — must resolve those references against the members registry rather than storing bare name strings. This ensures that people referenced in shared data are linked to their actual org identities when possible.

### Required Behavior

When a workflow collects a person reference (e.g., "Who is the project owner?" or "Add Sarah as a reviewer"):

1. **Search the registry.** Read the members registry by ID anchor, `aifs_read("id:{resource_ids.members_registry}")`, with the id from `org-config.json` — never by the bare `/members-registry.json` path, which does not resolve for a non-Drive member — and search by `display_name` using case-insensitive partial matching (e.g., "Bill" matches "Bill Smith").

2. **Single match → confirm.** If exactly one member matches, confirm with the user: "That's {display_name} ({email}), correct?" On confirmation, record the person as a **registered member** with their `member_hash`, `display_name`, and `email`.

3. **Multiple matches → disambiguate.** If more than one member matches, present all matches and ask the user to select the correct person.

4. **No match → record as unregistered.** If no member matches, record the person using the provided name with `member_hash: null` and `email: null`. Inform the user: "{name} isn't in the org's member registry yet. I'll add them by name for now — once they're set up in agent-index, you can link their full identity later."

5. **Self-references.** If the user says "me", "I am", or similar, use the running member's identity (already resolved at session start from their `member_hash`).

### Schema for Person Fields

Wherever a person is stored in a collection's data files (`project.md`, task records, etc.), use a structured object rather than a bare string:

```yaml
owner:
  display_name: "Bill Smith"
  member_hash: "8d20ea22b9df1b13"    # or null if unregistered
  email: "bill@example.com"           # or null if unregistered
```

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

This format allows downstream tasks and reports to distinguish registered members (who can be looked up, notified, or referenced in other workflows) from placeholder names that need to be linked once the person joins the org.

### Linking Unregistered Members

Collections that support editing (like `edit-project`) should provide a way to retroactively link an unregistered member to their registry entry once they've joined the org. This is done by searching the registry by display name, confirming the match, and updating the record with their `member_hash` and `email`.

---

## Shared Artifacts: Frontmatter Declarations

What a task that touches shared data must declare in its frontmatter. The write and read paths themselves are runtime material, in core's `runtime-reference.md` § "Shared Artifacts and Data".

### The `produces_shared_artifacts` Flag

Set `produces_shared_artifacts: true` in a task's frontmatter if the task writes files to the remote `/shared/` namespace. This flag signals to the system (and to collection reviewers) that the task has write access requirements beyond the member's local workspace.

### The `reads_from` and `writes_to` Fields

Frontmatter fields `reads_from` and `writes_to` declare which shared paths a task accesses. Set them to `null` if the task doesn't read from or write to shared paths.

```yaml
reads_from: "/shared/projects/"
writes_to: "/shared/projects/"
```

These fields serve as documentation and as input for future access-control or audit systems. They do not currently enforce permissions, but collections should declare them accurately.

---

## Capability Provider Requirements

Collections may declare that they provide or require abstract capability types. This enables loose coupling between collections: a consumer collection codes against a capability interface, and the org chooses which provider collection fulfills it.

### Capability Type Registry

Well-known capability types are maintained in `agent-index-core/capability-types/`. Each type is a JSON file defining a set of operations with parameters and return values. New types may be proposed via the agent-index GitHub repository, following the same process as category additions.

Collections may also define custom capability types in a `/capability-types/` directory within the collection. Custom types are namespaced as `{collection-name}:{capability-name}` to avoid collisions with well-known types.

### Provider Declarations (`provides`)

Collections that implement a capability type declare this in the `provides` array of `collection.json`. Each entry must include:

| Field | Type | Description |
|---|---|---|
| `capability` | string | The capability type being provided. Must reference a well-known type or a custom type (namespaced). |
| `capability_version` | string | The version of the capability contract this provider implements. |
| `operations` | object | Map of operation names to implementation references. Each entry must have `implemented_by` (name of an API member) and `type` (`"skill"` or `"task"`). |

Every `implemented_by` value must reference a name listed in the collection's `api` array. The implementing skill or task must accept at minimum the parameters defined in the capability type's operation spec.

All operations marked `required: true` in the capability type definition must be present in the provider's `operations` map. Optional operations may be omitted.

### Consumer Declarations (`requires`)

Collections that need a capability type declare this in the `requires` array of `collection.json`. Each entry must include:

| Field | Type | Description |
|---|---|---|
| `capability` | string | The capability type being required. |
| `capability_version` | string | SemVer range (e.g., `">=1.0.0"`, `"^1.0.0"`). |
| `required_operations` | array | Operations the consumer must be able to call. At least one provider must implement all of these. |
| `optional_operations` | array | Operations the consumer will use if available. |
| `required` | boolean | If `true`, the collection cannot function without this capability. If `false`, reduced mode is acceptable. |
| `fallback` | string | Behavior when no provider is registered: `"skip_with_notice"`, `"prompt_manual"`, or `"error"`. |

### Capability Bindings

> **Implementation status (core 3.28.2 — V1 partial; re-verified at 3.31.0).** Only **single-provider auto-bind** is implemented: when exactly one provider is registered for a capability type in `org-config.json` → `capability_providers`, a consumer binds to it directly. **The multi-provider binding model described in this section — `capability-bindings.json`, bindings chosen in the setup interview, per-binding resolution — is specified but not implemented.** No shipped setup template declares bindings, and nothing writes `capability-bindings.json`. Do not author against this section; author against the single-provider path and the `requires` → `fallback` behavior in § Consumer Declarations. The same note appears in `capability-provider-spec.md` § Capability Bindings.

Consumer collections define named capability bindings — specific use cases that map to registered providers. Bindings are stored in a dedicated `capability-bindings.json` file in the member's local workspace:

**Path:** `members/{member_hash}/collections/{collection_name}/capability-bindings.json`

| Field | Type | Description |
|---|---|---|
| `version` | string | Schema version for the bindings file format. |
| `collection` | string | The consumer collection these bindings belong to. |
| `last_updated` | string | ISO date when bindings were last modified. |
| `bindings` | object | Map of binding names to binding configurations. |

Each binding entry:

| Field | Type | Description |
|---|---|---|
| `capability` | string | The capability type this binding draws from. |
| `provider_collection` | string | The registered provider collection bound to this use case. |
| `operation_subset` | array | Which operations this binding uses. |
| `provenance` | string | The provenance tier that governed this binding's configuration. |

Bindings are configured during the consumer collection's setup interview. When only one provider is registered for a capability type, bindings are auto-assigned without prompting. When multiple providers are registered, the setup interview presents binding choices using standard provenance tiers.

### Provider Registry in `org-config.json`

Registered providers are stored in `org-config.json` under `capability_providers`. Each capability type maps to an array of provider entries:

| Field | Type | Description |
|---|---|---|
| `provider_collection` | string | Name of the installed collection providing this capability. |
| `capability_version` | string | The capability type version the provider implements. |
| `registered_date` | string | ISO date when the provider was registered. |
| `registered_by` | string | `member_hash` of the admin who registered the provider. |
| `operations_available` | array | List of operations the provider implements. |
| `provider_config` | object | Provider-specific configuration set during registration. |

### Capability Type Versioning

Capability types follow semantic versioning. MAJOR bumps for removing required operations or breaking parameter signatures. MINOR bumps for adding operations or optional parameters. PATCH bumps for documentation changes only.

For the full capability provider specification including runtime resolution, install-time validation, and migration guidance, see `capability-provider-spec.md`.

---

## Release Gate

**The gate that runs is `lib/preflight-cli.sh`.** `lib/release/release-prep.sh` (and `.ps1`) runs it once per repo, after restamping manifests, as a hard gate: any error aborts that repo's prep. Nothing in the release scripts runs `@ai:preflight`; it is an agent task, and a script cannot invoke it.

**`preflight-cli.sh` is not equivalent to `@ai:preflight`, and neither contains the other.** (Compared at developer 1.13.0.)

- **Only `@ai:preflight` checks:** file completeness, including a `-setup.md` for every API member and orphaned files (Step 2); frontmatter validation by type (Step 3); cross-reference integrity (Step 5); setup template quality — provenance annotations and required sections (Step 6); most content-quality checks — README completeness and freshness, CLAUDE.md alias coverage, CHANGELOG format, naming, workflow and directive quality, storage-access clarity, tutorial skill, authoring-note remnants (Step 7); access-model consistency (Step 7.5); token efficiency (Step 8, notes only); and marketplace-specific checks (Step 9).
- **Only `preflight-cli.sh` checks:** JSON brace balance (Check 5), the JS-integrity heuristic (Check 7), the `node --check` half of the adapter build check (Check 14), and trailing newlines (Check 15).
- **Both check:** version consistency (CLI Checks 1–3, 9, 12, 13; task Step 4), shell-script LF line endings (Check 4), `directory_version` movement (Check 10), `inherit:false` against the adapter contract (Check 8), the file-integrity sentinel (Check 11), and spec-document currency headers (Check 16).

**What this means in practice.** A clean `preflight-cli.sh` run does not show that a collection would also pass `@ai:preflight`. The CLI cannot see a missing setup file, incomplete frontmatter, or a setup template without its required sections. Bug `20260902-68dff8bf-145236-c1ae`: core v3.28.2 shipped with seven such errors while the CLI gate reported zero.

---

## Submission Process

To submit a collection to the marketplace:

1. Ensure the collection meets every requirement in this document, conforms to the file format standards it names (§ "Skill and Task File Requirements"), and passes the release gate (§ "Release Gate")
2. Host the collection in a publicly accessible Git repository
3. Open an issue in the agent-index resource listings repository at `https://github.com/agent-index/agent-index-resource-listings` with the collection name, repository URL, and a brief description
4. The agent-index team will review for standards compliance and add the collection to `directory.json` upon approval

---

*These requirements are versioned with the developer collection, which ships this document. Breaking changes to them require a MAJOR version bump of the developer collection and a migration path for existing collections.*
