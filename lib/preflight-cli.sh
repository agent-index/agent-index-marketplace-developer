#!/usr/bin/env bash
# preflight-cli.sh — Mechanical preflight checks for a collection, in pure bash.
#
# Usage:  bash preflight-cli.sh --collection <path> [--quiet]
# Exits:  0 = pass (warnings OK), 1 = errors, 2 = invocation error
#
# No external dependencies beyond standard POSIX tools (grep, sed, awk, find, tr).
# Runs the structural subset of @ai:preflight that doesn't need agent reasoning.

set -u

QUIET=0
COLL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --collection) COLL="$2"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$COLL" ]] || [[ ! -d "$COLL" ]]; then
    echo "Usage: bash preflight-cli.sh --collection <path> [--quiet]" >&2
    exit 2
fi

COLL="$(cd "$COLL" && pwd)"
if [[ ! -f "$COLL/collection.json" ]]; then
    echo "✗ collection.json not found at $COLL" >&2
    exit 2
fi

# ── Parse collection.json (no jq) ───────────────────────────────────────────
get_json_field() {
    # Extract a top-level string field's value from a JSON file. Naïve but
    # works for our well-formed files. Returns first match.
    local file="$1"
    local field="$2"
    grep -m1 "\"$field\":" "$file" | sed 's/.*"'"$field"'":[[:space:]]*"\([^"]*\)".*/\1/'
}

COLL_NAME=$(get_json_field "$COLL/collection.json" name)
COLL_VERSION=$(get_json_field "$COLL/collection.json" version)

if [[ -z "$COLL_VERSION" ]]; then
    echo "✗ could not parse version from $COLL/collection.json" >&2
    exit 2
fi

log() { [[ "$QUIET" -eq 0 ]] && echo "$@"; }

ERRORS=()
WARNINGS=()
err() { ERRORS+=("$1"); }
warn() { WARNINGS+=("$1"); }

log "preflight: $COLL_NAME v$COLL_VERSION at $COLL"
log ""

