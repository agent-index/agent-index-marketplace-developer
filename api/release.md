---
name: release
type: task
version: 1.1.0
collection: developer
description: Generates a matched pair of host-native release scripts — an idempotent build-and-prep script (adapter unit tests with module-resolution exit-classification, native bundle build + checksum stamp, manifest + resource-listings restamp, fail-closed version-consistency gate) and a gated push script (changelog date stamp, mandatory preflight, per-repo commit→push→tag v<version> in code-first/listings-last order, backend-distribution handoff). The ship-side counterpart to core's clone-script-generator.
stateful: false
produces_artifacts: true
produces_shared_artifacts: false
dependencies:
  skills: []
  tasks:
    - preflight
external_dependencies: []
reads_from: null
writes_to: null
---

## About This Task

`develop` builds a collection and `preflight` says whether it's ready to ship. `release` codifies the **last mile** — getting a reviewed, version-bumped release onto GitHub correctly and tagged so the rest of the system (the `clone-script-generator`, `/shared/dist/manifest.json`) can pin to it. Before this task, that knowledge lived only in hand-copied `push-*.sh` scripts: the push ordering, the version gate, the mandatory preflight call, the tag convention. This task makes it the generated, repeatable way to ship.

Like `clone-script-generator`, this task **does not push anything itself** — `git push` needs the real repos, host credentials, and a clean working tree (agent-side git over a synced/mounted filesystem is unsafe; it has produced torn commits). Instead, `release` interviews the developer, runs preflight as a hard gate, and emits a **host-native script** (PowerShell on Windows, bash on macOS/Linux) the developer runs natively. The script encodes every release invariant so none of them depend on memory.

### Why a generator, not an action

The agent can't safely `git push` (mount-tearing → torn commits; no host credentials in the sandbox). The same boundary that makes `clone-script-generator` a generator applies here. The agent's job is to get the *script* exactly right — version gate, preflight, ordering, tagging — and hand it to the human who has the credentials and a clean tree.

### Inputs

Gathered in the interview (Step 1):
- **Repos in this release** and each one's target version — adapter (`agent-index-filesystem-<backend>`), `agent-index-core`, `agent-index-marketplace`, `agent-index-resource-listings`, and/or marketplace collection repos. Defaults are read from each repo's `collection.json` / `adapter.json` `version` and the listings file's `directory_version`.
- **Whether this release publishes `/shared/dist/`** (Release-C backend distribution) and the backend (`onedrive` | `gdrive`). Drives the post-push handoff text.
- **Tag convention** — default `v<version>` per repo. Confirmed, not assumed.
- **Host OS/arch** — detected, selects PowerShell vs bash.

### Outputs

Two host-native scripts written to `<install_root>/.agent-index/` — `prep-<headline-tag>.{ps1,sh}` (build & prep) and `push-<headline-tag>.{ps1,sh}` (gated push & tag) — surfaced to the developer to run natively, prep first. No repos are built, pushed, or published by this task itself. The push script prints the post-run handoff (the dist-publish sequence) when the release publishes `/shared/dist/`.

### Cadence & Triggers

On demand, once per release, AFTER the design/test/preflight stages of the development lifecycle are complete (it is lifecycle stage 8 — Release). Re-runnable: regenerate if the repo set or versions change before the push.

---

## Workflow

### Step 1: Interview — scope the release

Ask the developer (one question at a time for non-technical authors; batched for experts):

1. Which repos are in this release? Offer the standard set and let them subset it.
2. For each repo, confirm the target version. **Read the actual declared version** from the repo (`collection.json` `version`, `adapter.json` `version`, or `infrastructure-directory.json`/`marketplace-directory.json` `directory_version`) and present it as the default — do not ask the developer to retype it.
3. Does this release publish `/shared/dist/` (backend distribution)? If yes, which backend?
4. Confirm the tag convention (default `v<version>` per repo).

Detect `host_os` and `host_arch` from the running environment.

**On success:** Proceed to Step 2 with the repo+version+tag set.
**On failure (a repo's declared version can't be read):** Report which repo and stop — a release must not be generated against an unknown version.

---

### Step 2: Determine push order (dependency order)

Order the selected repos so nothing ever points at a version whose code isn't live yet:

1. The filesystem adapter (`agent-index-filesystem-<backend>`)
2. `agent-index-core`
3. `agent-index-marketplace`
4. Marketplace collection repos
5. **`agent-index-resource-listings` LAST**, always — it is the broadcast layer; if it goes out before the code/binary it references, `check-updates` and adapter-update flows point at versions that 404.

Record this order; the generated script pushes in it.

---

### Step 3: Emit the release-delta manifest (data) -- the committed scripts own the logic

**Level-3 (C.1.5.0):** the prep/push logic is no longer transcribed into bespoke `prep-<tag>`/`push-<tag>` scripts each release. It lives in committed, version-controlled tooling at `agent-index-marketplace-developer/lib/release/` (`release-prep.{ps1,sh}`, `release-push.{ps1,sh}`). This task now emits ONLY a **release-delta manifest** (pure data -- which repos/versions changed) and surfaces the committed-script invocations. The agent still never builds or pushes.

