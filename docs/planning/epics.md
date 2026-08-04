---
title: Epics and Stories — Roll Anime to Fight (clone)
status: draft
created: 2026-08-04
updated: 2026-08-04
---

# Epics and Stories

Design: [`gdd.md`](./gdd.md) · Architecture: [`architecture.md`](./architecture.md)

Delivery is **vertical-slice-first**. Epic 1 ships the whole loop end to end; everything after it
layers on. Each story names its **allowed files** so parallel work cannot collide, and states what
"done" means in terms that can be checked rather than felt.

**The purity rule from architecture.md §2 governs every story here:** game logic goes in pure
modules under `src/shared`, side effects go in thin services. That is what keeps `scripts/check.sh`
able to verify behaviour with no Studio.

---

## Epic 1 — The core loop (vertical slice)

**Hypothesis:** *does the two-axis pull feel good?* Mutations are in scope specifically to test it.

**Done when** a player rolls, merges, places, clears wave 10 without instruction, and their progress
survives a rejoin.

| # | Story | Status |
|---|---|---|
| 1.1 | Roll resolution — rarity, mutation, pity | **done** |
| 1.2 | Inventory: uid issuing, capacity, ownership | todo |
| 1.3 | Merge resolution — the strict three-way match | todo |
| 1.4 | Grid placement and slot limits | todo |
| 1.5 | Wave simulation — spawn, damage, gold | todo |
| 1.6 | DataService — load, migrate, session-lock, autosave | todo |
| 1.7 | Remotes + rate limiting + validation middleware | todo |
| 1.8 | Client HUD, roll machine, inventory, grid UI | todo |
| 1.9 | In-Studio playtest and polish pass | todo *(owner)* |

---

### Story 1.1 — Roll resolution ✅

**Allowed:** `src/shared/Gacha/Roll.luau`, `tests/roll-invariants.luau`, `scripts/run-tests.sh`
**Forbidden:** anything under `src/server`, `src/client`

Pure resolution of a single roll: rarity from the luck-adjusted distribution, mutation from the
currently-open event window, and pity bookkeeping.

**Acceptance**
- Given luck L and pity state P, when a roll resolves, the system **shall** return a rarity drawn
  from `Rarities.rollChances(L)` and the updated pity state.
- When a tier's pity counter reaches zero, the next roll **shall** be of at least that tier.
- When a roll lands at tier T, the pity counters for T and every tier below it **shall** reset.
- When a roll resolves during an event mutation window, the mutation **shall** be drawn only from
  the three always-on mutations plus that window's mutation.
- The module **shall** take its RNG as an argument, so tests are deterministic.

**Verification:** statistical — 200k seeded rolls, observed rates within tolerance of designed
rates, and no gap between hits of a tier longer than its pity cap.

---

### Story 1.2 — Inventory

**Allowed:** `src/shared/Inventory/*`, `tests/inventory-invariants.luau`

Uid issuing, capacity enforcement against the Inventory Upgrade, ownership lookup.

**Acceptance**
- When a unit is granted and the inventory is below capacity, the system **shall** store it under a
  fresh uid and increment `nextUid`.
- When the inventory is at capacity, the system **shall** reject the grant and report it — never
  silently drop a rolled unit.
- Uids **shall** never be reused within a profile, even after a unit is consumed by a merge.

---

### Story 1.3 — Merge resolution

**Allowed:** `src/shared/Inventory/Merge.luau`, `tests/merge-invariants.luau`

**[C]** The strict rule: same unit **and** same mutation **and** same level.
**[C]** The base unit keeps its trait; the consumed unit's trait is destroyed.

**Acceptance**
- When base and fodder match on all three of identity, mutation and level, the system **shall**
  consume the fodder and raise the base to `level + 1`, retaining the base's trait.
- When any of the three differ, the system **shall** reject the merge and state which condition
  failed — a silent no-op here reads as a lost unit.
- A unit placed on the grid **shall** remain the same uid after merging into it.

---

### Story 1.4 — Grid placement

**Allowed:** `src/shared/Grid/*`, `tests/grid-invariants.luau`

**Acceptance**
- When the player places a unit on a free tile within their slot count, the system **shall** record
  the uid against that tile.
- When the tile index exceeds the current Slot Upgrade value, the system **shall** reject it.
- A uid **shall** never occupy two tiles, and a tile **shall** never hold a uid the player does not
  own. *(Already asserted by `Schema.validate`.)*

---

### Story 1.5 — Wave simulation

**Allowed:** `src/shared/Combat/*`, `src/server/Services/CombatService.luau`, `tests/combat-*.luau`

Pure resolution of a wave tick, with the service owning only timing and replication.

**Acceptance**
- Enemy HP, count and gold **shall** come from `Waves`, and damage from `Power`.
- When an enemy dies, the system **shall** award `goldPerKill` scaled by the Gold Upgrade.
- When all enemies die, the wave counter **shall** increment and persist.
- The `2x` toggle **shall** scale the server tick, never client playback.

---

### Story 1.6 — DataService

**Allowed:** `src/server/Services/DataService.luau`, `wally.toml`

ProfileStore lands here — the story that first exercises it.

**Acceptance**
- On join, the system **shall** load, `migrate`, `withDefaults` and `validate` the profile.
- When validation fails, the system **shall** refuse the session rather than overwrite the save.
- The system **shall** hold a session lock for the duration of play.

---

### Story 1.7 — Remotes and middleware

**Allowed:** `src/shared/Net/*`, `src/server/Middleware/*`, `src/server/Services/*`

**Acceptance**
- Every `C→S` remote **shall** pass rate limiting and argument validation before reaching a service.
- `RequestRoll` **shall** take no arguments.
- The server **shall** reject any uid the calling player does not own.
- Cooldowns **shall** live in the persisted profile, so reconnecting does not reset them.

---

### Story 1.8 — Client

**Allowed:** `src/client/**`

**Acceptance**
- The roll animation **shall** play after the server result arrives, never predicting it.
- Rarity and mutation **shall** be visually distinct at a glance — this is the pillar, on screen.
- The merge UI **shall** make the base unit unmistakable. **[C]** Trait loss is irreversible and
  players get this wrong in the source game.
- Async states **shall** cover loading, empty and error, not just the happy path.

---

### Story 1.9 — Playtest *(owner)*

Studio-only. Nothing in CI can substitute for it. Confirms the hypothesis: **is rolling a Gold
Common more exciting than rolling a clean Rare?** If not, the pillar needs rework before Epic 2.

---

## Later epics

| Epic | Contents |
|---|---|
| 2 | The four upgrades + upgrade UI |
| 3 | Traits + Trait Machine (17 traits, incl. Cloner and Ghost's unique mechanics) |
| 4 | Clone Machine, essence economy, Index + its 5%-cash reward |
| 5 | Infinite Tower, Evolution Machine |
| 6 | Spin Wheel, codes, leaderboards, **Trade** *(needs its own security review)* |
| 7 | Admin Abuse events, lobby space |
| — | Shop / Robux — systems built, hooks stubbed pending owner's call |
