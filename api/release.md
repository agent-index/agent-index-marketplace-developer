---
name: release
type: task
version: 1.0.0
collection: developer
description: Generates a host-native, preflight-gated, version-gated release push script for one or more agent-index repos — code-repos-first/listings-last ordering, per-repo commit→push→tag (v<version>), and a backend-distribution publish handoff. The ship-side counterpart to core's clone-script-generator.
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

A single host-native script written to `<install_root>/.agent-index/release-<headline-tag>.{ps1,sh}`, surfaced to the developer to run natively. No repos are pushed by this task. The task also prints the post-run handoff (the dist-publish sequence) when the release publishes `/shared/dist/`.

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

### Step 3: Generate the script

Emit one self-contained host-native script (`.ps1` for windows, `.sh` for darwin/linux). It must implement, in this order:

**A. Version gate (pre-flight, fail-closed).** For each repo, assert the declared version equals the intended target (`collection.json`/`adapter.json` `version`, listings `directory_version`). On any mismatch, print the repo + expected/actual and exit non-zero. This is the guard that stops a "I forgot to bump X" release.

**B. Subroutine/asset presence gate (when applicable).** If the release publishes `/shared/dist/`, assert the Release-C subroutines exist in the core tree (`templates/clone-script-generator.md`, `templates/backend-distribution.md`). If the release includes an adapter, assert `dist/<bundle>` exists and its sha256 matches `adapter.json` `exec_bundle_checksum` (computed on the **git-blob LF bytes** — Windows checkout converts LF→CRLF and breaks the SHA).

**C. Manifest restamp (idempotent).** For each collection repo, set every `api/*-manifest.json` `collection_version` to that repo's `collection.json` `version`. (Preflight Check 2 requires ALL manifests aligned, not just touched ones; five shipped collections failed this in the 2026-06 sweep.)

**D. Mandatory preflight (hard gate).** For each collection repo, run `lib/preflight-cli.sh --collection <repo>` (path: the developer collection's CLI). **Abort the entire release on any error** — this is the `release-script-runs-preflight` contract, now generated rather than remembered. Offer `confirm "Continue anyway?"` ONLY for warnings, never for errors.

**E. Per-repo push, in the Step-2 order.** For each repo, a `push_one` routine that:
1. Verifies the dir is a git repo with an `origin` remote (print the `git remote add` command and skip if not).
2. Shows `git status --short` + staged diff; **confirms before commit**; commits with the supplied message.
3. Compares local HEAD to `@{u}`; **confirms before push**; pushes the current branch.
4. **Tagging:** if tag `v<version>` already exists at HEAD → leave it. If it exists pointing elsewhere → print a loud warning and do NOT move it (operator cuts a new tag by hand; we never force-move a published tag the clone-script-generator may already pin). Otherwise **confirm → `git tag -a v<version> -m "<msg>"` → push the tag.**

**F. Dist-publish handoff.** If the release publishes `/shared/dist/`, print the exact next steps: run `clone-script-generator` into a local clone pinned to the new tags → `create-org`/`apply-updates` diffs the clone against the backend and republishes `/shared/dist/` + `manifest.json` → verify the manifest's `org_release_tag` and per-artifact sha256. (This task stops at the script; it does not itself publish — same boundary as the clone generator.)

The script prints a clear per-repo status line and exits non-zero on any abort, so both the developer and any wrapping automation can tell it failed.

**On success:** Proceed to Step 4.

---

### Step 4: Deliver

Write the script to `<install_root>/.agent-index/release-<headline-tag>.{ps1,sh}` and surface it to the developer with: the push order, which repos will be tagged at which `v<version>`, and (if applicable) the dist-publish handoff. Remind them it runs **natively** — the agent does not push.

Confirm the release-checklist (the developer collection's release-checklist reference) is satisfied before they run it.

**On success:** Task complete.

---

## Directives

### Behavior

Operate as the ship-side partner. Never generate a release script without first reading each repo's actual declared version (Step 1) — the version gate is only as good as the truth it's seeded with. Always put `agent-index-resource-listings` last. Always make preflight a hard gate on errors. Always tag, and never instruct moving a published tag. Adapt verbosity to the developer's experience level, but never skip a gate to move faster.

### Output Standards

The deliverable is one self-contained host-native script. It must be runnable as-is, print per-step status, use confirm prompts for commit/push/tag, and exit non-zero on any abort. PowerShell for windows; bash for darwin/linux. No agent-side push.

### Constraints

- This task generates a script; it never pushes, tags, or publishes anything itself.
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
