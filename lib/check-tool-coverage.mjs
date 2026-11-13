#!/usr/bin/env node
// check-tool-coverage.mjs — preflight Check 18: tool and argument coverage (adapter repos).
//
// Usage: node check-tool-coverage.mjs <adapter-repo-path>
// Prints one finding per line, prefixed "ERROR " or "WARN " (preflight-cli.sh turns
// them into err/warn), and "INFO " lines for the log. Always exits 0 unless it
// cannot run at all (exit 2).
//
// Source of truth is the code: every `case 'aifs_*'` in routeToolCall (src/exec.mjs)
// is a tool the executor accepts, and each tool's top-level `args.X` reads are the
// arguments it accepts. Compared against:
//   1. the wrapper --help   (bash src/aifs-exec.sh --help)           -> ERROR
//   2. the executor --help  (node dist/aifs-exec.bundle.js --help,
//                            its `tools` list and `arguments` map)   -> ERROR
//   3. SPEC.md in a sibling agent-index-filesystem clone (### aifs_X) -> WARN
// The two --help surfaces are what an agent reads at runtime; SPEC.md is a separate
// repo with its own release (DC-001 decisions, 2026-10-11).

import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname, resolve } from 'node:path';

const repoArg = process.argv[2];
if (!repoArg || !existsSync(repoArg)) {
  console.log('ERROR usage: node check-tool-coverage.mjs <adapter-repo-path>');
  process.exit(2);
}
const repo = resolve(repoArg);
const out = [];
const error = (m) => out.push(`ERROR ${m}`);
const warn = (m) => out.push(`WARN ${m}`);
const info = (m) => out.push(`INFO ${m}`);

// ── 1. What the executor accepts (routeToolCall) ─────────────────────────────
const execPath = join(repo, 'src', 'exec.mjs');
if (!existsSync(execPath)) {
  warn('src/exec.mjs not found; tool/argument coverage not checked');
  finish();
}
const src = readFileSync(execPath, 'utf8');
const start = src.search(/function\s+routeToolCall\s*\(/);
if (start < 0) {
  warn('routeToolCall not found in src/exec.mjs; tool/argument coverage not checked');
  finish();
}
// The function body ends at the first line that is exactly "}" after its start.
const endRel = src.slice(start).search(/\n\}\s*\n/);
const body = endRel < 0 ? src.slice(start) : src.slice(start, start + endRel);