Write the manifest to `<install_root>/.agent-index/release-<headline-tag>.json` (torn-write discipline: read it back before surfacing). Shape (see `lib/release/release-manifest.schema.json`):

```json
{
  "headline_tag": "c150",
  "repos": [
    { "name": "agent-index-core", "path": "../agent-index-core", "version": "3.28.0", "is_adapter": false, "in_listings": true }
  ],
  "push_order": ["agent-index-core", "agent-index-marketplace", "agent-index-marketplace-developer", "agent-index-marketplace-library", "agent-index-resource-listings"],
  "dist_publish": true
}
```

Only repos changed in the release go in `repos`/`push_order`; flag adapters with `is_adapter:true` (so the build+checksum step runs only for them -- no adapter steps when adapters are untouched); `push_order` MUST end with `agent-index-resource-listings`.

**The committed scripts encode every invariant the old generated pair did:**
- `release-prep` -- preflight **hard gate** per repo (G3), adapter unit-test advisory-skip + **native bundle build + checksum + `node --check`** for `is_adapter` repos (P1/P2), `api/*-manifest.json` `collection_version` restamp (P3), and (via preflight Checks 10/13/14) the resource-listings stamp + cross-repo version-consistency gate + adapter build integrity (P4/P5). NO git writes; re-runnable.
- `release-push` -- the **pre-push diff + integrity gate** (shows each repo's `git diff --stat`/full diff for review, and flags a lost `AIFS:FILE-END` sentinel vs HEAD, a missing trailing newline, or a non-HTTPS `origin` -- the guard that would have caught the create-org torn-write), CHANGELOG `<RELEASE_DATE>` stamp at push (G2), per-repo confirm-commit/push/**tag `v<version>`** in `push_order` with resource-listings LAST and never moving a published tag (G4), and the `/shared/dist` handoff note (G5).

Preflight is the single source of truth for structural gates; `release-prep` calls it rather than re-implementing them inline.

### Step 4: Deliver

Surface the committed-script invocations to the developer (**run prep first, then push**), naming the manifest path, the push order, and which repos tag at which `v<version>`:

```
# Windows
powershell -ExecutionPolicy Bypass -File lib\release\release-prep.ps1 -Manifest .agent-index\release-<headline-tag>.json
powershell -ExecutionPolicy Bypass -File lib\release\release-push.ps1 -Manifest .agent-index\release-<headline-tag>.json
# macOS/Linux
bash lib/release/release-prep.sh .agent-index/release-<headline-tag>.json
bash lib/release/release-push.sh .agent-index/release-<headline-tag>.json
```

Remind them the scripts run **natively** -- the agent neither builds nor pushes (esbuild needs the host binary; agent-side git over a synced mount tears commits).

Confirm the release-checklist (the developer collection's release-checklist reference) is satisfied before they run them.

**On success:** Task complete.

---

## Directives

### Behavior

Operate as the ship-side partner. Never generate a release script without first reading each repo's actual declared version (Step 1) — the version gate is only as good as the truth it's seeded with. Always put `agent-index-resource-listings` last. Always make preflight a hard gate on errors. Always tag, and never instruct moving a published tag. Adapt verbosity to the developer's experience level, but never skip a gate to move faster.

### Output Standards

The deliverable is a matched pair of self-contained host-native scripts (prep + push). They must be runnable as-is, print per-step status, use confirm prompts for commit/push/tag, and exit non-zero on any abort. Prep is idempotent and git-free; push is the only phase that commits/pushes/tags. PowerShell for windows; bash for darwin/linux. No agent-side build or push.

### Constraints

- This task generates scripts; it never builds, pushes, tags, or publishes anything itself.
- Always generate BOTH scripts (prep + push); the build/checksum/manifest/listings stamping belongs in prep, the commit/push/tag in push. Never fold the version-consistency + manifest-alignment gate into push-only — it must fail at the earliest (prep) phase.
- Never pin a tag to a branch (`main`) — tags are `v<version>` only.
- Never force-move or delete a published tag in the generated script.
- Never place `agent-index-resource-listings` anywhere but last in the push order.
- Never weaken the preflight gate from error-blocking to advisory.
- Compute adapter bundle checksums on git-blob LF bytes, never the working-tree copy.

### Edge Cases

If a repo has no `origin` remote, the generated script prints the `git remote add` command and skips that repo (does not invent a remote).

If the developer wants to ship a collection that isn't represented in any resource-listings directory, note it (org-internal collections need not broadcast) but still generate the push+tag for the collection repo.

If the release includes only `agent-index-resource-listings` (a listings-only correction), the version gate checks `directory_version` and the script still tags it `v<directory_version>`.

If `preflight` (the dependency task) isn't installed, fall back to invoking `lib/preflight-cli.sh` directly and note that the full agent-side preflight is the canonical comprehensive check.

<!-- AIFS:FILE-END -->
