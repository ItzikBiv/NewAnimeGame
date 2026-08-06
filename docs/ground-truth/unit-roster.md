# Source game — unit roster, stat model and HUD

Evidence: 38 owner screenshots (IMG_1356–IMG_1393), captured at waves 157–175 on an
end-game account (`ItzikBiv`, wave 199, 358M gold, Index 41/85).

Grading, as in `source-game-teardown.md`:
**[C]** confirmed on screen · **[D]** derived from confirmed numbers ·
**[I]** inferred · **[?]** open · **[OURS]** our design decision.

Nine of the screenshots are the **INDEX** panel, which lists every unit in the game
in rarity order whether or not it has been collected. That is the closest thing to a
published unit list the source game has, and it settles several things the earlier
teardown left open.

---

## 1. The rarity ladder has EIGHT bands, not seven

[C] The Index orders units: **Common → Rare → Epic → Legendary → Mythic → Secret →
God → Limited**.

`Limited` is not a source-of-acquisition flag bolted onto some other rarity — it is
its own band, printed on the card the same way `God` is, and it sits *after* God in
the Index. Our `Rarities.luau` had seven tiers and modelled Limited as a `UnitSource`.
The band is real and needs to exist.

This does **not** change the roll pool. Per the project owner, limited units cannot be
summoned at all; they come from the Shop or from events. So Limited is a rarity that
is never in the roll table — which is exactly the distinction `UnitSource` was already
drawing, now applied to a band rather than to scattered units.

## 2. Roster (Index, 85 slots, 41 collected)

`???` = an Index slot the owner has not yet collected, so the name is masked. Counts
per band are read off the Index grid (6 tiles per row); named entries are [C].

| Band | Named on screen | Slots |
|---|---|---|
| Common | Itadoro, Usoff, Luppi, Keririn, Zero | 5 |
| Rare | Sukora, Goke, Mika, +2 `???` | 5 |
| Epic | Manji, +6 `???` | ~7 |
| Legendary | Nonomi, Truck, Goji, Sakuna, Noruto, Saitomo, +2 `???` | ~8 |
| Mythic | Kashimi, Joti, Kiwusuke, Rengundam, Orihemi, Brocolli, Acer, Hoshira, Kokushiro, Yoriki, Shimo Haya, +1 `???` | ~12 |
| Secret | Yutta, Megumo, Gyomain, Kenie, Ulquiopta, Brakura, Jerin, Yuwah, Fryren, Deyo, +1 `???` | ~11 |
| God | Goji (Shinjuku), Michael, Wise, Bills, Remura, +`???` | ~8 |
| Limited | all `???` on this account | ~20 |

[C] `Goji` appears twice — once as a Legendary and again as **`Goji (Shinjuku)`** at
God. So the roster deliberately reuses a character across bands with a parenthesised
variant name. Our unit ids must therefore key on the full name, not the character.

[I] The names are deliberate near-misses of real anime characters (Itadori→Itadoro,
Gojo→Goji, Usopp→Usoff, Goku→Goke, Sukuna→Sakuna, Ulquiorra→Ulquiopta, Frieren→Fryren,
Broly→Brocolli). Per the owner's 1:1 directive we carry them across as-is. `Unit.id` is
a stable internal key and `Unit.displayName` is the only thing rendered, so renaming the
roster later is a data edit on one field per unit and touches no save data.

## 3. Units have FOUR stats, not one power number

[C] Every unit card shows exactly: **Attack · Defense · Health · Speed**.

This is the single biggest correction in this document. Our `Power.luau` collapses a
unit to one scalar `power`. The source game does not. Observed ranges:

- **Attack** — 65 to 16,875. The headline number.
- **Health** — 1,200 to 27,000.
- **Defense** — 1.06 to 1.50. A *small multiplier*, not a flat armour value.
- **Speed** — 0.6 to 3.5. [I] attacks per second; a Speed 3 unit with 7,000 Attack is
  a glass cannon, which is exactly how Shimo Haya's block reads.

[D] **DPS ≈ Attack × Speed** orders the roster far more sensibly than Attack alone.
Kenie (Secret) has *less* Attack than Ulquiopta (Secret) but 3.6× the Health — the two
are a tank and a damage dealer, not a weak unit and a strong one.

## 4. Roles are real: DAMAGE / TANK / SUPPORT

[C] The Index has a role filter row: `ALL · DAMAGE · TANK · SUPPORT`, alongside the
mutation filter column.

