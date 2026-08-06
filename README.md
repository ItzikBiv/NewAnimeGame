# Roll Anime to Fight — clone

A Roblox gacha auto-battler / wave-defense game, cloning
[*Roll Anime to Fight!*](https://www.roblox.com/games/107653945083776/Roll-Anime-to-Fight)
by *Another Slop*.

Built with **Rojo + Luau**. Developed under the
[workflow](https://github.com/Bent40/Workflow-Marketplace) operating model, using the
BMad Game Dev Studio skill suite.

## The game in one line

Spend gold to **roll** anime fighters, **merge** duplicates to level them, **place** them on a
grid, and **survive** endless waves — where a *mutated* low-rarity unit can beat a clean
high-rarity one.

## Start here

**[`docs/ground-truth/source-game-teardown.md`](docs/ground-truth/source-game-teardown.md)** is the
canonical reference for what the source game actually does. It is built from direct observation of
the live game, not from wikis — several public wikis are wrong on points the teardown corrects.

Every claim in it is marked **[C]** confirmed / **[D]** derived / **[I]** inferred / **[?]** open.
**Do not encode an [I] or [?] as a magic number in gameplay code** — put it in a config table with
a comment pointing back to the teardown, so a correction stays a one-line data change.

## Layout

```
docs/ground-truth/   Source-game teardown — the reference for all design work
docs/planning/       BMad artifacts (brief, GDD, architecture, epics)
src/shared/Config/   Confirmed + derived data tables (rarities, mutations, traits, upgrades)
src/server/          Server gameplay systems
src/client/          HUD and interaction
_bmad/               Workflow / BMad project config
```

## Setup

```sh
rokit install          # rojo, selene, stylua, wally, luau-lsp
wally install          # dependencies
rojo serve             # then connect from Roblox Studio via the Rojo plugin
```

Build a place file without Studio:

```sh
rojo build -o RollAnimeToFight.rbxlx
```

Run everything CI checks, before pushing:

```sh
./scripts/check.sh          # stylua + selene + rojo build + all test suites
./scripts/run-tests.sh      # just the headless test suites
```

`check.sh` falls back to an offline selene std (`scripts/roblox-offline.yml`) when the Roblox API
dump host is unreachable, so linting still runs in sandboxed environments. CI remains authoritative
— it lints with the full `std = "roblox"`.

## Status

Planning. The scaffold builds and the confirmed data tables are encoded; gameplay systems are not
implemented yet.

Delivery is **vertical slice first** — Epic 1 ships the full core loop end to end
(roll → merge → place → wave → gold → save), then mutations, traits, checkpoints, upgrades, codes
and shops layer on as later epics.

## Known gaps

The two that most affect the build, both tracked in the teardown's Open Questions:

1. **Base roll odds are not published anywhere** and cannot be read off a screenshot. A 1:1 numeric
   clone of the gacha is not achievable from public data — we design our own curve, bounded by the
   observed pity caps.
2. **`SPD` sign convention** is contradictory between the dev FAQ and the in-game Trait Machine.
   It inverts the strongest trait in the game and must be resolved before attack-speed code.
