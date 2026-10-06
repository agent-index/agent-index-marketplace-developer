# Developer Collection — Changelog

## [1.14.0] — 2026-10-01 — Permission changes through the core procedure; new preflight Check 17

**MINOR — pairs with agent-index-core 3.32.0.** Part of retiring the permission-change-helper (design record: `/shared/projects/core-improvements/artifacts/retire-permission-helper-*.md`).

### Added
- **Preflight Check 17** (`preflight` 1.9.0 → 1.10.0; `lib/preflight-cli.sh`): permission changes only through core `internal/permission-changes.md`.
  - **ERROR** on any invocation of `aifs_share` / `aifs_unshare` / `aifs_transfer_ownership` in capability files.
  - **WARNING** on leftover `permission-change-helper` / `build-permission-spec` / `agent-index://` references.
  - **WARNING** on a `collaborative-acls.json` using the legacy `grants` key.
  - This replaces the "preflight flags direct calls" check that standards.md described but no version implemented.
  - Invocation detection ignores backticked prose mentions such as `` `aifs_unshare()` `` and catches a quoted executor argument (`aifs-exec.sh "aifs_share" …`).

### Changed
- **`develop` 1.5.0 → 1.6.0** — access-model guidance: owners confirm grants through the core procedure. The verified-outcome gate is keyed on the procedure's row states. The core-edit constraint now allows an explicit admin authorization, recorded in the design record. New **sharing callers** rule set: declared sources only, any recipient (outside-org flagged), choices before the table, no access record before the gate, no destructive state from declined/cancelled rows, recompute after removals, and `all_or_nothing` only for sets that are meaningless when half-applied. The same rule set is added to core's `collection-authoring-guide.md`.
- **`developer-guide` 1.3.0 → 1.4.0** — the sharing answer describes the procedure. The Level-3 reference implementation is now core `lib/permission-changes/permission-changes.js` (replacing `build-permission-spec.js`).
- **`preflight`** — the `inherit:false` check and the grant-gating warning are reworded for the procedure.

### Added — distribution channels (stage mode)
- `release-stage` cleans up: each repo is checked out again on the branch it started on after its push (`--stay-on-channel` / `-StayOnChannel` keeps it on the channel). Because repos now return to the default branch, a re-run from that branch no longer replaces a channel that holds staged commits: an unchanged repo is left as is, a changed one needs a typed `REPLACE`, and the script shows how to add the changes to the candidate instead.
- `release-stage` warns when `agent-index-core` isn't in the set (the test org's clone tooling would fall back to a core without channel support). release-checklist S1 says the same.
- **`release` 1.2.0 → 1.3.0** — new stage mode: stage → test → promote. The Step 1 interview asks "stage to a channel, or release?"; Step 4 surfaces the stage invocation and the promote steps.
- **`lib/release/release-stage.{sh,ps1}`** (new) — same manifest as `release-push`, plus `--channel <name>` / `-Channel <name>`. Pushes every repo in `push_order` to `channel/<name>` so a test org on that distribution channel can install the candidate before anything is tagged.
  - Gates before any write: channel name `^[a-z0-9][a-z0-9-]{0,39}$`; no `.git/index.lock` (refuses, never deletes); an `origin` remote and a checked-out branch; the same preflight invocation `release-prep` uses (`--skip-preflight` prints a loud warning).
  - Already on `channel/<name>`: commit `stage(<name>): <repo> v<version>` and fast-forward push, no force. On any other branch: `git checkout -B channel/<name>` (working changes kept), commit, `push --force-with-lease`, after saying the existing `origin/channel/<name>` will be **replaced**.
  - Repos with no changes are still pushed at `HEAD`. Never tags; never pushes the default branch. Prints the test-org handoff and the promote steps (PR → merge → `release-push --tag-only` → `git checkout <default> && git pull`).
  - `--yes` / `-Yes` answers every prompt; for tests/CI only.
- `lib/release/README.md` and `release-checklist.md` gain the stage path.

