#!/usr/bin/env node
// check-docs.mjs — preflight Checks 19, 20 and 21 (DC-001 PR 2).
//
// Usage: node check-docs.mjs <check> <repo-path>      check = 19 | 20 | 21
// Prints one finding per line, prefixed "ERROR ", "WARN " or "INFO ". Exits 0
// unless it cannot run at all (exit 2). preflight-cli.sh turns the lines into
// err/warn/log.
//
// 19  Citation integrity (all repos). The citation rule adopted on CI-013 is
//     {doc} § "Exact Heading", with no line numbers.
//       - Every `{doc}.md § "Heading"` in *.md, *.json and *.sh must match a heading in
//         that document. The document is looked up in this repo first, then in sibling
//         agent-index-* clones; CLAUDE.md maps to .claude/CLAUDE.md.template.
//         Missing heading: ERROR. Document not found anywhere: WARNING.
//       - `{doc}.md line N` / `{doc}.md lines N` / `{doc}.md:N`: ERROR.
//       - CHANGELOG.md is skipped: it is a historical record.
// 20  No duplicate headings (core only). No heading may appear in both
//     .claude/CLAUDE.md.template and runtime-reference.md or admin-distribution.md,
//     so each rule has one home. ERROR.
// 21  api[] entries (collections). A plain-string entry can't carry triggers: WARNING. An object entry
//     with no "triggers" array (missing, or not an array): WARNING.
//     A trigger whose `capability` isn't its entry's `name`: ERROR.

import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, resolve, dirname, basename, relative } from 'node:path';

const [check, repoArg] = process.argv.slice(2);
if (!['19', '20', '21'].includes(check) || !repoArg || !existsSync(repoArg)) {
  console.log('ERROR usage: node check-docs.mjs <19|20|21> <repo-path>');
  process.exit(2);
}
const repo = resolve(repoArg);
const out = [];
const error = (m) => out.push(`ERROR ${m}`);
const warn = (m) => out.push(`WARN ${m}`);
const info = (m) => out.push(`INFO ${m}`);

const SKIP_DIRS = new Set(['.git', 'node_modules', 'dist']);
function walk(dir, exts, acc = []) {
  let entries;
  try { entries = readdirSync(dir); } catch { return acc; }
  for (const name of entries) {
    if (SKIP_DIRS.has(name)) continue;
    const p = join(dir, name);
    let st;
    try { st = statSync(p); } catch { continue; }
    if (st.isDirectory()) walk(p, exts, acc);
    else if (exts.some((e) => name.endsWith(e))) acc.push(p);
  }
  return acc;
}

// Heading text as written, plus a normalized form that ignores `code` and **bold** markers
// and trailing whitespace, so `## \`aifs_read\`` matches a citation of "aifs_read".
const norm = (h) => h.replace(/[`*]/g, '').replace(/\s+/g, ' ').trim();
function headingsOf(file) {
  const set = new Set();
  let inFence = false;
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    if (/^\s*(```|~~~)/.test(line)) { inFence = !inFence; continue; }
    if (inFence) continue;
    const m = /^#{1,6}\s+(.*?)\s*#*\s*$/.exec(line);
    if (m) { set.add(m[1]); set.add(norm(m[1])); }
  }
  return set;
}

if (check === '19') checkCitations();
else if (check === '20') checkDuplicateHeadings();
else checkApiEntries();
for (const line of out) console.log(line);
process.exit(0);

