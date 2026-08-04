---
title: Game Architecture — Roll Anime to Fight (clone)
engine: Roblox
language: Luau
status: draft
created: 2026-08-04
updated: 2026-08-04
---

# Game Architecture

Design intent: [`gdd.md`](./gdd.md) · Source facts: [`../ground-truth/source-game-teardown.md`](../ground-truth/source-game-teardown.md)

This document covers how the game is built, not what it is. Decisions here are **reversible in
principle but expensive in practice** — they are flagged for review in §9 rather than assumed.

---

## 1. The one rule everything else follows

> **The server owns every number that a player would pay to change.**

This is a **gacha with tradeable, Robux-adjacent value**. Rolls, gold, merges, mutations and
inventory are all things a player has a direct incentive to forge. On Roblox the client is fully
compromised by default — exploiters run arbitrary Luau in the client context and can call any
`RemoteEvent` with any arguments at any rate.

Therefore:

| Concern | Where it lives |
|---|---|
| RNG for rolls and mutations | **Server only.** The client never sees a seed, a weight, or a pending result. |
| Gold, essence, shards, inventory | **Server only.** The client holds a read-only replica for display. |
| Merge validation | **Server only.** The client sends *intent* ("merge B onto A"), never an outcome. |
| Wave state, enemy HP, damage | **Server only.** |
| Mutation event clock | **Server only**, derived from server time and replicated. |
| Animation, VFX, camera, UI state | Client. |

**The client is a renderer and an input device. It is never a source of truth.**

A concrete consequence: the roll animation must play *after* the server has decided the result, or
the client would need to know the outcome early. The spinner is theatre over an already-settled
value — which is also how the source game must work.

---

## 2. Place structure

```
ReplicatedStorage/
  Shared/
    Config/          pure data + pure functions — no side effects, no services
      Rarities  Mutations  Traits  Upgrades  Waves  Power
    Net/             remote definitions, shared by client and server
    Types/           shared type definitions
  Packages/          Wally dependencies

ServerScriptService/
  Server/
    init.server.luau       bootstrap
    Services/
      DataService         persistence, session locking, migrations
      RollService         the gacha — sole owner of roll RNG
      InventoryService    ownership, capacity, merges
      CombatService       waves, enemy spawning, damage resolution
      EconomyService      gold, essence, shards, upgrades
      EventClockService   the 15-minute mutation rotation
    Middleware/
      RateLimit           per-player, per-remote token buckets
      Validate            argument shape + ownership checks

StarterPlayer/StarterPlayerScripts/
  Client/
    init.client.luau
    Controllers/         HUD, RollMachine, Inventory, Grid, Upgrades
    State/               read-only replica of the server's view
```

**`Shared/Config` is deliberately pure.** It has no `game:GetService`, no `wait`, no remotes — which
is exactly why `scripts/run-tests.sh` can execute it under the bare Luau CLI with no Roblox runtime.
That property is load-bearing for our whole test story and must not be given up for convenience.

---

## 3. Networking

### 3.1 Remotes are intent, never outcome

```
C→S  RequestRoll        {}                        -- no arguments at all
C→S  RequestMerge       { baseUid, consumedUid }  -- uids, not stats
C→S  RequestPlace       { uid, tileIndex }
C→S  RequestUpgrade     { upgradeId }
C→S  RequestWaveStart   {}

S→C  ProfileReplicated  { full profile snapshot }  -- on join
S→C  ProfileDelta       { changed fields only }    -- thereafter
S→C  RollResult         { unitId, rarity, mutation, pityAfter }
S→C  WaveTick           { wave, enemiesLeft, ... }
S→C  EventClockChanged  { activeMutation, nextChangeAt }
```

`RequestRoll` taking **no arguments** is deliberate. There is no field an exploiter can tamper with;
the server reads the player's gold and luck from its own state.

### 3.2 Replication strategy

Full snapshot on join, deltas after. A maxed inventory is **225 units** (`[D]` Inventory Lv7), each
carrying id, rarity, mutation, level and trait — small enough to send whole once, too large to
resend per change.

**[?] Open:** whether to hand-roll deltas or take a replication library. Hand-rolled is fewer
dependencies; a library is fewer bugs in a fiddly area. Decide at Epic 1 implementation.

### 3.3 Rate limiting — **required, not optional**

Every `C→S` remote passes through a per-player token bucket before it reaches a service. Without
this, a client loop calling `RequestRoll` thousands of times per second is both an economy exploit
and a server-performance incident.

Roll is additionally gated on the server's own cooldown, so the limit cannot be bypassed by
reconnecting.

---

## 4. Persistence

### 4.1 The store

**Recommendation: ProfileStore** (the maintained successor to ProfileService), via Wally.

Rationale — the failure it prevents is the expensive one. Roblox DataStores have no cross-server
locking, so two servers holding the same player produce **item duplication**, which in a game with
trading is unrecoverable and reputation-ending. ProfileStore provides session locking, auto-retry,
and a migration hook. Hand-rolling that is a known footgun with no upside.

**[?] Not yet added to `wally.toml`** — a dependency this environment cannot install or run is a
dependency I cannot verify. It goes in when Epic 1 implementation starts, so it lands with code that
exercises it.

