---
title: Game Design Document — Roll Anime to Fight (clone)
game_type: gacha auto-battler / wave defense
platforms: Roblox
status: draft
created: 2026-08-04
updated: 2026-08-04
---

# Game Design Document

**Canonical for design intent.** Where this contradicts a wiki, this wins. Where it contradicts
[`source-game-teardown.md`](../ground-truth/source-game-teardown.md) on a **[C]** fact, the teardown
wins and this document is wrong.

Notation carried from the teardown: **[C]** confirmed · **[D]** derived · **[I]** inferred ·
**[?]** open. Anything marked **[OURS]** is a design decision we made because the source game's
value is unknowable — it is not a claim about the original.

---

## 1. Pillars

Restated from the brief because everything below serves them:

1. **The two-axis pull** — rarity × mutation, independent. A mutated Common beats a clean Epic.
2. **The clock is a character** — mutations rotate every 15 minutes.
3. **Numbers that keep moving** — ~5% enemy HP growth per wave, endless.
4. **Idle-tolerant, attention-rewarded.**

**The failure mode to design against:** if mutation multipliers are too small, rarity dominates and
pillar 1 collapses into an ordinary rarity ladder. Every number in §4 is chosen to prevent that.

---

## 2. Core loop

```
        ┌─────────────────────────────────────────────┐
        │                                             │
   spend gold ──► ROLL ──► unit (rarity × mutation)   │
        ▲                        │                    │
        │                        ▼                    │
        │              inventory (cap 75→225)         │
        │                        │                    │
        │            ┌───────────┴───────────┐        │
        │            ▼                       ▼        │
        │    merge (same unit +        place on grid  │
        │     mutation + level)         (4→12 slots)  │
        │            │                       │        │
        │            └───────────┬───────────┘        │
        │                        ▼                    │
        │                  START wave                 │
        │                        │                    │
        │              auto-battle vs 16 enemy tiles  │
        │                        │                    │
        └──────── gold ◄─────────┴────► trait shards  │
                  essence                             │
                     └────────────────────────────────┘
```

Wave counter persists across sessions. **[C]**

---

## 3. Combat model

### 3.1 The arena — **[C]**

| Side | Tiles | Notes |
|---|---|---|
| Player | **4 → 12** (Slot Upgrade) | Blue outline |
| Enemy | **16**, fixed | Red outline |

Units auto-attack. The player never controls a unit directly — placement and squad composition
*are* the gameplay. **[C]** Support units heal (green numbers observed).

### 3.2 Stats — **[C]** the four stats, **[OURS]** all magnitudes

`Attack · Defense · Health · Speed`

**[?]** No stat magnitude appears in any screenshot. Everything below is our baseline.

**[OURS]** Damage resolution, kept deliberately simple — this is an idle auto-battler, not a tactics
game, and every extra term is a number the player cannot see:

```
hit          = attack × mutationDamageMult × (1 + Σ traitDamage) × levelMult
mitigated    = hit × (100 / (100 + defense))
crit         = mitigated × (1 + critDamage)   when rand() < critChance
attackPeriod = baseAttackPeriod / (1 + Σ traitAttackSpeed)
```

`Defense` uses the standard `100/(100+D)` curve so it has diminishing returns and can never reach
immunity. **[OURS]** — the source game shows a Defense stat but never its formula.

### 3.3 Roles — **[C]**

`DAMAGE · TANK · SUPPORT`, filterable in the Index. **[OURS]** Intended split roughly 60/20/20 of
the roster, so a squad has a real composition decision rather than "equip highest number".

---

## 4. Power model — the pillar, in numbers

A unit's power is the product of four independent multipliers:

```
power = rarityMult × mutationMult × levelMult × (1 + traitBonus)
```

### 4.1 Rarity multipliers — **[OURS]**

| Rarity | Mult | Roll chance (luck x1) |
|---|---|---|
| Common | 1.0 | 62.1% |
| Rare | 2.2 | 25% |
| Epic | 5.0 | 8% |
| Legendary | 12 | 1 in 35 |
| Mythic | 28 | 1 in 70 |
| Secret | 65 | 1 in 180 |
| God | 150 | 1 in 40,000 |

### 4.2 Mutation multipliers — **[OURS]**, and where the pillar is enforced

| Mutation | Damage | Availability |
|---|---|---|
| Normal | 1.0 | always |
| Gold | 1.75 | always |
| Diamond | 2.5 | always |
| Demon | 3.25 | event `:15` |
| Slayer | 4.0 | event `:00` |
| Hollow | 4.75 | event `:45` |
| Destroyer | 5.5 | event `:30` |
| Astronaut | 6.5 | Admin Abuse only |

