---
title: Game Brief — Roll Anime to Fight (clone)
status: draft
created: 2026-08-04
updated: 2026-08-04
---

# Game Brief

Grounding: [`docs/ground-truth/source-game-teardown.md`](../ground-truth/source-game-teardown.md).
This brief is deliberately short. The vision is not being discovered — it is a clone of a shipped,
observed game, so the teardown *is* the vision document. What this brief adds is the **why**, the
**pillars**, and the **cut line**.

## Core fantasy

> *"One more roll. That's the one that carries me."*

The player is not a fighter. They are a collector who assembles a squad and watches it hold the
line — and the whole emotional arc lives in the gap between pulling the lever and seeing the label
come up gold.

## Pillars

1. **The two-axis pull.** Rarity and mutation are independent. A mutated Common can beat a clean
   Epic. Every roll therefore has two chances to be exciting, and the ceiling on a "bad" tier is
   never zero. *This is the pillar. Everything else is scaffolding around it.*
2. **The clock is a character.** Mutations rotate on a quarter-hour cycle
   (`Slayer :00 · Demon :15 · Destroyer :30 · Hollow :45`). Rolling is not "spend gold" — it is
   *"be here at :30 if you want a Destroyer."* Retention is designed into the mechanic, not bolted on.
3. **Numbers that keep moving.** Enemy HP grows ~5% per wave, forever. There is no win screen.
   Progress is a number going up and a wave counter you can quote at other players.
4. **Idle-tolerant, attention-rewarded.** `Auto` and `2x` are permanent HUD fixtures and the devs
   themselves recommend AFK farming for God Essence. The game must play itself competently — but a
   player who shows up at :30 with a full inventory does meaningfully better.

## Audience

Roblox players who already play this genre — *Anime Fighters*, *Defend Ur Base*, the whole
roll-and-merge shelf. They are pattern-fluent: they will find the merge rule and the pity counters
without a tutorial, and they will notice immediately if the drop rates feel stingy. **Not** a
general Roblox audience, and explicitly not a "casual player who has never seen a gacha".

## What we take, what we leave

**Take:** the two-axis roll, the timed mutation rotation, the strict merge rule (same unit + same
mutation + same level), the four-upgrade economy, the trait machine, endless waves, per-player
arenas in a shared server.

**Leave:** the monetisation depth (R$1749 shard packs, VIP chests, limited gacha banners) — the
systems get built, the Robux hooks stay stubbed. Also leaving their exact character names; we coin
our own parodies, as they did.

**Cannot take:** their drop rates. Not published, not recoverable. Ours are designed to the
constraints their pity counters imply. This is the one place the clone is provably not 1:1, and it
is documented rather than hidden.

## Scope

**Large**, delivered vertical-slice-first. Approved at kickoff.

### MVP — Epic 1, the hypothesis test

The core loop, end to end, and nothing else:

```
roll → get unit → merge duplicates → place on grid → survive a wave → earn gold → roll again
```

Plus persistence, because a wave counter that resets is not the game.

**The hypothesis Epic 1 exists to test:** *does the two-axis pull feel good?* If rolling a
Gold Common is not more exciting than rolling a clean Rare, the pillar is broken and no amount of
later content fixes it. Epic 1 ships with mutations **in** for exactly this reason — cutting them
to "simplify the slice" would test the wrong thing.

### Deliberately after the slice

Traits · Clone Machine · Evolution Machine · Infinite Tower · Spin Wheel · Trade · codes ·
leaderboards · Admin Abuse events · shop. All designed in the GDD, none in Epic 1.

## Risks

| Risk | Why it's real | Response |
|---|---|---|
| **Balance is unverifiable without players** | We have one wave-scaling anchor and zero unit stat magnitudes | Headless sim over the economy before tuning by feel |
| **No Roblox Studio in the build environment** | Nothing visual or runtime can be verified by the agent | All logic lives in pure, testable modules; owner verifies in Studio |
| **The clone is mechanically faithful but feels flat** | Fidelity to systems ≠ fidelity to *feel*. Their game has juice we cannot read off a screenshot | Budget explicitly for roll animation, mutation VFX and damage-number weight — treat polish as scope, not garnish |
| **Scope is genuinely large** | 8 machines/modes, 73+ units, 17 traits, 8 mutations | Vertical slice first; every later system is an independent epic |

## Success

- **Epic 1:** a player rolls, merges, places, and clears wave 10 without instruction, and their
  progress survives a rejoin.
- **v1:** a player who has played the original recognises it, and cannot name a core system we are
  missing.
