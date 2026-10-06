# lib/release -- committed release tooling (level-3)

Replaces the old pattern where the `release` task **generated** a bespoke `prep-<tag>`/`push-<tag>`
script pair every release (level 2 -- the release invariants were re-transcribed each time). The
prep/push logic now lives in committed, version-controlled scripts; the `release` task emits ONLY a
**release-delta manifest** (data) and surfaces these invocations.

## Files
- `release-prep.ps1` / `release-prep.sh` -- build+prep (NO git writes; safe to re-run): preflight
  hard gate per repo, adapter build+checksum (only repos flagged `is_adapter`), manifest
  `collection_version` restamp. Adapter repos (`adapter.json`, no `collection.json`) are gated, not
  skipped (1.14.0): `adapter.json` `version` must equal the manifest version, and the bundle's sha256
  must match `exec_bundle_checksum` (bare hex or `sha256:<hex>`) and pass `node --check`.
- `release-stage.ps1` / `release-stage.sh` -- **stage mode (1.14.0)**: push a release candidate to
  the branch `channel/<name>` in every repo of the manifest so a test org on that distribution
  channel can install it BEFORE anything is tagged. See "Stage -> test -> promote" below.
- `release-push.ps1` / `release-push.sh` -- the irreversible phase: **pre-push diff + integrity
  gate** (per repo: `git diff --stat`/full diff for operator review; integrity guard flags a lost
  `AIFS:FILE-END` sentinel vs HEAD, a text file with no trailing newline -- the torn-write signature
  that truncated create-org.md -- and a non-HTTPS `origin`), CHANGELOG date-stamp at push, then
  per-repo commit -> push -> tag `v<version>` in `push_order` (resource-listings LAST; an existing
  identical tag is left, a tag pointing elsewhere is NEVER moved), then the /shared/dist handoff note.
  **Branch-aware (1.13.0):** on the default branch it tags as it pushes; on any other branch (the PR
  workflow) it pushes the branch and defers tagging. After the PR merges, re-run with `-TagOnly` /
  `--tag-only` to tag the merged commit on `origin/<default>` -- never a pre-merge commit. It also
  warns when a push only succeeded by bypassing repository rules. Before tagging, `--tag-only`
  checks the version at the merged commit: `collection.json` or `adapter.json` `version` must equal
  the manifest version; for a catalog repo (`marketplace-directory.json` /
  `infrastructure-directory.json` / `filesystem-adapter-directory.json`) every entry that lists
  another repo in the manifest must carry that repo's manifest version as `current_version`. (The
  catalog repo's own tag is a repo-level counter, not any file's `directory_version`.)

## Release-delta manifest (the ONLY thing the agent produces)
```json
{
  "headline_tag": "c150",
  "repos": [
    { "name": "agent-index-core", "path": "../agent-index-core", "version": "3.28.0",
      "is_adapter": false, "in_listings": true }
  ],
  "push_order": ["agent-index-core", "agent-index-marketplace", "agent-index-marketplace-developer",
                 "agent-index-marketplace-library", "agent-index-resource-listings"],
  "dist_publish": true
}
```
`push_order` MUST end with `agent-index-resource-listings`. Only repos changed in the release belong
in `repos`/`push_order`; adapters are flagged `is_adapter:true` so the build+checksum step runs only
for them (no adapter steps when adapters are untouched).

## Stage -> test -> promote (distribution channels, 1.14.0)
`release-stage` takes the same manifest plus a channel name (`^[a-z0-9][a-z0-9-]{0,39}$`; branch
`channel/<name>`). Gates first, before any write: the name, no `.git/index.lock` in any repo (it
refuses rather than deleting a lock), an `origin` remote, a checked-out branch, and the same
preflight invocation `release-prep` uses (skip with `--skip-preflight` / `-SkipPreflight` only in an
emergency; it prints a loud warning). Then, per repo in `push_order` (catalogs last):

- **Already on `channel/<name>`** (iterating): show `git status --short` + diff stat, confirm,
  `git add -A`, commit `stage(<name>): <repo> v<version>`, `git push origin channel/<name>` --
  fast-forward, no force.
- **On any other branch, channel absent or already contained in it** (new candidate): confirm;
  `git checkout -B channel/<name>` (keeps working changes), add, commit, push with an explicit
  lease (a fast-forward).
- **On any other branch, channel holds staged commits not on it:**
  - no working changes: left as is (already staged, nothing new);
  - working changes: refused unless you type `REPLACE` (start a new candidate). The message gives
    the usual alternative, adding them to the candidate:
    `git stash; git checkout channel/<name>; git stash pop`, then re-run.
    `--yes` / `-Yes` never replaces.
- **No changes, nothing staged yet:** the branch is still pushed at `HEAD`, so the channel includes the repo.
- **Cleanup:** after each repo is pushed it is checked out again on the branch it started on (the
  default branch if it started on the channel). The staged commits live on `channel/<name>`;
  default branches are left as they were. `--stay-on-channel` / `-StayOnChannel` skips this. If a
  push fails, the script says which repo is left on the channel and how to go back.
- **Never tags. Never pushes the default branch.**

Then on the test org's admin install: create the org with the channel (or set "Distribution
channel" in `edit-org`), refresh clones, "publish our org updates". Iterate: `git checkout
channel/<name>` in the repos you're changing, edit, re-run stage. Untouched repos are left as is.

**Promote** when the candidate passes, per repo (code repos first, listings last): open a PR
`channel/<name>` -> default branch and merge it; run `release-push --tag-only`; then
`git checkout <default> && git pull && git branch -D channel/<name>`. Run `release-prep` before promoting if stage ran with
`--skip-preflight` or anything changed since.

`--yes` / `-Yes` answers every prompt with y. It exists for tests/CI only; never use it for a real
stage.

## Run (host-native; the agent never pushes)
```
# Windows
powershell -ExecutionPolicy Bypass -File lib\release\release-prep.ps1 -Manifest .agent-index\release-c150.json
powershell -ExecutionPolicy Bypass -File lib\release\release-push.ps1 -Manifest .agent-index\release-c150.json
powershell -ExecutionPolicy Bypass -File lib\release\release-push.ps1 -Manifest .agent-index\release-c150.json -TagOnly   # after the PR merges
powershell -ExecutionPolicy Bypass -File lib\release\release-stage.ps1 -Manifest .agent-index\release-c150.json -Channel dev-1   # stage mode
# macOS/Linux
bash lib/release/release-prep.sh .agent-index/release-c150.json
bash lib/release/release-push.sh .agent-index/release-c150.json
bash lib/release/release-push.sh .agent-index/release-c150.json --tag-only   # after the PR merges
bash lib/release/release-stage.sh .agent-index/release-c150.json --channel dev-1   # stage mode
```

**Python (bash scripts).** The `.sh` scripts source `_python.sh`, which finds a Python 3 that actually runs (`python3`, `py -3`, `python`) — on Windows `python3` is often the Store alias stub. On Windows the `.ps1` scripts need no Python at all.