**The pillar check.** A mutation multiplier must be able to leap a unit at least one rarity tier:

| Matchup | Power | Winner |
|---|---|---|
| Destroyer **Common** (1.0 × 5.5) | **5.5** | beats a clean Epic (5.0) ✓ |
| Diamond **Rare** (2.2 × 2.5) | **5.5** | beats a clean Epic (5.0) ✓ |
| Gold **Epic** (5.0 × 1.75) | **8.75** | loses to a clean Legendary (12) |

So mutations reliably buy **one tier**, occasionally two, and never trivialise the ladder. That is
the intended shape: a lucky Common is a genuine result worth keeping, not a consolation prize.

### 4.3 Levels — **[I]** structure, **[OURS]** magnitude

**[C]** Merging requires **same unit + same mutation + same level**. **[I]** This implies a binary
tree: a Lv*n* unit costs `2^(n-1)` base copies.

**[OURS]** `levelMult = 1.8^(level-1)`. Chosen deliberately **below** the 2× copy cost, so merging
is a real trade — you give up board width for depth. If it were ≥2× merging would be strictly
correct and the decision would evaporate.

**[C] Trait retention:** the unit placed **first** keeps its trait; the one dropped on top is
consumed. The merge UI must make the base unit unmistakable — this is a losable, irreversible
choice and it is in their FAQ precisely because players get it wrong.

### 4.4 Traits — **[C]** verbatim, all 17

Full table in the teardown §7. Two carry unique mechanics rather than stat lines and need real
implementation: **Cloner** (summons 2 units instead of 1) and **Ghost** (revives once at 80% stats).
**Juggernaut** is the only trait with a downside (10% slower attacks).

---

## 5. Wave scaling — **[D]** shape, **[OURS]** constants

**[C]** The only hard anchor: **wave 174 → enemy HP 481,324.**

Solving `base × growth^(wave-1)` against that anchor:

| Growth | Implied base HP at wave 1 |
|---|---|
| 1.04 | 544 |
| 1.045 | 237 |
| **1.05** | **103.9** |
| 1.055 | 46 |
| 1.06 | 20 |

A 5% growth rate implies a wave-1 HP of **103.9** — essentially a round 100. A single data point
173 waves out landing that close to a clean number is strong evidence this is the real curve, so:

```
enemyHP(wave) = 100 × 1.05^(wave-1)          [OURS, fitted to the [C] anchor]
```

Reproduces the anchor to within **3.8%** (463,179 vs 481,324) — inside what one data point can
honestly justify. Do not add precision we have not earned.

| Wave | HP |
|---|---|
| 1 | 100 |
| 25 | 323 |
| 50 | 1,092 |
| 100 | 12,524 |
| 174 | 463,179 |

### 5.1 Enemy count — **[C]** observed, **[OURS]** curve

Observed across 9 screenshots: `w9→4, w13→3, w16→5, w25→6, w26→7, w29→9, w33→7, w34→7, w174→8`.

**Count does not scale with wave.** It sits in a 3–9 band from wave 9 to wave 174. Difficulty comes
almost entirely from HP, not from swarm size — which makes sense with only 16 enemy tiles.

```
enemyCount(wave) = clamp(3 + floor(wave / 20), 3, 10)      [OURS]
```

**[OURS]** Every 10th wave is a **boss wave**: one enemy, 8× HP, 5× gold. Nothing confirms bosses in
the wave rotation — but the Admin Abuse event has a "boss spawn", so bosses exist as a concept, and
an endless 5%-per-wave ramp with no rhythm is monotonous. Flagged clearly as our addition.

### 5.2 Gold — **[OURS]**

```
goldPerKill = ceil(enemyHP(wave) × 0.02) × goldUpgradeMult
```

Proportional to HP so the economy self-balances against the difficulty curve rather than needing a
second tuned exponent. At wave 174 with the ×3.4 max upgrade that is ~31.5k per kill — consistent
with the observed 50.8M bank on a mature account.

**[C]** Kills also drop **Trait Shards** and **Essence**. **[OURS]** Essence drops at the rarity of
the enemy tier, God Essence at a very low rate, matching the FAQ's *"small chances, recommended to
afk"*.

### 5.3 Absolute scale — **[OURS]**

The multipliers above are all relative. Two numbers give them absolute meaning, and therefore make
the curve tunable in **seconds** rather than in ratios:

```
BASE_ATTACK         = 10      -- a Common / Normal / Lv1 unit's hit
BASE_ATTACK_PERIOD  = 1.0s
```

A starting squad is 4 slots of Common Lv1 → **40 DPS**.

### 5.4 What the curve actually feels like

Measured, not asserted — `tests/design-invariants.luau` computes these and fails CI if they drift:

| Wave | Time to clear, unaided starting squad |
|---|---|
| 1 | 7.5s |
| 5 | 9.1s |
| 9 | 11.1s |
| 10 *(boss)* | 31s |
| 15 | 14.8s |
| **40** | **>120s — the stall** |

**The design target is met:** a fresh player clears the wave-15 first-session goal comfortably, and
hits a genuine wall around **wave 40** — far enough out to feel earned, close enough that rolling
and merging become obviously necessary rather than optional. Boss waves land as a real spike (11s →
31s at wave 10) without being a brick.

### 5.5 The tuning question this raises

Enemy HP grows 5% per wave *forever*. Player power grows in **discrete jumps** — a roll, a merge, a
trait. Those two curves cannot be matched analytically; the wall is wherever the player's luck
stops. The wave-40 stall above assumes **zero progression**, which no real player experiences.

**This still needs a headless economy sim** — one that plays thousands of simulated sessions,
rolling and merging on our actual odds — before the numbers are trusted. The tests prove the curve
is *shaped* right; only a sim proves it is *paced* right.

---

## 6. Systems, and which epic owns them

| System | Epic | Notes |
|---|---|---|
| Roll machine, 3 pity counters, luck | **1** | Pity for Legendary/Mythic/Secret. God has none. **[C]** |
| Rarity × mutation, event clock | **1** | The pillar. Not cuttable. |
| Inventory, merge, grid placement | **1** | Merge rule is strict. **[C]** |
| Wave combat, gold, persistence | **1** | |
| Four upgrades | 2 | Formulas derived and tested. **[D]** |
| Traits + Trait Machine | 3 | 17 traits, incl. 2 unique mechanics |
| Clone Machine (essence, timers) | 4 | |
| Index + 5%-cash-per-5-units reward | 4 | **[C]** |
| Infinite Tower | 5 | Ticket-gated, own leaderboard |
| Evolution Machine | 5 | **[?]** recipes entirely unknown |
| Spin Wheel, codes, leaderboards, Trade | 6 | |
| Admin Abuse events | 6 | Needs a lobby space separate from the arena |
| Shop / Robux | — | Systems built, hooks stubbed. Owner's call to activate. |

---

## 7. Epic 1 — the vertical slice

**Hypothesis:** *does the two-axis pull feel good?*

Mutations are **in scope for Epic 1** specifically to test this. Cutting them to "simplify the
slice" would test a different, less interesting game.

**Done when:** a player rolls, merges, places, clears wave 10 without instruction, and their
progress survives a rejoin.

**Acceptance criteria (EARS):**

- When the player presses ROLL and has sufficient gold, the system **shall** deduct the cost and
  grant one unit whose rarity is drawn from the luck-adjusted distribution.
- When a roll occurs during an event mutation window, the system **shall** include that mutation and
  only that mutation in the mutation pool, alongside Normal/Gold/Diamond.
- When the player drops unit B onto placed unit A, and A and B share identity **and** mutation
  **and** level, the system **shall** consume B and raise A to level+1, retaining A's trait.
- When the pity counter for a tier reaches zero, the next roll **shall** be of at least that tier.
- While a wave is running, the system **shall** award gold per enemy killed, scaled by the Gold
  Upgrade multiplier.
- When the player rejoins, the system **shall** restore wave number, gold, inventory, upgrade
  levels and grid placement.
- **Anti-exploit:** the server **shall** be sole authority for rolls, gold and merges; the client
  **shall not** be trusted for any of them.

---

## 8. Open design questions

1. **[?] Unit stat magnitudes.** All of §3.2 is invented. One real stat card would anchor it.
2. **[?] Upgrade cost curves.** One price point each — placeholders.
3. **[?] Skills.** Charge counts and per-skill `Auto` toggles are visible; no skill list captured.
4. **[?] Evolution Machine recipes.** Inputs guessed, outputs unknown.
5. **[?] Checkpoints.** Wiki-only. Not implementing on that evidence.
6. **[OURS, needs a call] Boss waves** (§5.1) — our invention. Keep or drop?
7. **[OURS, needs a call] Monetisation** — build the systems, stub the Robux hooks?