### Fixed
- **Preflight Check 14** compared `exec_bundle_checksum` including its `sha256:` prefix against a bare hash, which would report a false mismatch on every adapter. The prefix is now stripped before comparing.
- **`release-prep.{sh,ps1}`** no longer skips adapter repos: a repo with `adapter.json` and no `collection.json` is gated on `adapter.json` `version` and on the bundle checksum + `node --check`. `exec_bundle_checksum` is accepted as bare hex or `sha256:<hex>` (the form the adapters actually use; the old pattern matched only bare hex).
- **`release-push --tag-only` / `-TagOnly`** now version-checks adapters (`adapter.json` at the merged commit) and catalog repos (each catalog entry that lists another repo in the manifest must carry that repo's manifest version), not only `collection.json`.
- `api/release.md`: the branch-aware section was labelled "release 1.2.0"; it is "developer 1.13.0".

### Fixed — release tooling on Windows
- **`release-prep` no longer reports `PREP OK` after checking nothing.** On Windows, `python3` is often the Microsoft Store alias stub: `command -v python3` succeeds, but running it prints "Python was not found" and outputs nothing. `release-prep.sh` read that as an empty repo list, skipped every gate, and printed `PREP OK` (hit on 2026-10-06 shipping bug-reports 1.4.0; `release-push` caught it as "push_order is empty").
  - New `lib/release/_python.sh`, sourced by `release-{prep,push,stage}.sh`: resolves a Python 3 that actually **runs** (`python3`, then `py -3`, then `python`) and fails with install guidance if none does. It strips the CR that Windows Python writes to stdout (it corrupted repo names read back by the scripts) and converts the manifest path to `C:/...` form so Windows Python can open it.
  - `release-prep.sh` / `.ps1` refuse an empty repo list and count what they prepped: `PREP OK -- N repo(s) gated + stamped`, and a run that prepped nothing fails instead.

## [1.13.0] — 2026-09-30 — release-push tags only merged commits

### Changed
- **`release-push` is branch-aware** (`release` task 1.1.0 → 1.2.0; `lib/release/release-push.{ps1,sh}`). A release tag now always points at a commit on the repo's default branch.
  - **On the default branch:** unchanged — commit, push, tag. Orgs whose repos have no PR rules see no difference.
  - **On any other branch:** commit, push the branch, then **defer the tag** and print the PR to open. New `-TagOnly` / `--tag-only` mode, run after the PR merges: fetches, confirms `origin/<default>`'s `collection.json` carries the manifest version (stops before later repos if not, so listings stay last), and tags that merged commit.
  - Why: before this, releasing from a feature branch tagged the pre-merge commit. Under a squash or rebase merge that commit never lands on the default branch, so tag-pinned clones would install code that is not on `main`. Releasing from `main` instead only worked for accounts allowed to bypass the repo's PR rule — every Agent Index Inc release on 2026-09-28/30 printed "Bypassed rule violations".
- The push output is no longer buried: a push that succeeded only by **bypassing repository rules** now prints a warning, and a push rejected for a **protected branch** explains the branch + PR + `-TagOnly` route instead of just failing.

### Verified
- `release-push.sh` against throwaway repos with a local bare remote: a release from `main` tags `HEAD` as before; a release from `release/x-1.0.2` pushes the branch and defers; `--tag-only` before the merge stops (`origin/main` still at 1.0.1); after a squash merge `--tag-only` tags the squash commit on `main` — not the branch commit. `release-push.ps1` carries the same logic line for line; it could not be executed in the authoring sandbox (no PowerShell), so its first real run is the next release.

### Changed (housekeeping)
- All 6 manifests restamped to `collection_version` 1.13.0.

## [1.12.0] — 2026-09-30 — preflight checks every catalog, and Check 13 actually matches

### Fixed
- **Checks 10, 12 and 13 looked only at the public catalog** (`preflight` task 1.8.0 → 1.9.0; `lib/preflight-cli.sh`). Since core 3.31.0 a collection can be listed in a private catalog instead — `cx-studio` is listed only in `agent-index-private-marketplace` — and none of the three checks read it. cx-studio 4.0.0 shipped with that listing still advertising 3.0.4, and preflight passed it (bug `privatecatalogunchecked`). The CLI now builds one catalog list — `$COLL` if it is a catalog repo, `RESOURCE_LISTINGS_PATH` or the sibling `agent-index-resource-listings`, a new `CATALOG_PATHS` (colon-separated), and every sibling clone holding a `marketplace-directory.json` — and all three checks iterate it. Messages name the catalog they came from.
- **Check 13 never matched a marketplace collection.** It compared the catalog entry's repo basename with the collection name. That holds for `agent-index-core` and `agent-index-marketplace` and for nothing else: every marketplace repo is `agent-index-marketplace-{name}`, so since 1.10.0 the check reported "not found in any reachable directory" for every collection it was written for — `projects`, `library` and `strategy` included, not only private ones. It now matches on the entry's `name`, the repo basename, or the collection's directory name, reports every catalog that lists the collection, and when none does, says which catalogs it searched.

### Verified
- Positive: cx-studio 4.0.1 now matches its private listing; projects 4.3.0, library 1.6.1 and core 3.31.0 match the public listings (all previously "skipped" apart from core).
- Negative: a private listing reverted to 4.0.0 without a `directory_version` bump fails with two errors — Check 10 (content changed, `directory_version` unchanged) and Check 13 (4.0.0 != 4.0.1). Before this release both passed silently.
- Sweep of all 13 source clones under Check 13, which runs for the first time: every catalog listing matches its source. The only mismatch was this collection's own public listing (1.11.0), which this release updates to 1.12.0 (`agent-index-resource-listings` `directory_version` 1.26.0 → 1.27.0).

### Changed
- `ROADMAP.md` `Current version` corrected from 1.6.1 (five releases stale) to 1.12.0.
- All 6 manifests restamped to `collection_version` 1.12.0.

## [1.11.0] — 2026-09-20 — Release C.1.5.3: spec-doc currency check + CHANGELOG re-encode

Every item below was verified against the tree before it was written here, and the "Not in this release" section is deliberate. Companion to core 3.28.3.

### Added
- **preflight Check 16 — spec-document currency** (`preflight` task 1.7.0 → 1.8.0; `lib/preflight-cli.sh`). Scope is root-level `*.md` only — `standards.md`, `ROADMAP.md`, `README.md`, `*-spec.md`, `*-guide.md`; `api/`, `setup/`, `internal/` and `upgrade/` are already covered by Check 1. Two tiers by design. A document that declares a currency header must keep it accurate: WARNING when the newest CHANGELOG entry naming the file is dated after the header, WARNING when the CHANGELOG records a later version for it than the header declares. A document that declares nothing gets **one** summary adoption WARNING naming the files — never one per file, because seventeen documents across the org are in that state and per-file errors would fail every collection on first run. ERROR is reserved for a single case: a declared `Version` **ahead** of anything the CHANGELOG records for that file — a forward reference, meaning the document was bumped and the release was not. `ROADMAP.md` is excluded from the version half, which stays with Step 4. The version match requires the strict backticked `` `file` (vX.Y.Z) `` form, so looser prose cannot trigger it.
  - Executed against deployed core rather than predicted: 6 warnings, 0 errors, and it re-derives the two missing-section findings from the files and the CHANGELOG with no knowledge of the audit that first found them.
  - Coverage note: all four branches of the check are exercised by a throwaway fixture collection, including the swapped pair that distinguishes behind-spec (WARNING) from ahead-of-spec (ERROR). The version-ahead branch has no live example in this repo.

### Fixed
- **`CHANGELOG.md` — UTF-8-read-as-CP1252 mojibake repaired.** 137 mis-decoded sequences across five forms: 92 em dash, 41 right arrow, 2 left-right arrow, 1 en dash, 1 section sign. Every run round-trips cleanly, so the repair is mechanical rather than editorial — no run required a judgement about what was meant. Byte-order mark preserved, line count unchanged, no ASCII byte altered. Verified by re-applying the mis-decode to the corrected file and reproducing the original byte for byte.
  - The count was first reported as 94. That figure came from grepping a single two-character signature, which misses the arrow family entirely — 43 sequences, a third of the corruption. The acceptance test used here instead asserts that the three lead characters this fault always begins with (U+00C2, U+00C3, U+00E2) do not occur anywhere in the file, which catches the whole class by construction rather than by enumeration. Stated as codepoints deliberately: writing the literal sequences into this file would make the CHANGELOG fail its own test.
  - Same fault as core's, at 137 sequences against core's 640. This repo was outside the scope of the original finding, which was written against core only.

### Not in this release
- **Neither preflight gate can see character-encoding corruption.** `lib/preflight-cli.sh` and the `preflight` task both return clean on a CHANGELOG corrupted in every em dash — confirmed by running the CLI against this tree with and without the re-encode and getting byte-identical output. Unlike the CLI-is-a-subset problem, this is a gap in *both*, so it is a coverage hole rather than a subset difference. A Check 17 built on the lead-character assertion above is proposed and not implemented.
- **The `@ai:preflight` / `preflight-cli.sh` gate-equivalence defect is not fixed.** `standards.md` names the two as interchangeable; the CLI is a strict subset and is the one the release push script gates on. On the same tree in the same hour the CLI returned 0 errors and the full task returned errors the CLI has no check for.
- **Check 16 cites `standards.md` § "Spec Document Currency", which does not exist yet.** The rule is drafted and blocked on two open decisions in core. The check is self-describing and functions without it, but the citation is a forward reference until that section lands.

## [1.10.0] — 2026-07-18 — Release C.1.5.0: committed release tooling + preflight gate consolidation

### Added
- **`lib/release/` — committed release tooling (level-3).** `release-prep.{ps1,sh}` + `release-push.{ps1,sh}` + manifest schema replace the per-release generated prep/push pair; the `release` task emits only a release-delta manifest. Includes the **pre-push diff + integrity gate** (flags a lost `AIFS:FILE-END` sentinel vs HEAD, a missing trailing newline, or a non-HTTPS `origin`), CHANGELOG date-stamp at push, resource-listings-last order, remote-URL HTTPS guard.
- **preflight Checks 13–15.** 13: catalog `current_version` == collection.json version; 14: adapter build integrity (`exec_bundle_checksum` + `node --check`); 15: trailing-newline truncation guard.

### Changed
- **developer-guide — the three-maturity-level tier principle** (inline → generated-script → committed-script+data) + adapter test-contract hygiene (`getpermsinvalidownerfield` class). **`optimize`** flags level-2 patterns as promotion candidates. **`develop`** scaffolds new collections with the standard LF `.gitattributes`.

## [1.9.0] — 2026-07-13 — Release C.1.4.4: preflight phantom-version guard (catalogphantomversion)

### Added
- **`preflight-cli.sh` — Check 12: catalog current_version has a matching released git tag.** For each resource-listings catalog entry (marketplace / adapter / infrastructure directories), verifies a `v{current_version}` tag exists on the corresponding local sibling clone. ERROR when a clone has tags but not the cataloged one (a phantom version — cataloged release was never tagged); WARNING when the clone is absent locally (can't verify offline). Reads local clone tags only (no web). Surfaced the client-intelligence 2.2.0 (real=v2.3.0) and strategy 1.1.4 (real=v1.2.0) phantoms; both catalog entries corrected in resource-listings.

## [1.8.0] — 2026-07-01 — release task generates the two-script (build-and-prep + push) flow

### Changed
- **`release` task 1.0.0 → 1.1.0 — generates BOTH release scripts, not just push.** Codifies the mature two-phase process validated in C.1.3.5: Step 3 now emits an idempotent **build-and-prep** script (P1 adapter `npm test` with module-resolution exit-classification → P2 native `npm run build` + `exec_bundle_checksum`/`bundle_built_at` stamp + `node --check` → P3 restamp every `api/*-manifest.json` `collection_version` → P4 restamp resource-listings `current_version`/`directory_version`/`last_updated` → P5 fail-closed version-consistency gate) AND the gated **push** script (G1 re-assert prep gates → G2 surgical changelog date stamp → G3 mandatory preflight → G4 per-repo commit→push→tag in code-first/listings-last order → G5 dist handoff).
- **Version-consistency gate now asserts manifest alignment at the earliest (prep) phase.** Step 3A/P5 require every `api/*-manifest.json` `collection_version` to equal `collection.json` `version` — not just the top-level number. A gate that checked only `collection.json` let core 3.22.5 (C.1.3.5) ship all 20 manifests a version behind, caught only at the push-time preflight and requiring a hotfix + force-moved tag. `release-checklist.md` carries the matching lesson.

## [1.7.1] — 2026-06-29 — release-checklist: classify the adapter-test exit (C.1.3.3)

### Added
- **Lesson: `node --test` in an adapter dir false-alarms on the host.** Adapter test files import the framework via `file:../agent-index-filesystem`, which `npm install` doesn't reliably link on Windows/Git Bash → `ERR_MODULE_NOT_FOUND` before any assertion runs, so the runner exits non-zero and looks like "tests failed" when the code is fine. A release script's adapter-test step must **classify the exit**: module-resolution signature → advisory skip (bundle build + `exec_bundle_checksum` match is the real gate); genuine non-zero (assertion failures) → block. Stops the cry-wolf risk of "continuing anyway" past a real failure. (release-checklist.md Lessons.)

## [1.7.0] — 2026-06-26 — Ship-side codification: the release process becomes a tool

The *authoring* side of releasing was well-codified (lifecycle, version-bump mechanics, preflight, listings broadcast); the *ship* side lived only as tribal knowledge in hand-copied `push-*.sh` scripts. This release moves the push-script pattern, the tagging strategy, and the backend-distribution publish into the developer collection so they become the way everyone ships.

### Added
- **`release` 1.0.0 (new task)** — generates a host-native, preflight-gated release push script: a version gate (assert each repo's declared version == target), mandatory `preflight-cli` (errors abort), manifest restamp, **code-repos-first / `agent-index-resource-listings`-last** push order, and per-repo commit→push→**tag `v<version>`** (never moving a published tag — the `clone-script-generator` pins to those tags), plus the `/shared/dist/` publish handoff. The ship-side counterpart to core's `clone-script-generator`; like it, the task only *generates* — the agent never pushes (host credentials + clean-tree + FCI-1 safety boundary).
- **`release-checklist.md` (new reference, collection root)** — the single ordered gate list (pre-push → push+tag → backend publish → test-the-release) that `release` generates against. Resolves the long-dangling "the org's release checklist" reference in the `develop` lifecycle.

### Changed
- **develop 1.5.0** — lifecycle Release stage (step 8) now names tagging + `/shared/dist/` publish and routes to `@ai:release`; Version Bump flow adds step 7 ("a bump is not shipped until pushed AND tagged"); the lifecycle's checklist reference now points at the real `release-checklist.md`.
- **preflight 1.7.0** — new release-readiness NOTE (Step 7): a clean preflight is not "released"; reminds the developer that tagging + backend manifest are post-push gates preflight can't see, and routes to `@ai:release`. NOTE only, never a gate — preflight's job ends at the push boundary.
- Companion: `agent-index-core` standards.md gains a "Release procedure (admin-side)" section (push ordering, tag convention + never-move-a-published-tag, preflight-gate, agent-never-pushes, then backend publish).

## [1.6.1] — 2026-06-10 — repair: tail truncations introduced in 1.6.0

The 1.6.0 release commits contained tail-truncated capability specs — a mount-mediated read-modify-write during version restamping wrote stale truncated views back to disk (FCI-1 class; see bug 20260608-8d20ea22-003039-trunc and release record platform-reliability/build-record.md). 1.6.1 splices the complete pre-release tails back under the 1.6.0 content edits, verified byte-exact against the pre-release endings, and stamps the repaired files with AIFS:FILE-END sentinels. No behavioral changes beyond 1.6.0.

## [1.6.0] — 2026-06-09 — Platform Reliability: file-integrity sentinel authoring + enforcement

Release record: core-improvements `releases/platform-reliability/`. Implements the developer-collection half of the sentinel standard (standards.md § "File-integrity sentinel"); partially addresses `20260608-8d20ea22-003039-trunc` (prevention).

### Added
- **preflight 1.6.0**: new CLI **Check 11** — file-integrity sentinel. Collections declaring `"file_integrity": "sentinel-v1"`: missing `AIFS:FILE-END` on a stampable file is an ERROR (presumed tail truncation). Non-declaring collections get a single summary WARNING (adoption nudge). Check 6's mid-word heuristic remains for unstamped legacy files only. Spec section added under Step 7 Content Quality Checks.
- **develop 1.4.0**: New Collection flow Phase 5 item 11 — scaffolded collections declare sentinel-v1 and every generated file is stamped from birth. Version Bump flow step 5a — re-stamp sentinels on touched files; offer adoption to non-declaring collections.

## [1.5.1] — 2026-06-07 — directory_version bump enforcement

### Fixed

- **`preflight` Step 4 (Resource-listings broadcast)** now ERRORs when listing content changed but the directory file's top-level `directory_version` did not. Closes the gap that silently hid two shipped batches (developer 1.5.0 docs-currency + the brand-book program) from `check-updates`/`refresh-marketplace-cache` — bug 20260607-8d20ea22-131906-d1rv.
- **`develop` release guidance** now lists the `directory_version` bump as a mandatory, easily-forgotten fourth step of the resource-listings broadcast (bumping `last_updated` alone is insufficient).
- **`lib/preflight-cli.sh` Check 10** — mechanical guard: when a sibling `agent-index-resource-listings` clone is reachable, errors if the entry's `current_version` moved (vs git HEAD) while `directory_version` did not.

## [1.5.0] — 2026-06-06 — access-model currency (companion to the 2026-06 cross-collection audit)

### Changed

- **`develop` 1.3.0 — "Native permissions awareness (v3.1.0+)" replaced by "Access-model design (core 3.9+)".** Teaches the three proven patterns (open-commons / owned-content / two-tier hybrid) and their structural implications; supersedes the per-task `aifs_share` guidance (grants on member-owned content are owner-applied via the permission-change-helper with the verified-outcome HARD GATE). Adds the org sharing vocabulary, pointer conventions (overwrite-only, scope shapes, parent/hygiene rules, owner_departed, invisible-until-shared), `id:`-anchor preference (duplicate-name bug 20260606-62a14c43-230135-db13), and the non-recursive `aifs_delete` contract. Phase 1 gains a default-visibility question; Phase 5 scaffolds `collaborative-acls.json` and pointer-index creation in Setup Completion.
- **`preflight` 1.5.0 — new Step 7.5: Access-Model Consistency.** ERRORs: shared write paths without covering `collaborative-acls.json`; ACL dirs not created by Setup Completion; retired constructs (`projects-manifest.json`, `shared_projects_path`, `aifs-bridge`, `server.bundle.js`). WARNINGs: ungated grant steps, missing `if_revision` on multi-writer files, name-path resolution in duplicable trees, recursive-delete assumptions, off-vocabulary sharing language.
- **`optimize` 1.2.0 — Step 7 example modernized.** The retired projects-manifest loader example replaced with a pointer-index lister.
- **`developer-guide` 1.3.0** — "How do I share..." answer updated for owner-applied grants; new question pattern "How do I decide who can read/write my collection's data?" mapping the decision rule to the three patterns with reference collections.

- **`develop` — Development Lifecycle section.** The nine-stage process (functional outcomes → solution design review → technical design review → test plan review → dev → test → iterate until bug-free → release → post-release test as a real non-admin member), with the paper-trail expectation: every stage produces a reviewable, resiliently-stored record. Skipping a stage is an explicit decision, never a default.
- **`develop` Version Bump Flow step 3a** — restamp every manifest's `collection_version` (and touched capabilities' versions) at every bump; five shipped collections had missed this.
- **`preflight` Step 4** — README `## Version` stanza must equal collection.json version when present (mechanical twin: `lib/preflight-cli.sh` **Check 9**, negative-tested).
- **`preflight` Step 7.5** — additional warning: leading-slash `/members/{hash}/` paths intended as local writes (deprecated-remote-space lookalike; found in two shipped setup templates).

### Notes

- Docs-only release plus one mechanical check (CLI Check 9): no shared writes, no provisioning, no setup-interface changes (MINOR).
- `agent_index_min_version` raised to 3.9.0 — the access-model content assumes My Drive member spaces and install-time ACL provisioning.

## [1.4.0] — 2026-07-18 — companion to core 3.7.4

### Added

- **`lib/preflight-cli.sh` Check 8 — `inherit: false` spec usage vs adapter contract version.** Closes section 4 of idea `helper-spec-needs-inherit-passthrough`. Catches the forward-compat regression where a spec emits `inherit: false` against an org adapter that declares `contract_version < 2.0.0`. Pre-2.0 adapters silently ignore the field; the share applies with default-additive semantics rather than override — degraded, not failing. Warning-level (not error-level) so forward-compatible specs targeting future adapter rollouts aren't blocked.
- **`preflight.md` Step 4 — `inherit: false` spec usage sub-check** describing the bash CLI's Check 8 mechanics at the agent-task documentation level. Resolution order: `ADAPTER_CONTRACT_OVERRIDE` env var, then candidate install layouts; skip-with-notice if no adapter contract_version found.

### Fixed (correctness, pre-release)

- **Check 8 reads `contract_version` (filesystem-contract field) NOT `adapter_version` (adapter package version field).** The two are distinct surfaces — `contract_version` lives in `mcp-servers/filesystem/adapter.json`, `adapter_version` lives in `agent-index.json`'s `remote_filesystem.exec` block. They share a major version coincidentally today (both at 2.x) but are conceptually different. The original tech-design draft conflated them; corrected during pre-build cross-component verification per the 3.7.3 retro process change.

### Notes

- All API manifests' `collection_version` bumped 1.3.1 → 1.4.0. `preflight` task version 1.3.0 → 1.4.0 (minor — new check addition is a meaningful behavior change).
- Companion release: agent-index-core 3.7.4 "Closing the Loop" — closes four bugs surfaced by 3.7.3 verification cycle plus the non-admin onboarding blocker.

---

## [1.3.1] — 2026-05-13

### Added

- **`lib/preflight-cli.sh` Check 7 — JS-integrity heuristic.** Catches the "validate.js debris" corruption class: JS files that have a clean apparent end (legitimate `module.exports`) followed by debris (duplicate function definitions, a second `module.exports`, stray prose fragments) past the apparent end. Surfaces as ERROR when: (a) more than one top-level `module.exports = ` line, or (b) duplicate top-level `function foo(...)` declarations. Would have caught the validate.js corruption that shipped from an earlier edit and blocked AC-016 testing on 2026-05-13.

### Notes

- No spec edits to `preflight.md`; v1.2.x's preflight workflow already documents Step 4 release-artifact integrity checks at the agent-task level. This patch adds the same hazard class to the runnable CLI used by release push scripts.
- All API manifests' `collection_version` bumped 1.3.0 → 1.3.1. `preflight` task version unchanged.

---


## [1.3.0] — 2026-05-11

### Added

- **`lib/preflight-cli.sh`** — bash CLI runner for the mechanical preflight checks. Invocation: `bash lib/preflight-cli.sh --collection <path>`. Returns 0 on pass, 1 on errors, 2 on invocation problems. Runs the subset of `@ai:preflight` checks that don't require agent reasoning: (1) frontmatter `version:` ↔ matching `*-manifest.json` `version`, (2) every `*-manifest.json` `collection_version` ↔ `collection.json` `version`, (3) `CHANGELOG.md` top entry matches `collection.json` version, (4) every shipped `*.sh` has LF-only line endings, (5) every `*.json` parses cleanly, (6) mid-word truncation heuristic on `*.md` files.

  Designed for invocation from release push scripts as a mandatory pre-step: `node ../agent-index-marketplace-developer/lib/preflight-cli.sh --collection . && git push ...`. Aborts the push if any error fires. Closes idea `release-script-runs-preflight`. Would have caught the bugs in developer 1.2.3 (frontmatter drift in `preflight.md`) and the bash-mount truncation incidents that hit 3.6.0 / 3.6.1 publish flows. Agent-side `@ai:preflight` (the full task) remains the canonical comprehensive check; this CLI just covers the structural subset, runnable in non-agent contexts.

### Changed

- `preflight` task version 1.2.4 → 1.3.0. All API manifests' `collection_version` bumped 1.2.4 → 1.3.0.

---


## [1.2.4] — 2026-05-07

### Fixed

- **`preflight.md` frontmatter version bumped to match the manifest.** The 1.2.3 release expanded `preflight.md` substantially with two new Step 4 sub-checks (adapter supported-ops vs bundle implementation, shipped shell-script line endings) and bumped `preflight-manifest.json` from 1.2.2 to 1.2.3, but left `preflight.md`'s frontmatter `version` field at 1.2.2. This is the exact drift that 1.2.2's preflight Step 5 is supposed to catch — and would have, if the developer collection had been preflighted against itself before the 1.2.3 release. Caught post-publish during dev_install upgrade verification on 2026-05-07. Filed as bug `20260507-8d20ea22-8` (release-discipline bug; the next release author should always run preflight against the developer collection itself before pushing).

## [1.2.3] — 2026-05-05

### Added

- **`preflight` task Step 4 — Adapter supported-ops vs bundle implementation.** New release-artifact integrity check. For every op name in `adapter.json` → `supported_operations`, search the bundle file for at least one of three recognizable implementation signatures (literal op name, canonical `aifs_<snake_case_op>` wrapper, or handler-pattern match like `case '<op>':` or `async <op>(`). Zero matches → ERROR with the bundle path, the manifest path, the missing op names, and the patterns that were tried. Catches the failure mode in bug `20260502-8d20ea22-2`: gdrive 2.2.0's `adapter.json` declared `share`/`unshare`/`getPermissions`/`search`/`transferOwnership` while the bundle was byte-identical to 2.1.3 (no implementations). The pre-1.2.3 freshness checks (timestamp + checksum) couldn't catch it because the broken state was self-consistent. Grep-based for portability across bundling formats; asymmetric (false positives are the dangerous case, false negatives are recoverable by adjusting search patterns). Also surfaces a WARNING when `contract_version >= 2.0.0` but `supported_operations` is empty or absent — the v2.0 contract requires at least the read ops.

- **`preflight` task Step 4 — Shipped shell-script line endings.** New release-artifact integrity check. Walks the collection's `lib/`, `bin/`, and any subdirectories; for every `*.sh` file, scans for `0x0D` bytes (CR characters). Any hit → ERROR with the file path. Closes bug `20260504-8d20ea22-7`: `mcp-servers/permission-helper/show-plan.sh` shipped with CRLF line endings from a Windows host commit and bash refused to execute it (`bash: $'\r': command not found`). The fix is mechanical — convert to LF (`dos2unix`, `sed -i 's/\r$//'`, or "Save With Unix Line Endings"). Shell-script-only by design; other text formats tolerate either line ending.

### Closes

- Idea `preflight-bundle-vs-supported-ops` (developer-collection) — both sub-checks shipped under the broadened scope.
- Bug `20260502-8d20ea22-2` (already resolved by gdrive 2.2.1) — preflight now prevents recurrence.
- Bug `20260504-8d20ea22-7` (already resolved in core 3.3.1's apply-updates LF normalization) — preflight now catches it at upstream-release time too.

## [1.2.2] — 2026-05-02

### Fixed / Added

- **`preflight` task Step 5 — Manifest-frontmatter agreement, tightened.** The pre-1.2.2 wording said "verify the manifest's name, type, version, collection, stateful, dependencies, and external_dependencies match the frontmatter." That was ambiguous about whether the comparison checked value equality or merely field presence; in practice it was being interpreted loosely and not catching real version drift (e.g., `projects/api/edit-project-manifest.json` `version: 1.0.0` vs `projects/api/edit-project.md` frontmatter `version: 2.0.0`). The check is now explicit: it is a **value-equality** comparison, with `version` called out specifically because the `.md` frontmatter is the canonical source of truth (it's what `member-index.json` records, what `org-setup`'s "Needs Attention" reads, and what `check-updates` Step 4 compares against). A drifted manifest `version` is silently wrong because no consumer reads it, so it must be caught at author time.
- **`preflight` task Step 5 — New manifest collection_version sync check.** Sibling check that verifies each API member manifest's `collection_version` field exactly equals the `version` field in `collection.json`. Catches the common author-forgot-to-resync case (bump `collection.json` but not the manifests). Closes developer-collection idea `per-capability-manifest-vs-md-version-drift`.
- Both checks are paired in the same Step 5 section: together they catch *vertical* drift (manifest version vs `.md` frontmatter version, per-capability) and *horizontal* drift (manifest `collection_version` vs `collection.json` `version`, collection-level). Same hazard class as bug `20260430-8d20ea22` — two declared facts that must agree.

### Changed

- `preflight` task v1.2.1 → v1.2.2.
- `collection.json` description leads with the v1.2.2 changes.
- All API-member manifests bumped to `collection_version: 1.2.2`.

---

## [1.2.1] — 2026-04-30

### Added

- **`infrastructure-directory.json`** awareness across the developer collection. The new index file in `agent-index-resource-listings` broadcasts the latest versions of `agent-index-core` and `agent-index-marketplace` so admins running `check-updates` can discover infrastructure releases the same way they discover collection and adapter releases.
- **`develop` skill (v1.2.1):** new "Resource-listings broadcast" subsection — every release of any collection, adapter, or core/marketplace must update the matching directory entry as part of the same release. Pattern: bump `version` in the collection / adapter, update `current_version` in the relevant directory file, bump `last_updated`. Release is incomplete without all three.
- **`developer-guide` skill (v1.2.1):** new common-question pattern: "How do I broadcast a new release so admins discover it?" — explains the three directory files and the consistency requirement.
- **`preflight` task (v1.2.1):** new check category "Resource-listings broadcast freshness" in Step 4. Errors when the matching directory entry's `current_version` (and `contract_version` for adapters) doesn't match the collection's actual version. Note-level when the resource-listings repo isn't reachable from the preflight context.

---

## [1.2.0] — 2026-04-30

### Added

- **`develop` skill: native permissions awareness (v3.1.0+).** When the developer is authoring a task that touches shared resources, `develop` proactively surfaces the right access-control patterns: tasks with `produces_shared_artifacts: true` need an `aifs_share` step in their workflow, shared state files need `if_revision`, tasks calling v2.0+ ops need an adapter `contract_version` pre-flight. Cross-references the new "Designing for Native Permissions" section in `collection-authoring-guide.md`. Pushes back on agent-index-side permission state (grants log, resolved view) — backend ACLs are the source of truth.
- **`developer-guide` skill: v3.1.0 awareness.** Updated priority-order list of source documents to flag the new "Designing for Native Permissions" section in the authoring guide and the `agent-index-filesystem/SPEC.md` v2.0.0 contract (with note about the gdrive-only contract status). Two new common-question patterns: "How do I share / check permissions / audit a resource?" and "What admin tasks ship with agent-index-core?" — both v3.1.0+.
- **`preflight` task: four new check categories** (v1.2.0):
  - **README freshness** — every name in `collection.json` `api` array appears in README; numerical claims like "All N tools" match the actual count; version mentions in the README don't drift from `collection.json` `version`.
  - **ROADMAP version match** — if `ROADMAP.md` exists with a `Current version: X.Y.Z` line, it must match `collection.json`.
  - **Adapter manifest bundle freshness** — if `adapter.json` exists at the collection root, `bundle_built_at` and `exec_bundle_checksum` are checked against the actual bundle file (mtime + sha256).
  - **CLAUDE.md template alias coverage** (agent-index-core only) — every `type: task` API entry should appear in the Core aliases table in `.claude/CLAUDE.md.template`.
  - **Cross-package coordination reminder** — if the CHANGELOG mentions adapter contracts, new ops, new tasks, OAuth scope changes, permission, or schema changes, emits a NOTE to remind the developer to consider whether the developer collection's docs reference the new patterns.

### Changed

- `develop` 1.1.0 → 1.2.0
- `developer-guide` 1.1.0 → 1.2.0
- `preflight` 1.1.0 → 1.2.0
- All API-member manifests bumped to `collection_version: 1.2.0`

---

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