[D] The stat blocks confirm the roles are backed by numbers rather than being
cosmetic. Within Secret alone: Ulquiopta 7,500 ATK / 7,500 HP (damage), Gyomain
4,000 ATK / 25,000 HP (tank), Deyo 420 ATK / 14,000 HP (tank or support).

## 5. Observed stat blocks

All at Lv. 1 except where noted. `—` = Normal (no mutation).

| Unit | Band | Mutation | Attack | Defense | Health | Speed |
|---|---|---|---:|---:|---:|---:|
| Itadoro | Common | Cursed [?] | 65 | 1.21 | 1,705 | 1 |
| Goke | Rare | — | 157.5 | 1.06 | 1,200 | 1.1 |
| Mika | Rare | Hollow | 198 | 1.17 | 1,395 | — |
| Goji | Legendary | Hollow | 1,125 | 1.33 | 4,725 | 0.8 |
| Sakuna | Legendary | Hollow | 1,125 | 1.33 | 4,725 | 0.75 |
| Nonomi | Legendary | Diamond | 2,137.5 | 1.50 | 15,000 | 0.7 |
| Acer | Mythic | — | 360 | 1.20 | 3,500 | 0.6 |
| Hoshira | Mythic | — | 430 | 1.20 | 4,165 | 0.6 |
| Brocolli | Mythic | — | 600 | 1.22 | 6,400 | — |
| Orihemi (Lv. 2) | Mythic | — | 612.5 | 1.38 | 6,440 | — |
| Kokushiro | Mythic | — | 700 | 1.15 | 5,780 | 1 |
| Yoriki | Mythic | — | 1,250 | 1.15 | 5,780 | 1 |
| Joti | Mythic | — | 1,750 | 1.50 | 10,000 | — |
| Rengundam | Mythic | Diamond | 2,025 | 1.29 | 11,250 | 1.2 |
| Kashimi | Mythic | Gold | 5,250 | 1.28 | 15,625 | 0.8 |
| Shimo Haya | Mythic | — | 7,000 | 1.20 | 3,145 | 3 |
| Deyo | Secret | — | 420 | 1.28 | 14,000 | — |
| Jerin | Secret | — | 625 | 1.25 | 18,975 | — |
| Fryren | Secret | — | 2,000 | 1.25 | 5,800 | 3.5 |
| Yuwah | Secret | — | 3,000 | 1.12 | 8,500 | — |
| Gyomain | Secret | — | 4,000 | 1.32 | 25,000 | 2 |
| Kenie | Secret | Diamond | 4,725 | 1.37 | 27,000 | 1.8 |
| **Ulquiopta** | Secret | **—** | **7,500** | 1.25 | **7,500** | 2.5 |
| **Ulquiopta** | Secret | **Gold** | **11,250** | 1.28 | **9,375** | 2.5 |
| **Ulquiopta** | Secret | **Diamond** | **16,875** | 1.29 | **11,250** | 2.5 |
| Megumo | Secret | Demon | 15,000 | 1.31 | 17,500 | 1 |

**Base stats are hand-authored per unit, not derived from rarity.** Mythic spans
360→7,000 Attack. There is no formula to recover here; there is a designed roster.

## 6. Mutation multipliers — [D], from a controlled triple

The three Ulquiopta rows are the same unit at the same level under three mutations,
which is as clean an experiment as screenshots can give:

| Mutation | Attack | Health | Speed | Defense |
|---|---:|---:|---:|---:|
| Normal | ×1.00 | ×1.00 | ×1.00 | 1.25 |
| Gold | **×1.50** | **×1.25** | ×1.00 | 1.28 |
| Diamond | **×2.25** | **×1.50** | ×1.00 | 1.29 |

[C] **Mutations do not touch Speed.** All three Ulquiopta rows read 2.5.

[D] Diamond's Attack multiplier is exactly Gold's squared (1.5² = 2.25), which reads
like a deliberate ladder rather than two loose numbers.

[I] Defense moves very little (1.25 → 1.28 → 1.29). Both `×1.02 / ×1.035` and a flat
`+0.03 / +0.04` fit the two data points; two points cannot separate them. Treat
Defense as near-flat under mutation until there is better evidence.

[?] Hollow, Demon, Destroyer, Slayer and Astronaut multipliers are unmeasured — no
controlled pair exists in these screenshots. Goji and Sakuna, both Legendary Hollow,
show *identical* 1,125 / 1.33 / 4,725, which either means those two share a base block
or means Hollow overwrites stats outright. Unresolved.

