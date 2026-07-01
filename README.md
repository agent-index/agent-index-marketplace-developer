# Developer Collection

Unified development experience for building, evolving, and shipping agent-index collections. Designed for both non-technical users directing Claude and experienced engineers working directly with the system.

## What This Collection Does

The Developer collection gives you everything you need to create agent-index collections without having to read the standards spec, file format documentation, or authoring guide yourself. Claude reads those documents and applies them on your behalf.

You describe what you want your collection to do — in plain language or with technical precision — and Claude handles the file structure, frontmatter schemas, setup interviews, manifests, cross-references, and naming conventions. When you're ready to ship, the preflight check catches the loose ends that slip through during development: version bumps you forgot, changelog entries that don't match, setup templates missing provenance annotations, manifests that disagree with frontmatter.

## Included Skills and Tasks

**develop** (skill) — Interactive development partner. Creates new collections from scratch, adds capabilities to existing ones, handles version bumps, and generates all required files with correct standards compliance. Adapts to the developer's experience level — patient concept-by-concept guidance for beginners, fast scaffolding for experts.

**preflight** (task) — Release-readiness checker. Goes beyond structural validation to catch version inconsistencies, stale cross-references, incomplete setup templates, missing changelog entries, and all the small details that make the difference between a collection that works and one that installs cleanly. Reports errors, warnings, and notes with specific fix instructions.

**developer-guide** (skill) — Always-available reference. Answers questions about agent-index development by searching the standards, authoring guide, file format specs, and capability provider docs. Eliminates the need to know which document to look in.

**developer-tutorial** (skill) — Guided tour of collection development. Explains every concept from scratch for first-time authors. Covers collections, skills vs. tasks, file structure, setup interviews, versioning, preflight, and the full development lifecycle. Two modes: sequential walkthrough or jump to any topic.

**release** (task) — Ship-side release-script generator. The counterpart to core's clone-script-generator: it interviews the release scope and emits a matched pair of host-native scripts (PowerShell/bash) — an idempotent **build-and-prep** script (adapter tests, native bundle build + checksum stamp, manifest + resource-listings restamp, fail-closed version-consistency gate) and a gated **push** script (changelog date stamp, mandatory preflight, per-repo commit/push/tag at `v<version>` in dependency order — code first, resource-listings last, never moving a published tag — plus the `/shared/dist/` publish handoff). The agent never builds or pushes — the scripts run natively where the credentials and a clean tree are.

**optimize** (task) — Workflow token efficiency auditor. Reads a collection's task workflows, classifies each step as judgment (requires Claude's reasoning) or mechanical (deterministic, same logic every run), and estimates the token cost of mechanical steps. Produces an optimization report ranking extraction opportunities by savings. In apply mode, generates parameterized scripts and rewrites workflow steps to call them — so Claude spends tokens on reasoning, not re-deriving deterministic logic.

## Prerequisites

- agent-index-core v3.0.0 or later
- No external systems required

## Development Lifecycle

The collection supports the full development workflow:

1. **Learn** — Use the tutorial to understand how collections work
2. **Reference** — Use the guide to look up specific details as you work
3. **Build** — Use the develop skill to create or evolve a collection
4. **Check** — Use preflight to verify release readiness
5. **Ship** — Bump version and changelog, then use the release task to generate the preflight-gated push+tag script; run it natively, then publish `/shared/dist/` (backend distribution). The release-checklist reference enumerates the ordered gates.

## Version History

See [CHANGELOG.md](CHANGELOG.md) for version details.
