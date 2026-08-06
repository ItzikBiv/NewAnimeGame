#!/usr/bin/env python3
"""Assert that the built place puts instances where the code expects them.

WHY THIS EXISTS. `src/client/` contains an init.client.luau, so Rojo turns the
DIRECTORY into a LocalScript named Client and makes every sibling file a CHILD of
it. `Arena.luau` therefore lands at StarterPlayerScripts.Client.Arena, and the
correct require is `script.Arena`.

The first version wrote `script.Parent.Arena`. That is PlayerScripts, where nothing
called Arena exists, so the require threw on line 32 — before the client had built a
single instance. The player got an empty grey void: no HUD, no camera, no in-game
sign that anything was wrong. Every headless test passed, stylua passed, selene
passed and `rojo build` passed, because none of them look at the SHAPE of the tree.

This does. It is the cheapest possible guard against a whole class of bug that is
invisible to every other check we run and only shows up in a playtest.

Usage:  check-tree.py <built-place.rbxlx>
"""

import re
import sys

# Instance paths that some `require` or `WaitForChild` in the source depends on.
# Add a row whenever code starts reaching for a new path.
REQUIRED_PATHS = [
    # require(script.Arena) from src/client/init.client.luau
    ("StarterPlayer", "StarterPlayerScripts", "Client", "Arena"),
    # require(script.Services.*) / require(script.Middleware.*) from src/server
    ("ServerScriptService", "Server", "Services", "GameService"),
    ("ServerScriptService", "Server", "Services", "DataService"),
    ("ServerScriptService", "Server", "Middleware", "Guard"),
    # The client blocks on ReplicatedStorage:WaitForChild("Shared") and every
    # shared module is reached through it.
    ("ReplicatedStorage", "Shared", "Config", "Units"),
    ("ReplicatedStorage", "Shared", "Config", "Rarities"),
    ("ReplicatedStorage", "Shared", "Net", "Remotes"),
    ("ReplicatedStorage", "Shared", "Combat", "Wave"),
]

TOKEN = re.compile(
    r'<Item class="([^"]+)"[^>]*>|</Item>|<string name="Name">([^<]*)</string>'
)


def build_tree(xml: str):
    """Return the set of instance paths in the place, as tuples of names."""
    stack: list[list] = []  # each entry: [name, class]
    paths: set[tuple[str, ...]] = set()

    for match in TOKEN.finditer(xml):
        item_class, name = match.group(1), match.group(2)
        if item_class is not None:
            stack.append([None, item_class])
        elif name is not None:
            # The first <string name="Name"> after an <Item> names that instance.
            # Properties of a child would appear only after that child's own
            # <Item>, so walking back to the nearest unnamed frame is correct.
            for frame in reversed(stack):
                if frame[0] is None:
                    frame[0] = name
                    break
        else:
            if stack:
                named = tuple(f[0] for f in stack if f[0] is not None)
                if len(named) == len(stack):
                    paths.add(named)
                stack.pop()

    return paths


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-tree.py <built-place.rbxlx>", file=sys.stderr)
        return 2

    with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
        paths = build_tree(handle.read())

    missing = [p for p in REQUIRED_PATHS if p not in paths]

    for path in REQUIRED_PATHS:
        mark = "FAIL" if path in missing else "ok  "
        print(f"  {mark} {'.'.join(path)}")

    if missing:
        print(
            f"\n{len(missing)} expected instance path(s) are NOT in the built place.\n"
            "Something in the source requires a path that Rojo does not produce.\n"
            "Remember: a folder with an init script BECOMES the script, and its\n"
            "siblings become its CHILDREN — so it is script.Foo, not script.Parent.Foo.",
            file=sys.stderr,
        )
        return 1

    print(f"\n{len(REQUIRED_PATHS)} instance paths present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
