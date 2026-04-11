---
name: optimize
type: task
version: 1.0.0
collection: developer
description: Audits collection workflows for token efficiency — identifies deterministic steps that could be extracted into parameterized scripts, estimates savings, and generates the scripts.
stateful: false
produces_artifacts: true
produces_shared_artifacts: false
dependencies:
  skills: []
  tasks: []
external_dependencies: []
reads_from: null
writes_to: null
---

## About This Task

Collection workflows contain two kinds of steps: judgment steps where Claude's reasoning is the point (classify an email, write a summary, decide a project priority), and mechanical steps where Claude re-derives the same logic every run (read a JSON file and extract fields, validate a schema, compute a hash, write structured output to a known path, check MCP connectivity). Mechanical steps burn tokens on work that should be a script call.

This task reads a collection's workflows, classifies each step, estimates the token cost of mechanical work, and produces an optimization report. For each mechanical step it identifies, it explains why the step is mechanical, what a parameterized script replacement would look like, and the estimated token savings. The developer can then choose which optimizations to apply, and the task generates the scripts and rewrites the workflow steps to call them.

The result is a collection that spends tokens on reasoning — the work only Claude can do — and delegates everything else to deterministic scripts.

### Inputs

A path to the collection directory to audit. If not specified, Claude asks which collection to optimize.

Optionally:
- A specific task to audit (rather than the whole collection)
- `report-only` mode — produce the report but don't generate scripts
- `apply` mode — generate scripts and rewrite workflow steps (with developer approval at each step)

### Outputs

An optimization report showing:
- Per-task breakdown of judgment vs. mechanical steps
- Estimated token cost per mechanical step (rough, based on step complexity)
- Total estimated savings across all tasks
- Recommended script extractions with proposed interfaces

If `apply` mode is selected, also produces:
- Generated scripts in `/apps/` following the standard script conventions
- Rewritten workflow steps that call the scripts instead of inline reasoning

### Cadence & Triggers

On demand. Run when a collection is mature enough that its workflows are stable and optimization is worthwhile. Also useful during major version development when rethinking workflow structure.

---

## Workflow

### Step 1: Load the Collection

Read the collection directory. Parse `collection.json` to identify all API members. Read every task definition file (skills are not optimized — their reactive nature means most steps involve judgment).

Build an inventory of all task workflow steps across the collection.

**On success:** Proceed to Step 2 with the full step inventory.
**On failure:** Report "Cannot read collection at {path}" with the specific error and stop.

---

### Step 2: Classify Each Workflow Step

For every numbered step in every task workflow, classify it as one of:

**Mechanical** — The step meets ALL three criteria:
1. Inputs are fully determined by configuration or prior step outputs (no member judgment needed at runtime)
2. Logic is identical every run (no conditional reasoning based on content semantics)
3. Output format is fixed (structured data, not natural language)

Examples of mechanical steps:
- Read a JSON/YAML file from a known path and extract specific fields
- Validate that a file or data structure matches a known schema
- Compute a hash, checksum, or other deterministic transformation
- Write a structured block (JSON, YAML, frontmatter) to a known location
- Check whether an MCP tool is available or authenticated
- List files in a directory and filter by extension or name pattern
- Parse and merge configuration from multiple known files
- Perform date arithmetic (e.g., "is the EOL date within 90 days?")
- Format data for output (e.g., build a markdown table from structured data)
- Copy or move files between known paths

**Judgment** — The step requires Claude's reasoning:
- Interpreting natural language input from the member
- Making classification decisions based on content meaning
- Writing summaries, descriptions, or other natural language output
- Deciding between courses of action based on ambiguous signals
- Conducting conversations or asking follow-up questions
- Evaluating quality or completeness of member-provided content

