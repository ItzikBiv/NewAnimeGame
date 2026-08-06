#!/usr/bin/env bash
# Everything CI checks, run locally, before pushing.
#
#   ./scripts/check.sh
#
# Uses the offline selene std (scripts/roblox-offline.yml) when the real Roblox
# API dump is unreachable, so linting still runs in sandboxed environments.
# CI remains authoritative — it lints with the full `std = "roblox"`.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

status=0
step() {
	local name="$1"
	shift
	echo ""
	echo "── $name ────────────────────────────────────────────"
	if "$@"; then
		echo "   PASS: $name"
	else
		echo "   FAIL: $name"
		status=1
	fi
}

have() { command -v "$1" >/dev/null 2>&1 || [[ -n "${2:-}" ]]; }

# StyLua — formatting.
if command -v stylua >/dev/null 2>&1 || [[ -n "${STYLUA:-}" ]]; then
	step "stylua --check" "${STYLUA:-stylua}" --check src tests
else
	echo "skip: stylua not found (set STYLUA=/path/to/stylua)"
fi

# Selene — lint. Prefer the real Roblox std; fall back to the offline one when the
# API dump cannot be fetched.
SELENE="${SELENE:-$(command -v selene || true)}"
if [[ -n "$SELENE" ]]; then
	if "$SELENE" src >/dev/null 2>&1; then
		step "selene (roblox std)" "$SELENE" src
	else
		echo ""
		echo "note: the full Roblox std is unavailable here — using the offline std."
		echo "      CI still lints with std = \"roblox\", which is authoritative."
		step "selene (offline std)" "$SELENE" --config scripts/selene-offline.toml src
	fi
else
	echo "skip: selene not found (set SELENE=/path/to/selene)"
fi

# Rojo — the project must still build.
PLACE=/tmp/rollanimetofight-check.rbxlx
if command -v rojo >/dev/null 2>&1 || [[ -n "${ROJO:-}" ]]; then
	step "rojo build" "${ROJO:-rojo}" build -o "$PLACE"

	# And the built tree must have the SHAPE the requires assume. Building
	# successfully says nothing about where instances landed — a bad require path
	# passes every other check here and only fails in a playtest.
	if [[ -f "$PLACE" ]] && command -v python3 >/dev/null 2>&1; then
		step "instance paths" python3 scripts/check-tree.py "$PLACE"
	fi
else
	echo "skip: rojo not found (set ROJO=/path/to/rojo)"
fi

# Tests — the headless suites.
step "config + design + save tests" ./scripts/run-tests.sh

echo ""
if [[ "$status" -eq 0 ]]; then
	echo "all checks passed"
else
	echo "one or more checks FAILED"
fi
exit "$status"