# ── Check 1: frontmatter version <-> manifest version ───────────────────────
log "Check 1: .md frontmatter version <-> *-manifest.json version"
e1=${#ERRORS[@]}
if [[ -d "$COLL/api" ]]; then
    for md in "$COLL"/api/*.md; do
        [[ -f "$md" ]] || continue
        base=$(basename "$md" .md)
        case "$base" in *-setup|*-manifest) continue ;; esac
        manifest="$COLL/api/${base}-manifest.json"
        [[ -f "$manifest" ]] || continue
        md_v=$(grep -m1 '^version:' "$md" | sed 's/version:[[:space:]]*//' | tr -d ' \r')
        if [[ -z "$md_v" ]]; then
            err "  $base.md: no version field in frontmatter"
            continue
        fi
        # Get manifest version (skip collection_version)
        mf_v=$(grep '"version":' "$manifest" | grep -v collection_version | head -1 | sed 's/.*"version":[[:space:]]*"\([^"]*\)".*/\1/')
        if [[ "$md_v" != "$mf_v" ]]; then
            err "  $base: .md frontmatter version=$md_v but manifest.json version=$mf_v"
        fi
    done
fi
log "  errors: $(( ${#ERRORS[@]} - e1 ))"

# ── Check 2: manifest collection_version <-> collection.json version ────────
log "Check 2: *-manifest.json collection_version <-> collection.json version ($COLL_VERSION)"
e2=${#ERRORS[@]}
if [[ -d "$COLL/api" ]]; then
    for mf in "$COLL"/api/*-manifest.json; do
        [[ -f "$mf" ]] || continue
        cv=$(get_json_field "$mf" collection_version)
        if [[ "$cv" != "$COLL_VERSION" ]]; then
            err "  $(basename "$mf"): collection_version=$cv but collection.json version=$COLL_VERSION"
        fi
    done
fi
log "  errors: $(( ${#ERRORS[@]} - e2 ))"

# ── Check 3: CHANGELOG top entry matches collection.json version ────────────
log "Check 3: CHANGELOG top entry matches collection.json version"
e3=${#ERRORS[@]}
if [[ -f "$COLL/CHANGELOG.md" ]]; then
    # First `## [x.y.z]` entry
    top=$(grep -m1 '^##[[:space:]]*\[' "$COLL/CHANGELOG.md" | sed 's/^##[[:space:]]*\[\([^]]*\)\].*/\1/')
    if [[ -z "$top" ]]; then
        warn "  CHANGELOG.md: no [version]-shaped top entry"
    elif [[ "$top" != "$COLL_VERSION" ]]; then
        err "  CHANGELOG.md top entry is [$top] but collection.json version=$COLL_VERSION"
    fi
else
    warn "  CHANGELOG.md not found"
fi
log "  errors: $(( ${#ERRORS[@]} - e3 ))"

# ── Check 4: *.sh files have LF line endings ────────────────────────────────
log "Check 4: *.sh files have LF line endings (no CRLF)"
e4=${#ERRORS[@]}
while IFS= read -r -d '' f; do
    # Look for CR (0x0D) in the file
    if grep -q $'\r' "$f"; then
        err "  $(realpath --relative-to="$COLL" "$f"): contains CRLF"
    fi
done < <(find "$COLL" -name '*.sh' -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -print0)
log "  errors: $(( ${#ERRORS[@]} - e4 ))"

# ── Check 5: *.json files parse cleanly (weak — checks balanced braces) ─────
log "Check 5: *.json files have balanced braces"
e5=${#ERRORS[@]}
while IFS= read -r -d '' f; do
    opens=$(grep -o '{' "$f" | wc -l)
    closes=$(grep -o '}' "$f" | wc -l)
    if [[ "$opens" != "$closes" ]]; then
        err "  $(realpath --relative-to="$COLL" "$f"): unbalanced braces (opens=$opens, closes=$closes)"
    fi
    # Last non-empty char should be } or ]
    lastchar=$(tail -c 100 "$f" | tr -d '[:space:]' | tail -c 1)
    case "$lastchar" in
        '}'|']') ;;
        *) err "  $(realpath --relative-to="$COLL" "$f"): doesn't end with } or ] (last char: '$lastchar')" ;;
    esac
done < <(find "$COLL" -name '*.json' -not -path '*/node_modules/*' -not -path '*/.git/*' -print0)
log "  errors: $(( ${#ERRORS[@]} - e5 ))"

# ── Check 6: mid-word truncation heuristic for *.md files ───────────────────
log "Check 6: *.md mid-word truncation heuristic"
w6=${#WARNINGS[@]}
while IFS= read -r -d '' f; do
    # Last 40 chars, stripping trailing whitespace
    tail40=$(tail -c 200 "$f" | sed 's/[[:space:]]*$//' | tail -c 40)
    lastchar=$(echo -n "$tail40" | tail -c 1)
    # Suspicious: alphanumeric tail with no terminal punctuation
    if [[ "$tail40" =~ [a-zA-Z]{4,}$ ]] && [[ ! "$lastchar" =~ [.!?:\;\`\"\'\)\]\}\>\-] ]]; then
        rel=$(realpath --relative-to="$COLL" "$f")
        warn "  $rel: ends mid-word — last chars: \"$tail40\""
    fi
done < <(find "$COLL" -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*' -print0)
log "  warnings: $(( ${#WARNINGS[@]} - w6 ))"

# ── Check 7: JS-integrity heuristic for *.js files (added in v1.3.1) ────────
# Catches the "validate.js debris" corruption class: a file ends cleanly at one
# point and then has trailing debris (duplicate function definitions, a second
# module.exports, stray prose fragments) past the apparent end. Surfaces as:
#   - more than one `module.exports = ` line
#   - duplicate top-level `function foo(...)` declarations
#   - content after the last `module.exports` that isn't whitespace or a closing brace
log "Check 7: *.js JS-integrity heuristic"
e7=${#ERRORS[@]}
while IFS= read -r -d '' f; do
    # Count module.exports = lines in THIS file only (pipe avoids grep -c multi-file output)
    me_count=$(grep '^module\.exports\s*=' "$f" 2>/dev/null | wc -l | tr -d ' ')
    me_count=${me_count:-0}
    if [[ "$me_count" -gt 1 ]]; then
        rel=$(realpath --relative-to="$COLL" "$f")
        err "  $rel: $me_count top-level 'module.exports =' lines (suspected debris from a botched write — file may have content past its apparent end)"
        continue
    fi

    # Duplicate top-level function declarations (function foo(...))
    dup_fns=$(grep -E '^function [a-zA-Z_$][a-zA-Z0-9_$]*\s*\(' "$f" 2>/dev/null | sort | uniq -d)
    if [[ -n "$dup_fns" ]]; then
        rel=$(realpath --relative-to="$COLL" "$f")
        first_dup=$(echo "$dup_fns" | head -1)
        err "  $rel: duplicate top-level function declaration ($first_dup) — suspected debris"
        continue
    fi
done < <(find "$COLL" -name '*.js' -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -print0)
log "  errors: $(( ${#ERRORS[@]} - e7 ))"

# ── Check 8: inherit:false spec vs adapter contract version (added in v1.4.0) ─
# Catches forward-compat regressions: spec emits `inherit: false` but the org's
# adapter declares contract_version < 2.0.0 and silently ignores the field.
# Share applies with default semantics rather than override — degraded but not
# failing. Warning-level so forward-compatible specs aren't blocked.
#
# IMPORTANT: reads adapter CONTRACT version, NOT adapter PACKAGE version.
# `contract_version` (filesystem-contract level, e.g. 2.0.0) and
# `adapter_version` (package version, e.g. 2.3.0) are different surfaces;
# they happen to share a major today but are conceptually distinct.
#
# Resolution: ADAPTER_CONTRACT_OVERRIDE env var overrides anything; otherwise
# search common install layouts; skip-with-notice if nothing found.
log "Check 8: inherit:false spec vs adapter contract_version"
w8=${#WARNINGS[@]}
adapter_contract=""

if [[ -n "${ADAPTER_CONTRACT_OVERRIDE:-}" ]]; then
    adapter_contract="$ADAPTER_CONTRACT_OVERRIDE"
fi

if [[ -z "$adapter_contract" ]]; then
    for candidate in \
        "$COLL/../mcp-servers/filesystem/adapter.json" \
        "$COLL/../../mcp-servers/filesystem/adapter.json" \
        "${AGENT_INDEX_INSTALL_DIR:-}/mcp-servers/filesystem/adapter.json"
    do
        if [[ -n "$candidate" ]] && [[ -f "$candidate" ]]; then
            adapter_contract=$(grep -oE '"contract_version":[[:space:]]*"[^"]+"' "$candidate" 2>/dev/null \
                | head -1 \
                | sed 's/.*"contract_version":[[:space:]]*"\([^"]*\)".*/\1/')
            if [[ -n "$adapter_contract" ]]; then break; fi
        fi
    done
fi

if [[ -z "$adapter_contract" ]]; then
    log "  skipped: no adapter contract_version found (preflight may be running outside an install context — set ADAPTER_CONTRACT_OVERRIDE env var to force a value)"
else
    adapter_major=$(echo "$adapter_contract" | cut -d. -f1)
    log "  adapter contract_version: $adapter_contract (major: $adapter_major)"

    if [[ "$adapter_major" -lt 2 ]]; then
        while IFS= read -r -d '' f; do
            line=$(grep -nE '"inherit"[[:space:]]*:[[:space:]]*false|^[[:space:]]*inherit:[[:space:]]*false' "$f" 2>/dev/null | head -1)
            if [[ -n "$line" ]]; then
                lineno=$(echo "$line" | cut -d: -f1)
                rel=$(realpath --relative-to="$COLL" "$f")
                warn "  $rel:$lineno — uses inherit:false but adapter contract is $adapter_contract (requires 2.0.0+; pre-2.0 adapters silently ignore inherit)"
            fi
        done < <(find "$COLL/api" -maxdepth 2 -name '*.md' -print0 2>/dev/null)
    fi
fi
log "  warnings: $(( ${#WARNINGS[@]} - w8 ))"

# ── Report ──────────────────────────────────────────────────────────────────
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "${#ERRORS[@]}" -eq 0 ]] && [[ "${#WARNINGS[@]}" -eq 0 ]]; then
    log "✓ preflight passed ($COLL_NAME v$COLL_VERSION)"
    exit 0
fi
err_n=${#ERRORS[@]}
warn_n=${#WARNINGS[@]}
if (( err_n > 0 )); then
    log "✗ $err_n error(s):"
    for e in "${ERRORS[@]}"; do log "$e"; done
fi
if (( warn_n > 0 )); then
    log "⚠ $warn_n warning(s):"
    for w in "${WARNINGS[@]}"; do log "$w"; done
fi
(( err_n > 0 )) && exit 1
exit 0