### 4.2 Save schema

Versioned from day one. The one thing that cannot be retrofitted is the ability to know what shape
old data is in.

```luau
{
  schemaVersion = 1,

  wave          = 1,
  gold          = 0,
  currencies    = { traitShards = 0, essence = { Common = 0, ... } },
  upgrades      = { Gold = 1, Luck = 1, Slot = 1, Inventory = 1 },
  pity          = { Legendary = 0, Mythic = 0, Secret = 0 },
  rollCount     = 0,

  inventory     = { [uid] = { unitId, rarity, mutation, level, trait } },
  grid          = { [tileIndex] = uid },

  stats         = { highestWave = 1, highestGold = 0, totalRolls = 0 },
}
```

**Design notes**

- `pity` persists. **[C]** The source game's counters survive rejoin — losing them on disconnect
  would be a player-hostile bug in the most emotionally loaded system in the game.
- Units are keyed by a server-issued **uid**, not by index. Merges and trades reorder the
  collection constantly; index-keyed references break under exactly that.
- `grid` stores uids, so a placed unit is never a second copy of an inventory unit. One unit, one
  record. This is the invariant that prevents duplication through the grid.
- No Robux/receipt state here. Purchase records belong with Roblox's receipt system.

### 4.3 Migration

Each schema bump ships a pure `migrate_N_to_N+1(data)` function, applied in sequence on load. Pure
functions mean migrations are testable under the same headless runner as everything else — no
DataStore, no Studio. `src/shared/Save/Schema.luau` implements this and is covered by tests.

---

## 5. The mutation event clock

**[C]** `Slayer :00 · Demon :15 · Destroyer :30 · Hollow :45`, Astronaut from Admin Abuse only.

Derived on the **server** from `os.time()`, never from client time — the whole point of the rotation
is that everyone in the server is on the same schedule, and a client that can lie about the clock
can farm the rarest rollable mutation on demand.

`Mutations.activeEventMutation(minuteOfHour)` is already implemented and tested as a pure function.
`EventClockService` is a thin wrapper that calls it with server time and fires `EventClockChanged`
on transitions.

**[?] Open:** UTC or server-local. Recommend **UTC** — unambiguous, and cross-server consistent.

---

## 6. Combat

Waves run on the **server** at a fixed tick. The client receives state and renders it; it does not
simulate damage.

**[C]** The `2x` speed toggle scales the tick rate, not the client's animation playback — otherwise
speed becomes a client-side damage multiplier, which is a free exploit.

`Auto` mode is server-side too, so idle progression continues correctly and cannot be spoofed. **[C]**
The devs recommend AFK farming, so this path is heavily used and must be cheap: one timer per player
arena, no per-frame work when nothing has changed.

**Cost note:** each player has their own arena in a shared server. Combat cost is therefore
`O(players × units × enemies)` — bounded at `12 × 16` per player, which is fine, but the tick must
not do per-frame table allocation. Flagged for a load check before launch, not before Epic 1.

---

## 7. Anti-exploit baseline

Beyond server authority:

| Vector | Mitigation |
|---|---|
| Remote spam | Per-player token buckets (§3.3) |
| Forged uids | Every uid checked for ownership by the calling player |
| Merge forgery | Server re-validates identity + mutation + level; never trusts client claim |
| Negative / NaN arguments | Type and range validation at the middleware boundary |
| Duplication via grid | Grid stores uids only — one unit, one record (§4.2) |
| Duplication via trade | Both sides locked and validated in one server-side transaction |
| Reconnect to reset cooldowns | Cooldowns live in the persisted profile, not in memory |

**[?] Trading is the highest-risk surface in the game** and is deliberately scheduled late
(Epic 6). It should get its own security review rather than riding along with a feature epic.

---

## 8. Testing strategy

Three tiers, ordered by what they can prove:

1. **Pure headless** — `scripts/run-tests.sh`, no Roblox at all. Covers `Shared/Config` and
   `Shared/Save`. **121 checks today.** This is where balance, odds, formulas and migrations live,
   and it is the only tier CI can run.
2. **Server-logic tests** — services with injected fakes for DataStore and remotes. Needs a Roblox
   test runner. Not yet set up.
3. **In-Studio play tests** — the only tier that proves anything visual or felt. **Owner-run.** No
   Studio exists in this environment, and no amount of tier-1 coverage substitutes for it.

The discipline that makes tier 1 possible is §2's purity rule. Keeping game logic in pure modules
and side effects in thin services is the single highest-leverage architectural choice here.

---

## 9. Decisions flagged for review

Reversible in principle, expensive in practice. None blocks Epic 1 planning.

1. **ProfileStore for persistence** (§4.1) — a dependency, but session locking is not worth
   hand-rolling in a game with trading.
2. **Server-authoritative everything** (§1) — costs a round trip on every action. In a gacha with
   real-money-adjacent value, that is the correct trade.
3. **Snapshot-then-delta replication** (§3.2) — hand-rolled vs library still open.
4. **UTC for the event clock** (§5).
5. **`Shared/Config` stays pure** (§2) — a real constraint on future code, and the reason CI can
   verify balance at all.
