#!/usr/bin/env bash
# Pre-send check for PowerShell scripts. Run this BEFORE sending any .ps1 to Rich
# or committing it. Catches the 2026-06-19 break: non-ASCII chars (em-dashes etc.)
# that Windows PowerShell 5.1 mis-reads and that crash the parser.
#
# Usage:  tools/check-ps.sh Export-Data.ps1 [more.ps1 ...]
#         tools/check-ps.sh            # checks every *.ps1 in the repo
set -u
files=("$@")
if [ "${#files[@]}" -eq 0 ]; then mapfile -t files < <(find . -name '*.ps1' -not -path './.git/*'); fi
fail=0
for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "skip (not found): $f"; continue; }
  # 1) ASCII-only (the actual bug class)
  if grep -nP '[^\x00-\x7F]' "$f" >/dev/null; then
    echo "FAIL  $f  -> non-ASCII characters (use ASCII only in .ps1):"
    grep -nP '[^\x00-\x7F]' "$f" | sed 's/^/        /'
    fail=1
  fi
  # 2) delimiter balance — INFO only (raw counts include parens/braces inside
  #    strings & comments, so a mismatch here is not necessarily a real error).
  #    The authoritative syntax check is the PowerShell parser in CI.
  ob=$(tr -cd '{' < "$f" | wc -c); cb=$(tr -cd '}' < "$f" | wc -c)
  [ "$ob" != "$cb" ] && echo "      (info) brace count differs {=$ob }=$cb - verify via CI parser"
  [ "$fail" -eq 0 ] && echo "OK    $f  (ASCII clean)"
done
if [ "$fail" -ne 0 ]; then echo "==> FAILED. Do not send/commit until fixed."; exit 1; fi
echo "==> All checks passed."