**Gray area** — The step appears mechanical but has aspects that may require judgment:
- Reading configuration and "determining which features are enabled" (mechanical if it's a boolean check, judgment if it requires interpretation)
- "Check if the project is stale" (mechanical if based on date thresholds, judgment if based on activity patterns)
- "Validate the brief is complete" (mechanical if checking required fields, judgment if evaluating content quality)

For gray-area steps, classify as "possibly mechanical" and note what would need to be true for the step to be fully mechanical.

**On success:** Proceed to Step 3 with the classification map.
**On failure or ambiguity:** Record uncertain classifications and proceed — the developer will review.

---

### Step 3: Estimate Token Cost

For each mechanical step, estimate the token cost per run:

**Low cost (~100-300 tokens):** Simple file reads, single-field extractions, boolean checks, path existence checks.

**Medium cost (~300-800 tokens):** Multi-field extraction with validation, schema checks, structured data assembly, multi-file reads with merging.

**High cost (~800-2000+ tokens):** Complex data transformations, multi-step validation chains, large file parsing with conditional extraction, building reports from multiple data sources.

Calculate per-task totals and collection-wide totals. These are rough estimates — the value is relative (which steps cost the most), not absolute.

**On success:** Proceed to Step 4.
**On failure:** Note that estimates are unavailable and proceed with qualitative analysis only.

---

### Step 4: Design Script Interfaces

For each mechanical step (and optionally, gray-area steps the developer approves), design a parameterized script interface:

**Script name:** Derived from the step's function. Use the collection name as a namespace prefix if the script is collection-specific. Example: `projects-load-manifest.py`, `email-triage-validate-config.py`.

**Input parameters:** Map directly from the workflow step's inputs. Every value that comes from configuration or prior steps becomes a CLI argument. Use the flag conventions from the authoring guide:
- `--input-path` / `--output-path` for file locations
- `--config-file` for configuration input
- `--dry-run` for preview mode
- `--format` for output format selection (json, yaml, text)

**Output contract:** Define what the script writes to stdout. Prefer structured JSON output that Claude can parse in one step. Include a `status` field (`success`, `error`, `skipped`) and a `data` field with the payload.

**Error handling:** Define exit codes. `0` for success, `1` for expected errors (file not found, validation failed), `2` for unexpected errors (crash, dependency missing).

**Consolidation opportunities:** If multiple mechanical steps in the same task (or across tasks) do similar work, design a single script that handles all of them. Example: if three tasks all start by reading `project-manifest.json` and extracting project metadata, that's one script with a `--fields` parameter, not three scripts.

Present the proposed script interfaces to the developer for review.

**On success:** Proceed to Step 5 with approved interfaces.
**On failure or developer rejection:** Revise interfaces based on feedback and re-present.

---

### Step 5: Generate the Report

Produce the optimization report:

**Summary:**
```
Optimization Report: {collection-name}
Tasks audited: {N}
Total workflow steps: {N}
  Mechanical: {N} ({percent}%)
  Judgment: {N} ({percent}%)
  Gray area: {N} ({percent}%)
Estimated token savings per run: ~{N} tokens ({percent}% of mechanical step cost)
Recommended scripts: {N}
```

**Per-task breakdown:** For each task, list every step with its classification, estimated cost, and (for mechanical steps) the proposed script that would replace it.

**Consolidation opportunities:** List scripts that serve multiple tasks, with the tasks and steps they cover.

**Gray-area analysis:** For each gray-area step, explain what makes it ambiguous and what the developer should consider.

**Implementation priority:** Rank the proposed scripts by estimated token savings (highest first). This helps the developer prioritize if they don't want to implement everything at once.

If mode is `report-only`, present the report and stop.

**On success:** If mode is `apply`, proceed to Step 6. Otherwise, task complete.

---

### Step 6: Generate Scripts (apply mode)

For each approved script:

1. Generate the script file following authoring guide conventions:
   - Shebang line (`#!/usr/bin/env python3` or `#!/usr/bin/env node`)
   - Dependency check on import
   - CLI argument parsing with `--help`
   - `--dry-run` support
   - Structured JSON output to stdout
   - Clear exit codes

2. Write the script to `/apps/{script-name}`. Create the `/apps/` directory if it doesn't exist.

3. Generate or update `requirements.txt` (Python) or `package.json` (Node) in `/apps/` with pinned dependencies.

Confirm each script with the developer before writing.

**On success:** Proceed to Step 7.
**On failure:** Report which scripts could not be generated and why.

---

### Step 7: Rewrite Workflow Steps (apply mode)

For each task with mechanical steps being replaced:

1. Read the current task definition file.
2. For each mechanical step being replaced, rewrite the step to call the generated script instead of containing inline reasoning. The rewritten step should:
   - Name the script and its arguments explicitly
   - Show the exact command with `{variable}` placeholders for configuration values
   - Describe how to parse the script's JSON output
   - Preserve the existing on-success and on-failure handling (or improve it using the script's exit codes)
3. Present the rewritten step alongside the original for developer review.
4. On approval, write the updated task definition file.

Example of a rewritten step:

```markdown
### Step 2: Load Project Manifest

Run the project manifest loader:

\`\`\`bash
python {apps_path}/projects-load-manifest.py \
    --manifest-path "{shared_projects_path}/projects-manifest.json" \
    --format json
\`\`\`

Parse the JSON output. The `data` field contains the manifest entries array.
If exit code is 1, the manifest file was not found — inform the member and offer
to create a new project instead.
```

**On success:** Proceed to Step 8.
**On failure:** Report which rewrites could not be applied and why. Leave the original steps intact.

---

### Step 8: Post-Optimization Validation

After all scripts are generated and workflow steps rewritten:

1. Verify every generated script is syntactically valid (run with `--help` to confirm it parses).
2. Verify every rewritten workflow step references a script that exists in `/apps/`.
3. Verify no mechanical step was accidentally left unrewritten if its script was generated.
4. Note that the collection version should be bumped (this is a MINOR change — new scripts, modified workflows, no breaking interface changes).

Present a summary: scripts generated, steps rewritten, estimated savings, next steps (version bump, testing).

**On success:** Task complete.
**On failure:** Report validation issues.

---

## Directives

### Behavior

Be conservative in classification. When in doubt, classify a step as gray area rather than mechanical. False positives (calling something mechanical when it requires judgment) create scripts that silently produce wrong results. False negatives (calling something judgment when it's mechanical) just leave tokens on the table — a missed optimization, not a correctness bug.

When designing scripts, prefer fewer consolidated scripts over many single-purpose ones. A collection with 15 tiny scripts is harder to maintain than one with 4 well-designed scripts that each handle a family of related operations.

When rewriting workflow steps, preserve the task's narrative flow. The step should still read as a coherent instruction to Claude, not as a bare script invocation. Claude needs context to handle errors and edge cases even when the core logic is in a script.

### Output Standards

The optimization report is delivered in chat. Scripts are written to the collection's `/apps/` directory. Rewritten task files replace the originals in `/api/`.

Generated scripts must follow the authoring guide's script conventions: shebang, dependency check, credential path flags, `--dry-run`, exit codes, structured output.

### Constraints

- Never classify a judgment step as mechanical. When uncertain, use gray area.
- Never rewrite a workflow step without developer approval.
- Never modify skill files — only task workflows are candidates for optimization.
- Never generate scripts that handle credentials differently than the authoring guide prescribes.
- Never remove on-success/on-failure handling from rewritten steps — adapt it to use script exit codes.
- Always preserve the original workflow step (in a comment or backup) when rewriting, so the developer can compare.

### Edge Cases

If a collection has no tasks (skills only), report that there are no optimization candidates — skills are inherently reactive and judgment-heavy.

If every step in every task is already a script call, report that the collection is already optimized.

If a task has only one mechanical step and the estimated savings are trivial (<200 tokens), classify it as a note rather than a recommendation — the maintenance cost of a script may not be worth the savings.

If a gray-area step could be made fully mechanical by splitting it into two steps (a mechanical data-loading step and a judgment interpretation step), recommend the split as an optimization strategy.

If the collection uses the iterative learning pattern, the correction-checking step is typically mechanical (read corrections file, match against current input) while the classification step is judgment. Recommend extracting the correction checker as a script that pre-applies learned rules before Claude does semantic classification.
