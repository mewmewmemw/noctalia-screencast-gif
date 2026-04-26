#!/usr/bin/env bash
# Static analysis. Runs shellcheck on every shell script in the repo.
# Exits non-zero if any check fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mapfile -t scripts < <(find "$ROOT" \
    -name .git -prune -o \
    -type f \( -name '*.sh' -o -name '*.bats' \) -print)

echo "shellcheck: ${#scripts[@]} files"
fail=0
for f in "${scripts[@]}"; do
    # bats files have a non-bash header but shellcheck handles --shell=bash fine.
    if [[ $f == *.bats ]]; then
        shellcheck --shell=bash --severity=warning "$f" || fail=1
    else
        shellcheck "$f" || fail=1
    fi
done

exit $fail
