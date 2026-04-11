# Developer Collection — Roadmap

Current version: 1.1.0
Last updated: 2026-04-06

---

## Current State

v1.1.0 adds token efficiency optimization to the development workflow. The collection now provides five API members: an interactive development skill (with script-first design built into scaffolding), a preflight task (with efficiency checks), an optimize task (for auditing existing collections), a reference guide, and a tutorial.

The optimize task classifies workflow steps as judgment or mechanical, estimates token costs, and can generate parameterized scripts to replace mechanical steps. The develop skill applies this thinking from the beginning — when scaffolding new collections, mechanical steps are identified and written as script calls rather than inline Claude instructions. Preflight surfaces optimization opportunities as notes during release-readiness checks.

The collection is designed to work for both non-technical users who describe what they want in plain language and experienced engineers who want fast scaffolding. All five API members are fully functional at v1.1.0.

### Known Limitations

- **Preflight does not validate capability bindings against a live org.** It can check that provider/consumer declarations reference valid types and API members, but cannot verify that a provider is actually registered in the org. Full binding validation requires org context that isn't available at development time.

- **The develop skill does not diff against prior versions.** When preparing a version bump, Claude asks the developer what changed. It does not automatically compare the current collection state against the last changelog entry to detect undocumented changes. A future version could add automatic change detection.

- **No collection testing framework.** Preflight checks structural compliance and release readiness, but does not simulate running a collection's skills or tasks. A future version could add dry-run testing that walks through task workflows with mock data to catch logic issues before deployment.

- **Evolve Collection flow does not track what files were modified.** After evolving a collection, the developer must remember what changed for the version bump. A future version could maintain a change log within the session to feed into the version bump workflow.

### Known Bugs

None currently tracked.

---

## Wishlist

### v1.1 — Quality of Life

- **Automatic change detection for version bumps.** When the develop skill enters the Version Bump flow, read the last changelog entry and diff the current file contents against what was documented. Surface any undocumented changes so the developer doesn't have to remember everything.
- **Preflight fix-it mode.** Instead of just reporting issues, offer a mode where preflight automatically fixes simple issues (missing frontmatter fields with obvious defaults, manifest-frontmatter sync, changelog formatting) and presents the fixes for approval.
- **Collection templates.** Offer starting templates for common collection patterns: "simple skill collection" (one skill, one config), "workflow collection" (task with supporting skills), "integration collection" (external system bridge with OAuth setup).

### v1.2 — Deeper Integration

- **Dry-run testing.** Walk through a task's workflow steps with mock member input and simulated data to catch logic issues, missing state file references, and broken step transitions before deployment.
- **Marketplace submission assistant.** Guide the developer through the submission process: verify all marketplace checks pass, prepare the Git repository, draft the submission issue for the resource listings repo.
- **Cross-collection dependency validation.** When a collection declares dependencies on other collections, read those collections (if available locally) and verify that referenced skills, tasks, and capability types actually exist.

### v2.0 — Structural Changes (breaking)

- **Plugin-aware development.** If agent-index adds a plugin system (bundling collections with MCP server configurations), extend the develop skill to scaffold plugin manifests and the preflight task to validate plugin structure.

---

## Design Notes

- **Preflight is separate from validate-collection by design.** validate-collection in agent-index-core checks structural compliance (are the files correct?). Preflight checks release readiness (is this actually ready to ship?). The distinction matters because collections can be structurally valid but not release-ready. Keeping them separate means core doesn't need to know about release workflows, and preflight can evolve faster than core.

- **The develop skill delegates to author-collection for initial scaffolding** but adds lifecycle management (evolving, version bumping) and audience adaptation (non-technical users) that author-collection doesn't handle. Over time, author-collection may be deprecated in favor of the develop skill, but for now both exist — core's author-collection for orgs that don't install the developer collection, and develop for those who do.

- **The guide skill is always-on eligible.** This means a developer can designate it as an always-on skill in their preferences, making agent-index development reference available in every session without explicit invocation. This is intentional — developers frequently need to look things up while doing other work.