// Split into case segments. Consecutive labels with no code between them share the next body.
const labelRe = /case\s+['"](aifs_[a-z0-9_]+)['"]\s*:/g;
const labels = [];
let m;
while ((m = labelRe.exec(body))) labels.push({ tool: m[1], at: m.index, end: labelRe.lastIndex });
const defaultAt = body.search(/\bdefault\s*:/);
const accepted = new Map(); // tool -> Set(args)
let pending = [];
for (let i = 0; i < labels.length; i++) {
  const segEnd = i + 1 < labels.length ? labels[i + 1].at : (defaultAt > 0 ? defaultAt : body.length);
  const seg = body.slice(labels[i].end, segEnd);
  pending.push(labels[i].tool);
  if (seg.trim() === '') continue; // fall-through label
  const argsRead = new Set();
  // args.X / args?.X (only the top-level property: args.paths.length -> "paths")
  for (const a of seg.matchAll(/\bargs\??\.([A-Za-z_][A-Za-z0-9_]*)/g)) argsRead.add(a[1]);
  // args['X'] / args["X"]
  for (const a of seg.matchAll(/\bargs\[\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]\s*\]/g)) argsRead.add(a[1]);
  // Object.prototype.hasOwnProperty.call(args, 'X') / 'X' in args
  for (const a of seg.matchAll(/hasOwnProperty\.call\(\s*args\s*,\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]\s*\)/g)) argsRead.add(a[1]);
  for (const a of seg.matchAll(/['"]([A-Za-z_][A-Za-z0-9_]*)['"]\s+in\s+args\b/g)) argsRead.add(a[1]);
  for (const t of pending) accepted.set(t, new Set(argsRead));
  pending = [];
}
for (const t of pending) accepted.set(t, new Set());
if (accepted.size === 0) {
  warn('no `case \'aifs_*\'` labels found in routeToolCall; tool/argument coverage not checked');
  finish();
}
const tools = [...accepted.keys()];
info(`routeToolCall accepts ${tools.length} tools`);

const hasWord = (text, word) => new RegExp(`(^|[^A-Za-z0-9_])${word}([^A-Za-z0-9_]|$)`).test(text);

// ── 2. Wrapper --help ────────────────────────────────────────────────────────
const wrapper = join(repo, 'src', 'aifs-exec.sh');
if (!existsSync(wrapper)) {
  error('src/aifs-exec.sh not found; the wrapper --help cannot document the tools');
} else {
  let help = '';
  try {
    help = execFileSync('bash', [wrapper, '--help'], { cwd: repo, encoding: 'utf8', timeout: 20000, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    help = (e.stdout || '').toString();
    if (!help) error(`bash src/aifs-exec.sh --help failed: ${(e.message || '').split('\n')[0]}`);
  }
  if (help) {
    // A tool's block starts on an indented line beginning with its name and runs
    // until the next such line or a blank line.
    const lines = help.split('\n');
    const blocks = new Map();
    let cur = null;
    for (const line of lines) {
      const s = /^\s+(aifs_[a-z0-9_]+)\b/.exec(line);
      if (s) { cur = s[1]; blocks.set(cur, line + '\n'); continue; }
      if (line.trim() === '') { cur = null; continue; }
      if (cur && /^\s/.test(line)) blocks.set(cur, blocks.get(cur) + line + '\n');
      else cur = null;
    }
    const missingTools = [];
    for (const t of tools) {
      if (!hasWord(help, t)) { missingTools.push(t); continue; }
      // Count only arguments written in the block's {...} signature, not words in the description
      // ("Check path existence" must not count as documenting `path`).
      const sigText = ((blocks.get(t) || '').match(/\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/g) || []).join(' ');
      for (const a of accepted.get(t)) {
        if (!hasWord(sigText, a)) error(`wrapper --help: ${t} does not document argument "${a}"`);
      }
    }
    if (missingTools.length) error(`wrapper --help lists ${tools.length - missingTools.length} of ${tools.length} tools; missing: ${missingTools.join(', ')}`);
  }
}

// ── 3. Executor JSON --help ──────────────────────────────────────────────────
const bundle = join(repo, 'dist', 'aifs-exec.bundle.js');
if (!existsSync(bundle)) {
  info('dist/aifs-exec.bundle.js missing; executor --help not checked (Check 14 reports the missing bundle)');
} else {
  let j = null;
  try {
    const raw = execFileSync(process.execPath, [bundle, '--help'], { cwd: repo, encoding: 'utf8', timeout: 20000, stdio: ['ignore', 'pipe', 'pipe'] });
    j = JSON.parse(raw);
  } catch (e) {
    error(`node dist/aifs-exec.bundle.js --help did not print JSON: ${(e.message || '').split('\n')[0]}`);
  }
  if (j) {
    const listed = new Set(Array.isArray(j.tools) ? j.tools : []);
    const missing = tools.filter((t) => !listed.has(t));
    if (missing.length) error(`executor --help "tools" lists ${tools.length - missing.length} of ${tools.length}; missing: ${missing.join(', ')}`);
    if (!j.arguments || typeof j.arguments !== 'object') {
      error('executor --help has no "arguments" map, so no tool\'s arguments are documented');
    } else {
      for (const t of tools) {
        const sig = j.arguments[t];
        if (typeof sig !== 'string') { error(`executor --help "arguments" has no entry for ${t}`); continue; }
        for (const a of accepted.get(t)) {
          if (!hasWord(sig, a)) error(`executor --help: arguments.${t} does not document "${a}"`);
        }
      }
    }
  }
}

// ── 4. SPEC.md (sibling agent-index-filesystem clone) ────────────────────────
const spec = resolve(dirname(resolve(repo)), 'agent-index-filesystem', 'SPEC.md');
if (!existsSync(spec)) {
  warn(`SPEC.md not checked: no sibling clone at ${spec}`);
} else {
  const text = readFileSync(spec, 'utf8');
  const missing = tools.filter((t) => !new RegExp(`^###\\s+${t}\\s*$`, 'm').test(text));
  if (missing.length) warn(`SPEC.md has no "### <tool>" section for: ${missing.join(', ')}`);
}

finish();

function finish() {
  for (const line of out) console.log(line);
  process.exit(0);
}
