# lib/release -- committed release tooling (level-3)

Replaces the old pattern where the `release` task **generated** a bespoke `prep-<tag>`/`push-<tag>`
script pair every release (level 2 -- the release invariants were re-transcribed each time). The
prep/push logic now lives in committed, version-controlled scripts; the `release` task emits ONLY a
**release-delta manifest** (data) and surfaces these invocations.

## Files
- `release-prep.ps1` / `release-prep.sh` -- build+prep (NO git writes; safe to re-run): preflight
  hard gate per repo, adapter build+checksum (only repos flagged `is_adapter`), manifest
  `collection_version` restamp.
- `release-push.ps1` / `release-push.sh` -- the irreversible phase: **pre-push diff + integrity
  gate** (per repo: `git diff --stat`/full diff for operator review; integrity guard flags a lost
  `AIFS:FILE-END` sentinel vs HEAD, a text file with no trailing newline -- the torn-write signature
  that truncated create-org.md -- and a non-HTTPS `origin`), CHANGELOG date-stamp at push, then
  per-repo commit -> push -> tag `v<version>` in `push_order` (resource-listings LAST; an existing
  identical tag is left, a tag pointing elsewhere is NEVER moved), then the /shared/dist handoff note.

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

## Run (host-native; the agent never pushes)
```
# Windows
powershell -ExecutionPolicy Bypass -File lib\release\release-prep.ps1 -Manifest .agent-index\release-c150.json
powershell -ExecutionPolicy Bypass -File lib\release\release-push.ps1 -Manifest .agent-index\release-c150.json
# macOS/Linux
bash lib/release/release-prep.sh .agent-index/release-c150.json
bash lib/release/release-push.sh .agent-index/release-c150.json
```
