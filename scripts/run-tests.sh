#!/usr/bin/env bash
# Runs the ground-truth config tests under the plain Luau CLI.
#
# Why this exists: the config tables are pure data + pure functions, so they can be
# verified without Roblox Studio or any Roblox runtime. That means CI (and an agent
# working headlessly) can prove the derived formulas still match the source game.
#
# The Luau CLI has no `io` library and no Roblox globals, so we concatenate the
# modules into one chunk and stub the handful of Roblox globals the config uses.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/src/shared/Config"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

LUAU="${LUAU:-$(command -v luau || true)}"
if [[ -z "$LUAU" ]]; then
	echo "error: luau not found on PATH." >&2
	echo "  install it with 'rokit install', or download a release from" >&2
	echo "  https://github.com/luau-lang/luau/releases and set LUAU=/path/to/luau" >&2
	exit 1
fi

OUT="$BUILD/run.luau"

# Roblox globals used by the config tables.
cat >"$OUT" <<'STUB'
Color3 = { fromRGB = function(r, g, b) return { r = r, g = g, b = b } end }
STUB

# Inline each config module as a function call, binding it to a global of the
# same name so the test file can reach it.
#
# Order matters: a module listed here may only require modules listed before it.
# `require(script.Parent.Foo)` is rewritten to the global `Foo`, since there is no
# Roblox instance tree outside Studio.
for module in Rarities Mutations Traits Upgrades Waves Power; do
	{
		echo "local function _load_${module}()"
		sed -E 's/require\(script\.Parent\.([A-Za-z0-9_]+)\)/\1/g' "$CONFIG/${module}.luau"
		echo "end"
		echo "${module} = _load_${module}()"
	} >>"$OUT"
done

echo 'print("config modules parsed: Rarities, Mutations, Traits, Upgrades, Waves, Power\n")' >>"$OUT"

# Each suite runs in its own chunk so a failure in one still reports the other.
status=0
for suite in config-invariants design-invariants; do
	SUITE_OUT="$BUILD/${suite}.luau"
	cp "$OUT" "$SUITE_OUT"
	{
		echo "print(\"\\n===== ${suite} =====\\n\")"
		cat "$ROOT/tests/${suite}.luau"
	} >>"$SUITE_OUT"
	"$LUAU" "$SUITE_OUT" || status=1
done

exit "$status"
