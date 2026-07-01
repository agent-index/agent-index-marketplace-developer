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

### Step 3: Generate the scripts (build-and-prep, then push)

Emit **two** self-contained host-native scripts (`.ps1` for windows, `.sh` for darwin/linux), matching the mature two-phase process: an idempotent, re-runnable **build-and-prep** script that makes the tree release-ready, then a gated **push** script that commits/pushes/tags. Splitting them keeps everything reversible until the push — prep can be run repeatedly with zero consequence; only the push is irreversible. Neither script is run by the agent; the developer runs them natively.

#### Script 1 — `prep-<headline-tag>.{ps1,sh}` (build & prep; makes NO git commits/pushes/tags and touches no `/shared/`; safe to re-run)

**P1. Adapter unit tests (adapter repos).** Run `npm test` in each adapter repo. **Classify the exit:** if the output matches a module-resolution signature (`ERR_MODULE_NOT_FOUND` / `Cannot find package '@agent-index/filesystem'`), treat it as an **advisory skip** — the framework `file:` dep isn't linked on the host, the bundle checksum gate (P2) is the real verification — NOT a failure. Only a non-resolution non-zero exit (real assertion failures) aborts. (Crying-wolf hazard: a hard-fail here trains operators to blow past a real failure.)

**P2. Native bundle build (adapter repos).** Run `npm run build` — esbuild needs the host's native binary; the sandbox cannot bundle. This regenerates `dist/aifs-exec.bundle.js`, copies `dist/aifs-exec.sh`, and writes `exec_bundle_checksum` + `bundle_built_at` into `adapter.json`. Then assert the freshly-written checksum equals sha256 over the rebuilt bundle bytes, and `node --check` the bundle.

**P3. Manifest restamp (collection repos, idempotent).** Set every `api/*-manifest.json` `collection_version` to that repo's `collection.json` `version` — ALL manifests, not just touched ones (preflight Check 2; core 3.22.5 shipped 20 manifests a version behind precisely because a hand-rolled prep skipped this).

**P4. Resource-listings stamp (idempotent).** For each entry this release changes, set `current_version` (and `contract_version` for adapters) in the matching directory file (`infrastructure-directory.json` / `filesystem-adapter-directory.json` / `marketplace-directory.json`), bump that file's top-level **`directory_version`**, and move `last_updated`. The `directory_version` bump is mandatory — staleness checks compare it; moving `last_updated` alone hides the release.

**P5. Version-consistency gate (fail-closed).** Assert every version-bearing file agrees: each repo's `collection.json`/`adapter.json` `version` (or listings `directory_version`) equals its target, AND every `api/*-manifest.json` `collection_version` equals its `collection.json` `version`, AND each changed listings entry's `current_version` equals the code repo's version. Any mismatch prints repo + expected/actual and exits non-zero. **A gate that checks only `collection.json` is not a version gate** — that hole shipped core 3.22.5's manifests a version behind.

#### Script 2 — `push-<headline-tag>.{ps1,sh}` (gated push & tag; the only irreversible phase)

**G1. Re-assert the prep gates (cheap backstop).** Re-run P5's version-consistency gate and the adapter bundle checksum match. If prep wasn't run (checksum mismatch / manifests unaligned), abort and tell the operator to run prep first.

**G2. Stamp changelog release dates.** Surgically replace the `<RELEASE_DATE>` placeholder with today's date on ONLY the specific version headers being shipped (leave unrelated placeholders — e.g. an older entry's — alone). This lands the date in the release commit instead of depending on memory.

**G3. Mandatory preflight (hard gate).** For each collection repo, run `lib/preflight-cli.sh --collection <repo>` (the developer collection's CLI). **Abort on any ERROR** — the `release-script-runs-preflight` contract. Offer `confirm "Continue anyway?"` for WARNINGS only, never errors.

**G4. Per-repo push, in the Step-2 dependency order** (adapter → core → marketplace → collection repos → **`agent-index-resource-listings` LAST**). A `push_one` routine per repo:
1. Verifies the dir is a git repo with an `origin` remote (print the `git remote add` command and skip if not).
2. Shows `git status --short` + staged diff; **confirms before commit**; commits with the supplied message.
3. Compares local HEAD to `@{u}`; **confirms before push**; pushes the current branch.
4. **Tagging:** if tag `v<version>` already exists at HEAD → leave it. If it exists pointing elsewhere → print a loud warning and do NOT move it (operator cuts a new tag by hand; never force-move a published tag the clone-script-generator / `/shared/dist/manifest.json` may already pin). Otherwise **confirm → `git tag -a v<version> -m "<msg>"` → push the tag.**

**G5. Dist-publish handoff.** If the release publishes `/shared/dist/`, print the exact next steps: run `clone-script-generator` into a local clone pinned to the new tags → `create-org`/`apply-updates` diffs the clone against the backend and republishes `/shared/dist/` + `manifest.json` → verify the manifest's `org_release_tag` and per-artifact sha256. (This task stops at the script; it does not itself publish — same boundary as the clone generator.)

Both scripts print a per-step status line and exit non-zero on any abort, so the developer and any wrapping automation can tell they failed.

**On success:** Proceed to Step 4.

---

### Step 4: Deliver

Write both scripts to `<install_root>/.agent-index/` (`prep-<headline-tag>` and `push-<headline-tag>`) and surface them to the developer with: **run prep first, then push**; the push order; which repos will be tagged at which `v<version>`; and (if applicable) the dist-publish handoff. Remind them the scripts run **natively** — the agent neither builds nor pushes (esbuild needs the host binary; agent-side git over a synced mount tears commits).

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
