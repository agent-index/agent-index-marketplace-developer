# Release Checklist (agent-index)

The ordered, ship-side gates for releasing any agent-index artifact — a marketplace collection, a filesystem adapter, or `agent-index-core`/`agent-index-marketplace`. This is the single source the `release` task generates against and that humans follow. It is the resolution of the "org's release checklist" referenced by the `develop` skill's lifecycle.

The development lifecycle (design → tech design → test plan → dev → test → iterate) precedes this; the checklist below is **stage 8, Release**, and **stage 9, Test the release**.

## Pre-push gates (must all pass before anything is pushed)

1. **Version bumped** — `collection.json` `version` (or `adapter.json` `version`, or the listings `directory_version`) reflects this release. PATCH/MINOR/MAJOR chosen per the Version Bump rules.
2. **Manifests restamped** — every `api/*-manifest.json` `collection_version` equals `collection.json` `version`; each touched capability's `version` is bumped in BOTH the manifest and the `.md` frontmatter. (Preflight Check 2 / Check 5 enforce this; five collections failed it in the 2026-06 sweep.)
3. **CHANGELOG entry** — newest entry matches the new version, dated today, changes under standard headings. README version stanza, if any, matches.
4. **Sentinels re-stamped** (collections declaring `file_integrity: sentinel-v1`) — every touched stampable file still ends with its `AIFS:FILE-END` marker.
5. **Resource-listings updated** — the matching entry in `marketplace-directory.json` / `filesystem-adapter-directory.json` / `infrastructure-directory.json` has the new `current_version` (and `contract_version` for adapters), AND the file's top-level **`directory_version` is bumped**, AND `last_updated` is moved. The `directory_version` bump is mandatory — staleness checks compare it; bumping `last_updated` alone hides the release.
6. **Preflight clean** — `@ai:preflight` (canonical) or `lib/preflight-cli.sh --collection <repo>` reports zero ERRORS for every collection in the release. Errors block; warnings are a judgment call.
7. **Adapter bundle fresh** (adapter releases) — `dist/<bundle>` exists and its sha256 matches `adapter.json` `exec_bundle_checksum`, computed on the **git-blob LF bytes** (Windows checkout converts LF→CRLF and breaks the SHA).

## Push + tag (generate with `@ai:release`; runs natively)

8. **Push order is dependency order** — adapter → core → marketplace → collections → **`agent-index-resource-listings` LAST**. The broadcast layer must never reference a version whose code/binary isn't live.
9. **Per repo:** commit (after diff review) → push → **tag `v<version>` → push the tag.** An existing identical tag is left alone; a tag pointing elsewhere is NEVER force-moved (cut a new tag by hand) — the `clone-script-generator` and `/shared/dist/manifest.json` pin to published tags.
10. **The agent does not push.** `git push`/tag run on the host where the credentials and a clean working tree are; agent-side git over a synced/mounted FS produces torn commits (FCI-1).

## Publish to the backend (backend-distribution orgs — Release C+)

11. **Clone at the new tags** — run the `clone-script-generator` to clone/pull each repo to its `v<version>` tag into the admin's local tree (the only GitHub touch, over the git protocol — not the rate-limited raw/REST path).
12. **Publish `/shared/dist/`** — `create-org`/`apply-updates` diffs the local clone against the backend and republishes only what changed: collections → their remote trees; directories + binary → `/shared/dist/` + `manifest.json`. Members read from here, never from github.com.
13. **Verify the manifest** — `/shared/dist/manifest.json` `org_release_tag` + per-artifact `sha256` reflect this release. This file is the org's version authority; `check-updates` compares against it.

## After release (stage 9)

14. **Test the release** in a real install as a real (non-admin) member — not admin-as-proxy. Record results. File any findings as bugs; fold fixes into a point release through this same checklist.

## Lessons (learned the hard way)

- **A release is a defined changeset, not "whatever is dirty in the tree."** (Release C, 2026-06-26.) Doc edits from a *different* effort had landed in repos the Release-C push script managed; the script's `git add -A` swept them into the release commit, and because the version tags had already been cut on the prior commit, the tags ended up one commit behind `main`. The push script's "never move a published tag" guard caught it. Mitigation: before running a release, confirm `git status` shows ONLY the changes that belong to this release; stash or land unrelated work separately. The `release` task scopes a release explicitly for this reason — prefer it over a blanket `git add -A`.
- **The only safe time to re-cut a tag is before anything consumes it.** A just-pushed tag that the `clone-script-generator` / `/shared/dist/manifest.json` has not yet pinned has zero consumers and can be re-cut (delete + repush) freely. After the clone-script-generator runs and the backend publishes, the tag is load-bearing — then "never move a published tag" is absolute and a correction means a new version, not a moved tag.
- **Listings-last protects against broadcast-ahead-of-code only when the code repo is in the release set.** A directory entry was published for a collection whose code repo wasn't part of that push, leaving the broadcast ahead of the code until a separate push caught up. If a release bumps a listing entry, the matching code repo must be in the same release's push set.
- **`node --test` in an adapter dir false-alarms on the host; the bundle build + checksum gate is the real verification (C.1.3.3, 2026-06-29).** Adapter test files `import` the framework via the `file:../agent-index-filesystem` dependency, which `npm install` does not reliably link into `node_modules` on Windows/Git Bash — so `node --test` throws `ERR_MODULE_NOT_FOUND` *before any assertion runs* and the runner exits non-zero. That looks like "tests failed" but the code is fine (the same suite passes in a properly-linked env). The danger is crying wolf: an operator who reflexively "continues anyway" could one day skip a *real* failure. A release script's adapter-test step must therefore **classify the exit**: capture output, and if it matches a module-resolution signature (`ERR_MODULE_NOT_FOUND` / `Cannot find package '@agent-index/filesystem'`) treat it as an **advisory skip** ("framework dep not linked on host — tests not run; the bundle checksum gate is the verification"), NOT a failure; only a non-resolution non-zero exit (real assertion failures) blocks. The authoritative gate remains: the bundle builds via esbuild AND its sha256 matches `adapter.json` `exec_bundle_checksum`. (To run the tests for real, stage the framework into `node_modules/@agent-index/filesystem` first, e.g. a clean checkout where the `file:` link resolves.)

<!-- AIFS:FILE-END -->
