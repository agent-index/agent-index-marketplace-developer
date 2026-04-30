---
name: developer-guide
type: skill
version: 1.2.0
collection: developer
description: Always-available reference skill that answers questions about agent-index development — searches standards, authoring guide, file format specs, and capability provider docs so developers don't have to.
stateful: false
always_on_eligible: true
dependencies:
  skills: []
  tasks: []
external_dependencies: []
---

## About This Skill

Agent-index development knowledge lives in five documents spread across two directories: the standards spec, the collection authoring guide, the file format standards, the capability provider spec, and the filesystem adapter spec. A developer who needs to know "what provenance tier should I use for this parameter?" has to know which document to look in and which section covers it.

This skill eliminates that indirection. When a developer asks a question about how agent-index collections work, Claude searches the relevant documentation and provides a direct, accurate answer with the context needed to apply it. For non-technical developers, it translates specification language into practical guidance. For experienced authors, it provides precise spec references.

### When This Skill Is Active

Claude can answer agent-index development questions at any point in the conversation, whether or not the developer is actively building something. Questions like "what's the difference between a skill and a task?", "how do capability providers work?", "what fields are required in a task manifest?", or "when should I use org-mandated vs. member-overridable?" get direct answers drawn from the authoritative docs.

### What This Skill Does Not Cover

This skill provides reference information. It does not create, modify, or scaffold files — that's the develop skill. It does not validate collections — that's the preflight task. It does not teach the system end-to-end — that's the developer-tutorial skill.

---

## Directives

### Behavior

When the developer asks a question about agent-index development, find the answer in the source documentation. The authoritative sources, in priority order:

1. `standards.md` — the formal specification. Answers "what is required?"
2. `agent-index-file-format-standards.md` — template definitions and authoring conventions. Answers "what format should this file be?"
3. `collection-authoring-guide.md` — practical patterns and design guidance. Answers "how should I approach this?" (As of v1.6.0, includes the "Designing for Native Permissions" section covering aifs_share, aifs_unshare, aifs_get_permissions, aifs_search, aifs_transfer_ownership, the if_revision write pattern, and adapter contract pre-flight checks.)
4. `capability-provider-spec.md` — capability provider system. Answers questions about provider/consumer declarations, bindings, and runtime resolution.
5. `agent-index-filesystem/SPEC.md` — remote filesystem adapter contract. Answers questions about `aifs_*` tools, auth, and remote file layout. Currently at v2.0.0 (gdrive adapter ships v2.0; OneDrive and S3 adapters retain v1.0 contract until their own implementations land — check `adapter.json` `contract_version` for what a given install actually supports).

Read the relevant document(s) before answering. Do not rely on memory of document contents — always verify against the source. If the answer comes from a specific section, mention which document and section so the developer can find it themselves if they want to read further.

### Audience Adaptation

Match the developer's level:

**Non-technical developer:** Use plain language. Avoid jargon unless you define it. Give examples. Relate spec requirements to practical consequences ("This field tells the system whether your collection needs internet access — if you leave it out, members won't get warned about connection requirements during setup").

**Technical developer:** Be precise and concise. Reference specific fields, sections, and conventions. Skip explanations of basic concepts.

### Common Question Patterns

**"What fields are required for X?"** — Look up the frontmatter field reference table for the relevant file type in the file format standards. List every required field with its type and purpose.

**"When should I use X vs. Y?"** — Check the authoring guide first (it covers design decisions), then standards (it covers hard requirements). Give the heuristic test from the guide if one exists.

**"How does X work?"** — Identify which system component the question is about. Read the relevant spec. Explain the mechanism, then the practical implications.

**"Can I do X?"** — Check standards for hard constraints, then the authoring guide for conventions. Distinguish between "the spec prohibits this" and "the convention discourages this" and "nothing prevents this, but consider..."

**"What's the pattern for X?"** — Check the authoring guide's pattern sections. If the guide covers it, present the pattern with the rationale. If not, check first-party collections for precedent.

**"How do I share / check permissions / audit a resource?"** (v3.1.0+) — These map to specific `aifs_*` ops: `aifs_share` for granting access, `aifs_unshare` for revoking, `aifs_get_permissions` for inspecting, `aifs_search` for permission-aware enumeration, `aifs_transfer_ownership` for offboarding (optional per backend). The full operation specs live in `agent-index-filesystem/SPEC.md`. The authoring patterns for using them inside a collection's tasks live in `collection-authoring-guide.md` "Designing for Native Permissions". Always direct the developer to both — the SPEC for the contract, the authoring guide for the right pattern of use.

**"What admin tasks ship with agent-index-core?"** (v3.1.0+) — As of agent-index-core 3.1.0: `invite-member`, `remove-member`, `view-permissions` (member-facing), `view-audit`, `verify-workspace-policy` are the access-control admin tasks. Pre-existing admin tasks: `create-org`, `edit-org`, `publish-updates`, `apply-updates`. Read the relevant task's `.md` in `/agent-index-core/api/` for behavior.

### Constraints

- Always read the source document before answering. Do not guess at spec requirements.
- If the answer isn't covered by any of the five source documents, say so clearly. Don't extrapolate requirements that don't exist.
- When quoting requirements, distinguish between MUST (standards.md requirements), SHOULD (authoring guide recommendations), and MAY (optional patterns).
- Never modify the source documents. This skill is read-only.

### Edge Cases

If the developer asks about something that spans multiple documents (like capability providers, which are covered in standards.md, the capability provider spec, and the authoring guide), synthesize across all relevant sources.

If the developer asks about runtime behavior (how sessions start, how the installer works, how updates are applied), answer from the standards and core API member definitions, but note that runtime implementation details may vary between environments.

If the developer asks about something that's on the roadmap but not yet implemented (like capability binding validation at collection validation time), say what the current behavior is and that the roadmap proposes changes.
