# Source-Game Teardown — *Roll Anime to Fight!*

Ground-truth reference for the clone. Everything here is derived from **direct observation of
the live game** (screenshots supplied by the project owner, 2026-08), not from wikis.

Roblox place: `107653945083776` · Developer: *Another Slop*

## How to read this document

Every claim carries a confidence marker. Do not silently promote a claim up the ladder.

| Marker | Meaning |
|---|---|
| **[C]** | **Confirmed** — read directly off a screenshot, or exactly stated by the devs in the official Discord FAQ |
| **[D]** | **Derived** — a formula fitted to two or more confirmed data points, and consistent with the observed MAX value |
| **[I]** | **Inferred** — a reasonable reading of partial evidence; needs verification before it drives code |
| **[?]** | **Open question** — we do not know; listed in [Open Questions](#open-questions) |

> **Rule for implementers:** an **[I]** or **[?]** may not be encoded as a magic number in gameplay
> code. Put it in a config table with a comment pointing back to this file, so a correction is a
> one-line data change.

---

## 1. Genre and core loop

**[C]** This is a **gacha auto-battler / wave-defense**, not a fighting game. The name is misleading:
the player never fights directly. Units are placed on a grid and fight autonomously.

```
spend gold ──► ROLL a unit ──► place on grid (4→12 slots)
    ▲                                    │
    │                                    ▼
    └──── earn gold ◄──── survive wave ◄─┘
              │
              └──► trait shards + essence ──► Trait Machine / Clone Machine
```

**[C]** Waves are **endless** and the wave counter **persists across sessions** — observed at Wave 151
sitting idle at base, and Wave 174 mid-combat. `START` begins a wave; the button becomes `STOP`
while a wave is live.

**[C]** The server is **shared and social, but play is per-player.** Each player has their own
arena, labelled `<PlayerName>'s Base` (observed: `ItzikBiv's Base`, `TraitUnsaved's Base`,
`lucier's Base`). Players see each other's bases and wave numbers.

---

## 2. The battle grid

**[C]** Two opposing tile sets, visually distinct:

| Side | Tile colour | Count |
|---|---|---|
| Player units | Blue outline | **4 at start → 12 at max** (Slot Upgrade) |
| Enemies | Red outline | **16** |

**[C]** Wave progress is shown as `N/M Enemies left` on a red bar (observed `8/8`, `5/5`, `4/9`,
`0/7`, `3/3`, `2/7`, `5/6`). Enemy count per wave varies — it is **not** a fixed number.

**[C]** Units and enemies both display floating health bars with **fractional HP**
(`15228.8/15228.8 HP`, `264,824/481,324`). Damage numbers pop in colour (`-52,500`, `-100,000`);
green numbers (`+1,145`) indicate healing → **support units heal**.

**[C]** Enemies observed at `Lv. 0`. Enemy names seen: `Black Ant`, `Red Ant`, `Hamtarts`, `Alien`,
`Turbo Dada`, `Bills`, `Berooh`, `Frozen Demon`. Note some names double as player units.

---

## 3. Rarity ladder

**[C]** Seven tiers, confirmed by the complete set of Essence items in the inventory *and* by roll
labels — there is **one essence per rarity**:

```
Common · Rare · Epic · Legendary · Secret · Mythic · God
```

**[C]** There is **no "Uncommon" tier.** Several public wikis list one; the essence set and the
index tabs both disprove it. Trust this document.

**[C] Ordering — RESOLVED.** Previously an open question. Two independent signals agree:

| Signal | Reading |
|---|---|
| Pity counter length | Legendary ~50 < Mythic ~100 < Secret ~250 |
| Robux essence price | Legendary R$49 < Mythic R$129 < Secret R$249 < God R$499 |

So the ladder is **Common < Rare < Epic < Legendary < Mythic < Secret < God**, and the wikis
claiming Secret sits *below* Mythic are wrong.

This also settles what the third pity counter is: the Roll Machine shows exactly three, for
**Legendary, Mythic and Secret**. **God has no pity counter at all** — there is no floor under a
dry streak, which is precisely what keeps it out of reach.

**[C]** Each rolled unit shows a **cash value** on its podium. Observed:

| Unit | Rarity | Value |
|---|---|---|
| Luppi | Common | `$275` |
| Keririn | Common | `$200` |
| Usoff | Common | `$300` |
| Got | Epic | `$6,000` |
| Sakuna | Legendary *(Diamond)* | `$7,500` |
| Noruto | Legendary | `$24,000` |

**[I]** Value is **per-unit**, not per-rarity — two Legendaries differ by 3.2×. It is likely a
hand-authored field on each unit, so treat it as unit data, not a formula.

---

## 4. Mutations

**[C]** A mutation is a **second, independent axis** layered on top of rarity. It is rendered as a
label *above* the rarity on the unit card (e.g. `Diamond` / `Legendary` / `Sakuna`), with a distinct
visual effect in battle.

**[C]** Mutations confirmed from the Index tabs, plus **Slayer** from the dev FAQ:

```
NORMAL · GOLD · DIAMOND · DEMON · SLAYER · DESTROYER · HOLLOW · ASTRONAUT
```

**[C]** `[HINT] Mutation Events start every 15 minutes!` — the hint bar. The dev FAQ gives the
**exact schedule**, and it explains what the hint means: the 15 minutes is a *rotation*, not a
single recurring event. Each mutation is rollable **only during its slot**:

| Server clock | Mutation |
|---|---|
| `xx:00` | **Slayer** |
| `xx:15` | **Demon** |
| `xx:30` | **Destroyer** |
| `xx:45` | **Hollow** |
| — | **Astronaut** — *"Every Admin Abuse"*, never on the clock |

**[I]** Normal, Gold and Diamond have no slot, so they are treated as always-available.
That makes the live pool at any moment **3 baseline mutations + exactly 1 event mutation.**

> This is a bigger deal than it looks. Mutation chasing is not "roll more" — it is **"roll at
> the right minute."** It converts the gacha from a pure money sink into a scheduled activity
> that pulls players back on a 15-minute heartbeat. Any clone that makes all mutations
> permanently rollable loses that retention hook entirely.

**[C]** **Astronaut is admin-only** — it is listed among Admin Abuse rewards, not on the clock.
It cannot be farmed, which is what makes it the scarcest mutation.

**[C]** Paid bundles advertise `Chance of Mutation` as a selling point.

> **This is the load-bearing design insight.** Rarity alone is not the power axis — a
> mutated low-rarity unit can beat a clean high-rarity one. If the clone flattens the
> rarity × mutation interaction, it reproduces the shell and loses the game.

---

## 5. Merging / levelling units

**[C]** Exact rule, quoted from the developers' Discord FAQ:

> *"First, you need 2 of the same unit with the same mutation and level. Place your 1st unit and
> then hold/equip your 2nd unit. When equipped, place your 2nd unit on your 1st unit — must be the
> same unit."*

Three conditions, all required:

1. same unit identity
2. **same mutation**
3. **same level**

**[C]** The merge interaction is **physical, not menu-driven**: place unit A on the grid, equip
unit B, then drop B onto A's tile.

**[I]** This implies a binary merge tree (2×Lv1 → Lv2, 2×Lv2 → Lv3 …), so a Lv*n* unit costs
2^(n−1) base copies. Observed levels are low (`Lv. 1`, `Lv. 2`) even on a mature 50M-gold account,
which is consistent with an expensive tree.

### Trait retention on merge — **[C]**

A separate FAQ answer, and easy to get wrong:

> *"Firstly place the unit you wanted to keep the trait, and then put the other unit you don't want
> the trait or doesn't have a trait above it when fusing."*

**The unit placed FIRST (the base) keeps its trait. The unit dropped ON TOP is consumed and its
trait is destroyed.**

This makes merge order a real decision with a real cost — players lose traits to it, which is why
the question is in the FAQ at all. The merge UI must make which unit is the base unmistakable, or
we will reproduce the bug rather than the feature.

---

## 6. Upgrades — **fully derived**

**[C]** Four upgrades, all competing for the same gold pool. Two independent save-states were
captured, which is enough to fit every curve and check it against the observed MAX.

### Observed data points

| Upgrade | State A | State B (all MAX) | Next-level cost seen |
|---|---|---|---|
| Gold | `Lv. 18` → `x2.7` | `Lv. 25` → `x3.4` | `$840,000` |
| Luck | `Lv. 20` → `x10.5` | `Lv. 25` → `x13` | `$1,365,000` |
| Slot | `Lv. 8` | `Lv. 9` → `12` | `$5,000,000` |
| Inventory | `Lv. 3` → `125` cap | `Lv. 7` → `225` | `$500,000` |

### Derived formulas

**[D] Gold Upgrade** — *"Increase the amount of gold you get from killing the enemies!"*
```
multiplier = 1 + 0.1 × (level − 1)        level 1..25
```
Check: Lv18 → 1 + 1.7 = **2.7** ✓ · Lv25 → 1 + 2.4 = **3.4** ✓ (MAX)

**[D] Luck Upgrade** — *"Increase the chance of rolling rarer animes!"*
```
multiplier = 1 + 0.5 × (level − 1)        level 1..25
```
Check: Lv20 → 1 + 9.5 = **10.5** ✓ · Lv25 → 1 + 12 = **13** ✓ (MAX)

**[D] Slot Upgrade** — *"Unlock more slots to place more animes!"*
```
slots = level + 3                          level 1..9
```
Check: Lv1 → **4** ✓ (matches owner's "you start with 4") · Lv9 → **12** ✓ (MAX)

**[D] Inventory Upgrade** — *"Increase inventory capacity to store more animes!"*
```
capacity = 50 + 25 × level                 level 1..7
```
Check: Lv3 → **125** ✓ (cross-checked against `Inventory: 12/125` in the same save-state) ·
Lv7 → **225** ✓ (MAX)

**[?] Cost curves are NOT derivable** — only one price point per upgrade was captured. The four
costs above are next-level prices at those specific levels, nothing more. Needs more data.

**[C]** Every upgrade can also be bought directly with Robux (`R$29`, `R$99` buttons observed).

---

## 7. Traits

**[C]** Traits are rolled at the **Trait Machine** using **Trait Shards**, and applied to a chosen
unit. The machine has an `Auto Roll` toggle, an `Auto Stop` toggle, and a `TRAIT INDEX`.
**[C]** *"Obtain trait shards by killing enemies!"*

### Complete trait table — **[C]** verbatim from the developers' Discord FAQ

| Tier | Trait | Effect |
|---|---|---|
| **Rare** | Sharp | +10% Crit Chance, +25% Crit Damage |
| | Swift | 10% Faster Attacks |
| | Strong | +10% Damage |
| **Epic** | Deadly | +15% Crit Chance, +30% Crit Damage |
| | Rush | 15% Faster Attacks |
| | Powerful | +20% Damage, +10% Health |
| **Legendary** | Deadeye | +35% Crit Chance, +45% Crit Damage |
| | Juggernaut | +50% Damage, +35% Health, 10% **Slower** Attacks |
| | Lethal | +35% Damage, +30% Crit Chance, +40% Crit Damage |
| | Royal | +25% Damage, +15% Health, +25% Cash |
| **Mythic** | Entrepreneur | +45% Damage, +25% Health, 10% Faster Attacks, +65% Money |
| | Reaper | +90% Damage, +35% Health, 16% Faster Attacks, +35% Crit Chance, +45% Crit Damage |
| | Cloner | +40% Damage, +60% Health, **summons 2 units instead of 1** |
| | **Ghost** | +100% Damage, +100% Health, **resurrects on death with 80% stats** |
| | Superior | +200% Damage, +100% Health, 20% Faster Attacks, +40% Crit Chance, +65% Crit Damage |
| **God** | Cursed | +400% Damage, +200% Health, 25% Faster Attacks, +65% Cash, +50% Crit Chance, +100% Crit Damage |
| | **Viking** | +200% Damage, +750% Health, 25% Faster Attacks, +50% Crit Chance, +150% Crit Damage |

**17 traits total.** Two of the Mythics — **Cloner** and **Ghost** — are not stat lines at all but
unique mechanics (extra summon, one revive). They need real implementation, not a multiplier.

**[C]** There are **two God traits**, and they are deliberately different shapes: Cursed is the
damage-and-economy pick, Viking is the survivability pick (+750% Health). Neither dominates.

**[C]** God-tier trait odds are **0.02%**, displayed in-game.

**[C]** Trait tiers are **Rare → Epic → Legendary → Mythic → God**. Note this ladder **omits
Common and Secret** — it is *not* the same ladder as unit rarity. Do not share one enum.

### `SPD` sign convention — **[C] RESOLVED**

Previously flagged as a blocking open question. The full FAQ settles it: it lists Viking as
**"25% Faster Attacks"**, while the Trait Machine renders the same trait as **"−25% SPD"**.

Both describe one effect. **`SPD` is the attack *cooldown*** — lowering it by 25% makes the unit
attack faster. So a negative `% SPD` in the game's UI is a *positive* attack-speed bonus.

**Juggernaut's "10% Slower Attacks" is the only genuine downside in the entire trait table.**

**[C]** Trait Shard packs (Robux): `1× = R$19`, `10× = R$179`, `50× = R$899`, `100× = R$1749` *(BEST)*.

---

## 8. Roll machine

**[C]** A physical `ROLL` / `Summon` button in the world, flanked by podiums displaying recent pulls.
The player's current luck multiplier is shown beside it (`x10.5`, `x13` — matching Luck Upgrade).

**[C]** **Three simultaneous pity counters** are displayed, e.g.:

```
Legendary in 43 Rolls
Mythic    in 42 Rolls
Secret    in 91 Rolls      ← label obscured in captures; identified in §3
```

**[C]** Readings across sessions:

| Session | Legendary | Mythic | Third |
|---|---|---|---|
| A | 37 | 86 | 235 |
| A (later) | 38 | 67 | 236 |
| B | 43 | 42 | 91 |

**[I]** These are **countdowns that reset on hit**. Legendary rising 37 → 38 while Mythic fell
86 → 67 means a Legendary was hit and its counter reset. Rough caps: Legendary ~40–50,
Mythic ~100, third ~250.

**[C]** `x10 LUCK in:` — a **timed server-wide luck event** with its own countdown, separate from
the Luck Upgrade.

**[?] Base drop rates per rarity are not published anywhere** and cannot be read off a screenshot.
**Project owner's call: we design our own.** See [Our roll odds](#our-roll-odds) below.

### Limited units are not in the roll pool — **[C]**

Per the project owner: **limited units cannot be summoned at all.** They come only from the **Shop**
or from **events**, and are marked `Limited — Unobtainable` once their window closes (observed on
the Overlord Gacha: `Aldedo`, `Als`, `Entomancer`, `Bloodtear`).

**A unit's rarity does not imply it is rollable.** Every unit needs an explicit source
(`roll` / `shop` / `event`) and the roll pool must filter on that, not on rarity.

### Our roll odds

Designed, not cloned — a 1:1 numeric match is impossible from public data. Shaped to satisfy the
three constraints we *do* have: the pity caps imply the natural rates; God must stay extreme even
at max luck; God has no pity floor.

| Rarity | Base (luck x1) | At max luck (x13) |
|---|---|---|
| Common | 62.1% | 32.9% |
| Rare | 25% | 36.7% |
| Epic | 8% | 15.2% |
| Legendary | 1 in 35 | 1 in 11 |
| Mythic | 1 in 70 | 1 in 22 |
| Secret | 1 in 180 | 1 in 64 |
| **God** | **1 in 40,000** | **1 in 18,530** |

Luck scales each tier by `luck^exponent` with the exponent chosen per tier, so luck is felt
strongly in the Legendary/Mythic band (**3.2×** at max) while barely moving God (**2.2×**) —
matching the owner's *"god tier is really rare even with luck multiplier"*.

Because those exponents rise with rarity, unchecked they would **invert the ladder at high luck**,
and luck genuinely stacks here (x13 upgrade × the x10 LUCK event × Luck Potions). So each tier is
clamped to at most 60% of the tier below it. The ordering therefore holds at *any* luck value —
regression-tested up to x10⁹.

---

## 9. Machines and side modes

| Feature | Evidence | Notes |
|---|---|---|
| **Roll Machine** | **[C]** | Core gacha. Gold → units. |
| **Trait Machine** | **[C]** | Trait Shards → traits. Auto Roll / Auto Stop toggles, Trait Index. |
| **Clone Machine** | **[C]** | Select a unit → `CLONE`, paid in **Essence** of matching rarity, on a **timer** with a `−50% Time` option. *"Obtain essence by killing enemies!"* |
| **Evolution Machine** | **[C]** | Sits beside the Trait Machine. **[I]** consumes the special items (Six Eyes, Cursed Finger, Cursed Womb, Sakuna's Fragment) to evolve units. Contents never captured. |
| **Infinite Tower** | **[C]** | Separate mode, entered with an **Infinite Ticket**. *"Buy tickets here to enter the Infinite Tower."* Has its own `Highest Floor` leaderboard. |
| **Spin Wheel** | **[C]** | `Free Spin in 00:26:34` → ~30-minute free-spin timer. |
| **Admin Abuse (AA)** | **[C]** | A live, staff-run event on a published schedule. See below. |

### Admin Abuse — **[C]**

A scheduled, staff-triggered live event. Per the dev FAQ it delivers:

- **Free items** — traits, essence, and more
- **The Astronaut mutation** — its *only* source
- **An obby in the Lobby** — complete it for rewards
- **A boss spawn** — defeat it for rewards

This is the game's live-ops layer, and it carries real design weight: it is the only route to the
rarest mutation, and it is the only content that isn't a grid battle. It also implies **a lobby
space separate from the player's base arena**, which nothing else in the teardown required.

**[I]** The name suggests it is triggered manually by staff rather than on a hard timer, though a
schedule is published in the Discord's events channel. Our clone would need either a scheduled job
or an admin command — a design call for the GDD, not a fact about the source game.

---

## 10. Items and currencies

**[C]** Complete inventory, read off a maxed account:

**Currency**
- `Gold` — primary soft currency (observed `50,878,965`)
- `Trait Shard` — trait rolls (`x760`)

**Essence** — one per rarity, drops from kills, feeds the Clone Machine
`Common (x648)` · `Rare (x541)` · `Epic (x425)` · `Legendary (x48)` · `Secret (x57)` · `Mythic (x90)` · `God (x17)`

**Evolution materials [I]**
`Six Eyes (x19)` · `Cursed Finger (x5)` · `Cursed Womb (x1)` · `Sakuna's Fragment (x1)`

**Tickets**
`Trading Ticket (x6)` · `Infinite Ticket (x1)`

**Consumables**
`Luck Potion (x13)` · `Gold Potion (x4)` · `Super Time Potion (x1)`

**[C]** Essence packs sell for Robux: `Legendary 10× = R$49`, `Mythic 10× = R$129`,
`Secret 10× = R$249`, `God 10× = R$499`. This pricing ladder is one of the two signals that
resolved the rarity order in §3.

**[C]** How to get **God Essence**, per the dev FAQ — exactly two routes:

1. **Farm waves** — small chance per kill, *"recommended to afk"*
2. **Buy with Robux** — at the Clone Machine

That first route is worth noting: the devs' own advice for their rarest crafting material is *leave
the game running*. Idle throughput is a first-class progression path here, not an afterthought —
which is consistent with the `Auto` toggle and the `2x` speed control being permanent HUD fixtures.

---

## 11. Unit index and stats

**[C]** The **Index** is a collection screen with:
- **Rarity** columns (Common → God)
- **Mutation** tabs: `NORMAL · GOLD · DIAMOND · DEMON · DESTROYER · HOLLOW · ASTRONAUT`
- **Role** filters: `ALL · DAMAGE · TANK · SUPPORT`
- Completion reward: **`Get 5% Cash Boost every 5 unique anime!`**
- Progress observed: **`26/73`** → **73 units** in the game at capture time

**[C]** Four unit stats: **Attack · Defense · Health · Speed**

**[C]** The **Animes** (inventory) screen has `Search anime…`, a `Display` toggle, and
`PICKUP ALL` / `EQUIP BEST` buttons.

### Roster observed

**[C]** Every name is **already a parody** — the game does not ship real anime character names.

| Seen in-game | Evidently riffing on |
|---|---|
| Noruto | Naruto |
| Sakuna | Sukuna |
| Luppi | Luffy |
| Goji / Goji (Shinjuku) | Gojo |
| Megumo | Megumi |
| Yutta | Yuta |
| Itadoro | Itadori |
| Keririn / Keriri | Krillin |
| Bills | Beerus |
| Brocelli | Broly |
| Orihemi | Orihime |
| Kokushiro | Kokushibo |
| Fryren | Frieren |
| Usoff | Usopp |
| Kiwusuke | Yusuke |

Also observed, source unclear: `Wise`, `Brakura`, `Yuwah`, `Remura`, `Jerin`, `Kenie`, `Zero`,
`Sukora`, `Coke`, `Acer`, `Hoshira`, `Shimo Haya`, `Berooh`, `Got`, `Turbo Dada`, `Alien`,
`Aldedo`, `Als`, `Entomancer`, `Bloodtear`.

> **Consequence for our clone.** The IP risk flagged at kickoff is materially lower than assumed —
> "clone 1:1" means cloning *parody* names, which is what the source game already does. We should
> still coin our own parodies rather than copy theirs (their exact names are their creative work,
> even if the underlying joke is not), but we are not shipping licensed characters either way.

---

## 12. Combat controls

**[C]** Persistent top HUD: `Wave: N` · `START`/`STOP` · `2x` speed toggle · `Auto: On/Off` · `Skills`

**[C]** The **Skills** panel lists skills with per-skill charge counts (`2`, `1`, `1`) and an
individual **`Auto`** toggle on each. Skills are attached to specific units (`Bills`, `Wise`,
`Yuwah` observed as skill owners).

**[C]** `Auto` mode runs waves unattended — the game is designed for idle/AFK play.

---

## 13. Social and progression

**[C]** **Leaderboards** — in-server boards for `People · Waves · Gold`, plus `Highest Waves`,
`Highest Gold`, `Highest Floors`. Sample: `TraitUnsaved — 199 waves — 9M`, `ItzikBiv — 82 — 1M`,
`luciel — 80 — 6.3M`.

**[C]** **Profile** — searchable by player name, shows `TITLES`, a display team, and lifetime stats:
`Rolls (1.01K)` · `Highest Wave (82)` · `Highest Tower` · `Highest Cash (7.5M)`

**[C]** **Trade** — player-to-player, gated by `Trading Ticket`.

**[C]** **Friend Gold Boost** — `+25%` observed with friends in-server, `0%` alone.
**[I]** ~5% per friend, capped.

**[C]** **Codes** — a `Codes` button top-right; codes grant Gold and Trait Shards.

**[C]** **Group Rewards** — an in-world reward for joining the Roblox group.

---

## 14. Monetization surface

**[C]** Observed, for parity reference only — we are not obliged to clone the paywall.

- **Shop** tabs: `SPECIAL OFFERS · FEATURED · CURRENCY · PASSES`
- **Starter Pack** — `R$49`
- **Sorcerer Bundle** — `Chance of Mutation`; contents `Megumo / Yutta / Goji (Shinjuku) / 50× Trait Shard`
  with **published odds `45% / 30% / 10% / 5%`**
- **Overlord Gacha** — `LIMITED`; `Aldedo / Als / Entomancer / Bloodtear`; marked
  `Limited — Unobtainable` once the window closes
- **Rarity bundles** — `MYTHIC BUNDLE (R$399)`, `SECRET BUNDLE (R$699)`, `GOD BUNDLE (R$1299)`
- **VIP Chest** — `R$209`, VIP only
- **Game Pass** button with an unread badge
- Trait Shard packs and Essence packs — §7 and §10

---

## Open Questions

Ranked by how much they block implementation.

1. **[?] Upgrade cost curves.** One price point captured per upgrade. Need ~3 consecutive levels of
   any one upgrade to fit properly. Current curves are placeholders bounded only to an order of
   magnitude.
2. **[?] Wave scaling** — enemy HP/count/reward as a function of wave number. Two anchors only
   (Wave 151 idle, Wave 174 with 8 enemies at ~481k HP). **Needed for the vertical slice.**
3. **[?] Mutation multipliers.** The full mutation *list* and *schedule* are now confirmed, but not
   one multiplier is visible anywhere. Ours is a designed ladder topping out at 6.5×.
4. **[?] Evolution Machine contents and recipes.** Never captured. We know the likely inputs
   (Six Eyes, Cursed Finger, Cursed Womb, Sakuna's Fragment) but not what they produce.
5. **[?] Infinite Tower rules** — floor scaling, rewards, ticket cost.
6. **[?] Skill system detail** — what skills exist, cooldowns, how they attach to units. The HUD
   shows per-skill charge counts and individual `Auto` toggles, but no skill list was captured.
7. **[?] Trait roll odds below God.** Only the God tier's 0.02% is confirmed.
8. **[?] Checkpoint system.** Public sources describe wave-skip checkpoints; **no screenshot or FAQ
   answer confirms this.** Do not implement on wiki evidence alone.
9. **[?] Admin Abuse trigger** — manual staff action vs. scheduled job.

### Resolved

- ~~Base roll odds~~ — unrecoverable from public data. Project owner's call: **we design our own.**
  Documented in §8, implemented in `Rarities.luau`, regression-tested.
- ~~Rarity order above Legendary~~ — **resolved** in §3. Pity length and Robux pricing agree:
  `Legendary < Mythic < Secret < God`. The third pity counter is Secret; God has none.
- ~~`SPD` sign convention~~ — **resolved** in §7. `SPD` is cooldown, so "−25% SPD" *is*
  "25% Faster Attacks". Juggernaut is the only real downside in the table.
- ~~Full mutation list~~ — **resolved** in §4. Eight mutations, with the exact event clock.

---

## Evidence index

23 screenshots supplied. **19 read successfully; 4 returned empty OCR** and have not been
incorporated: `IMG_1336`, `IMG_1339`, `IMG_1341`, `IMG_1342`.

| Screen | Source |
|---|---|
| Base overview, grid layout, HUD | inline (Wave 151) |
| Roll machine, pity counters, podiums | inline (Wave 151), `IMG_1347`, `IMG_1346` |
| Upgrade menu (MAX state) | inline (Wave 151) |
| Upgrade menu (mid-progression, with costs) | `IMG_1349` |
| Items inventory (maxed) | inline (Wave 151) |
| Items inventory (mid) | `IMG_1351` |
| Live combat | inline (Wave 174), `IMG_1334`, `IMG_1335`, `IMG_1337` |
| Trait Machine + trait odds | `IMG_1343`, `IMG_1344` |
| Clone Machine | `IMG_1338` |
| Infinite Tower | `IMG_1340`, `IMG_1333` |
| Index / collection | `IMG_1350` |
| Animes inventory + stats | `IMG_1348` |
| Shop / bundles | `IMG_1353` |
| Profile | `IMG_1352` |
| Spin Wheel + leaderboards | `IMG_1334` |
| **Discord FAQ — traits + merge rule** | `IMG_3798`, `IMG_3799` |

Screenshots live in the owner's Drive folder `1pyl1_njve1vod2PiIG0aTfdn74-qZgaI`.

**Full Discord FAQ text** supplied by the project owner (2026-08-04) — the authoritative source for
the trait table, the merge and trait-retention rules, the mutation event clock, God Essence sources,
and the Admin Abuse event. Where the FAQ and a screenshot disagree, **the FAQ wins**: it is the
developers' own words, and it resolved three open questions that screenshots alone could not.