// ── 19 ─────────────────────────────────────────────────────────────────────
function checkCitations() {
  const parent = dirname(repo);
  const siblings = readdirSync(parent)
    .filter((n) => n.startsWith('agent-index-') && join(parent, n) !== repo)
    .map((n) => join(parent, n))
    .filter((p) => { try { return statSync(p).isDirectory(); } catch { return false; } });

  // Resolve a cited document name to a file: this repo first, then siblings.
  const docCache = new Map();
  function findDoc(doc) {
    if (docCache.has(doc)) return docCache.get(doc);
    const base = basename(doc);
    const candidates = base === 'CLAUDE.md'
      ? [['.claude', 'CLAUDE.md.template'], ['CLAUDE.md']]
      : [[doc], [base]];
    let found = null;
    for (const root of [repo, ...siblings]) {
      for (const parts of candidates) {
        const p = join(root, ...parts);
        if (existsSync(p)) { found = p; break; }
      }
      if (!found && base !== 'CLAUDE.md') {
        // a document at any depth in this root (e.g. internal/conventions.md)
        const hit = walk(root, ['.md']).find((f) => basename(f) === base);
        if (hit) found = hit;
      }
      if (found) break;
    }
    docCache.set(doc, found);
    return found;
  }

  const files = walk(repo, ['.md', '.json', '.sh']).filter((f) => basename(f) !== 'CHANGELOG.md');
  // {doc}.md § "Heading"   (straight or curly quotes; the doc may be in backticks)
  const citeRe = /`?([A-Za-z0-9_./-]+\.md)`?\s*§\s*["“]([^"”\n]+)["”]/g;
  // {doc}.md line N / lines N / :N
  const lineRe = /`?([A-Za-z0-9_./-]+\.md)`?(?::(\d+)\b|\s+lines?\s+(\d+))/g;
  const headCache = new Map();
  let resolved = 0, broken = 0;
  const unknownDocs = new Set();
  for (const f of files) {
    const rel = relative(repo, f);
    let text = readFileSync(f, 'utf8');
    // In .json files a citation's quotes are escaped (§ \"Heading\"): unescape so it matches.
    if (f.endsWith('.json')) text = text.replace(/\\"/g, '"');
    const lines = text.split('\n');
    lines.forEach((line, i) => {
      for (const m of line.matchAll(citeRe)) {
        const [, doc, heading] = m;
        // Docs that explain the rule use a placeholder ("Exact Heading", "Heading", "…").
        if (/^(exact )?heading$|^(\.\.\.|…)$|[{}]/i.test(heading.trim())) continue;
        const file = findDoc(doc);
        if (!file) { unknownDocs.add(doc); continue; }
        if (!headCache.has(file)) headCache.set(file, headingsOf(file));
        const hs = headCache.get(file);
        if (hs.has(heading) || hs.has(norm(heading))) resolved++;
        else { broken++; error(`${rel}:${i + 1}: ${doc} § "${heading}" — no such heading in ${relative(dirname(repo), file)}`); }
      }
      for (const m of line.matchAll(lineRe)) {
        const n = m[2] || m[3];
        error(`${rel}:${i + 1}: line-number citation "${m[0].replace(/`/g, '')}" — cite ${m[1]} § "Heading" instead (line numbers move)`);
      }
    });
  }
  for (const d of unknownDocs) warn(`cited document ${d} not found in this repo or a sibling agent-index-* clone; its citations were not checked`);
  info(`${resolved} citation(s) resolve, ${broken} broken`);
}

// ── 20 ─────────────────────────────────────────────────────────────────────
function checkDuplicateHeadings() {
  const tpl = join(repo, '.claude', 'CLAUDE.md.template');
  const refs = ['runtime-reference.md', 'admin-distribution.md'].map((n) => join(repo, n)).filter(existsSync);
  if (!existsSync(tpl) || refs.length === 0) { info('skipped: not core (needs .claude/CLAUDE.md.template and a reference document)'); return; }
  const tplHeads = [...headingsOf(tpl)].filter((h) => h === norm(h));
  let dups = 0;
  for (const r of refs) {
    const rh = headingsOf(r);
    for (const h of tplHeads) {
      if (rh.has(h)) { dups++; error(`heading "${h}" is in both .claude/CLAUDE.md.template and ${basename(r)} — keep one home for the rule`); }
    }
  }
  if (!dups) info('no heading appears in both CLAUDE.md.template and the reference documents');
}

// ── 21 ─────────────────────────────────────────────────────────────────────
function checkApiEntries() {
  const cj = join(repo, 'collection.json');
  if (!existsSync(cj)) { info('skipped: no collection.json'); return; }
  let api;
  try { api = JSON.parse(readFileSync(cj, 'utf8')).api; } catch (e) { error(`collection.json does not parse: ${e.message}`); return; }
  if (!Array.isArray(api)) { info('collection.json has no api[] array'); return; }
  const plain = api.filter((a) => typeof a === 'string');
  if (plain.length) warn(`collection.json api[] has ${plain.length} plain-string entr${plain.length === 1 ? 'y' : 'ies'}, which can't carry triggers: ${plain.join(', ')} (use {"name": ..., "triggers": [...]})`);
  for (const a of api) {
    if (!a || typeof a !== 'object') continue;
    if (!('triggers' in a)) {
      warn(`collection.json api[] entry "${a.name}" has no "triggers" array; add "triggers": [] if it isn't meant to be asked for by phrase`);
      continue;
    }
    if (!Array.isArray(a.triggers)) {
      warn(`collection.json api[] entry "${a.name}": "triggers" is not an array; use [] or a list of trigger objects`);
      continue;
    }
    for (const t of a.triggers) {
      if (t && typeof t === 'object' && 'capability' in t && t.capability !== a.name) {
        error(`collection.json api[] "${a.name}": trigger "${t.phrase}" names capability "${t.capability}" — a trigger must route to its own entry`);
      }
    }
  }
}