[?] Level scaling is unmeasured. Orihemi at Lv. 2 (612.5 / 6,440) and Brocolli at
Lv. 1 (600 / 6,400) are different units, so the difference cannot be attributed to the
level. Levels up to 36 were seen in the inventory grid.

[?] `Cursed` appears in the mutation slot on Itadoro's card but is not one of the
Index's mutation tabs. Either a mutation that scrolls off the visible tab list, or the
card shows a trait in that position for some units.

## 7. Mutation tabs — [C]

The Index's mutation filter column reads, top to bottom:
`NORMAL · GOLD · DIAMOND · DEMON · DESTROYER · HOLLOW · ASTRONAUT`.

This confirms the roster in our `Mutations.luau` and confirms Astronaut is a real,
listed mutation rather than an admin curiosity. `Slayer` is visible on inventory tiles
("Slayer Rengundam") but did not fit in the visible tab column.

[C] In-game hint text: **"Mutation Events start every 15 minutes!"** — our 15-minute
mutation clock is correct.

## 8. Index completion bonus — [C]

**"Get 5% Cash Boost every 5 unique anime!"** printed on the Index panel.

At 41/85 collected that is +40% gold. This is a meaningful economy multiplier we had
not modelled at all, and it gives collection a purpose beyond completionism.

## 9. Wave and economy anchors — [C]

A second wave-HP anchor, far deeper than the first:

- Wave 175, boss **`Jigi`**, HP bar: **8,030,480.2**.
- Enemy counts across waves 157–175: 3, 5, 5, 5, 5, 5, 5, 5, 6, 7, 7, 7, 7, 9, 10.
  **Range 3–10** — our `enemyCount` clamp is right.
- Gold deltas per wave around wave 170: ~42k–58k, call it ~50k/wave.
- Account totals: wave 199 reached, 358M gold banked.

[D] **The base curve is fine; Jigi is the thing we cannot place.** The existing
anchor is a *normal* enemy at wave 174 reading 481,324 HP, and `100 × 1.05^(wave-1)`
gives 463,547 there — 3.7% low, which is the tolerance the tests already assert.

Jigi is not comparable to that. At 8,030,480 it is **16.7× a normal enemy of its own
wave** (~486,700). Our `BOSS_HP_MULTIPLIER` is 8, so Jigi is roughly twice what our
model calls a boss.

[?] That is *not* enough to retune the multiplier, because we do not know Jigi is a
boss in our sense. Wave 175 is not a multiple of 10, so it breaks our boss cadence
outright, and no other captured wave in 157–174 shows a named HP bar. Three readings
fit: bosses land every 25 waves rather than every 10; Jigi is an "elite" that can
appear inside an ordinary wave; or named bosses are a separate ladder from the wave
cadence. Retuning on one sighting would encode the wrong one of the three.

What to do with it: leave `BOSS_HP_MULTIPLIER` at 8, and treat "what makes a wave a
boss wave" as the open question. One more screenshot — any wave between 176 and 200
with or without a named bar — would settle it.

## 10. HUD layout — [C]

Worth recording because we are rebuilding this screen.

- **Left rail, top to bottom:** Pass · Shop · ANIMES · UPGRADES · ITEMS · INDEX ·
  PROFILE · TRADE
- **Top left:** `#` (server/friends) · Codes
- **Top centre:** `Wave: N` · `STOP` · `Auto: On` · `Skills` · `n/m Enemies left`
- **Top right:** a three-tab leaderboard — People · Waves · Gold — showing rank, name,
  wave and gold for the top players
- **Bottom right:** `Friend Gold Boost: 0%` and the gold total
- **Bottom centre:** the boss HP bar (`Jigi  6976068.7/8030480.2 HP`)
- **ANIMES panel:** a search box, a 4-wide scrolling grid of owned units each showing
  mutation + name + `Lv. N`, a detail card on the left with the four stats, and
  `PICKUP ALL` / `EQUIP BEST` / `Display` buttons
- **Inventory capacity is upgradeable:** observed 225 → 335 → 395
- Placing a unit when the board is full prints **"Your hotbar is full!"** — so the
  placement grid is called the *hotbar*, and it refuses rather than swapping

[C] `EQUIP BEST` exists. That is a one-button auto-fill of the hotbar, and it implies
the game has a canonical "which unit is better" ordering — most likely the DPS ordering
in §3.
