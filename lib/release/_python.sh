#!/usr/bin/env bash
# _python.sh -- sourced by release-{prep,push,stage}.sh (developer lib/release; 1.14.0).
# Resolves a Python 3 that actually RUNS and defines python3() so every python3 call in the
# sourcing script uses it. Why: on Windows, `python3` is often the Microsoft Store alias stub --
# `command -v python3` succeeds, but running it prints "Python was not found" and outputs nothing.
# release-prep read that empty output as "no repos" and reported PREP OK having checked nothing.
#
# Also on Windows (Git Bash/MSYS) Python writes CRLF to stdout -- the stray \r corrupts the repo
# names the scripts read back -- and cannot open /c/... paths. python3() strips \r, and
# py_path converts a path for Python (C:/... form) where cygpath is available.
_py_runs(){ [ "$("$@" -c 'print(42)' 2>/dev/null | tr -d '\r')" = "42" ]; }
_PY=()
if _py_runs python3; then _PY=("$(command -v python3)")
elif _py_runs py -3; then _PY=(py -3)
elif _py_runs python; then _PY=("$(command -v python)")
else
  echo "FATAL: no working Python 3 (tried python3, py -3, python). On Windows, install it"
  echo "       (winget install -e --id Python.Python.3.12) and reopen the shell -- or use the .ps1"
  echo "       scripts, which need no Python. A 'Python was not found' message means python3 is the"
  echo "       Microsoft Store alias, not Python."
  exit 2
fi
python3(){ "${_PY[@]}" "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; }
py_path(){
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; return; fi ;;
  esac
  printf '%s\n' "$1"
}
# AIFS:FILE-END
