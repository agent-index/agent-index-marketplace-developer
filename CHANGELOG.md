# Developer Collection — Changelog

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
