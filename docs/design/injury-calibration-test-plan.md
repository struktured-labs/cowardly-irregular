# Permanent Injury Calibration — Test Plan

**Status:** open, awaiting playtest + the party-HP rescale decision
**Raised by:** struktured, 2026-07-30 — *"injuries will need calibration"*
**Owner:** unassigned (battle lane on struktured's word)

Permanent injuries are a stated pillar — *"Stakes must be real"*, *"Permanent
injuries: irreversibly affect stats"*. They currently fire at the intended rate and
apply a penalty that is, on HP, invisible.

---

## 1. What the system actually does — measured, not assumed

```
BattleManager.gd:955    if randf() < 0.25          25% chance per KO'd party member,
                                                    evaluated once per battle
BattleManager.gd:6569   INJURY_TYPES               12 templates over 6 stats
BattleManager.gd:6589   level_scale = 1.0 + job_level * 0.05
                        penalty = int(base_penalty * level_scale)
```

| stat | templates | base_penalty |
|---|---|---|
| max_hp | Fractured ribs, Internal bleeding | 8, 12 |
| max_mp | Mana drain wound, Spirit fracture | 5, 7 |
| attack | Torn muscle, Damaged nerve | 2, 3 |
| defense | Cracked armor plates, Weakened guard | 2, 3 |
| magic | Mana channel scarring, Arcane burnout | 2, 3 |
| speed | Sprained ankle, Lingering fatigue | 1, 2 |

## 2. The defect — calibration drift, stated in the code's own comment

`BattleManager.gd:6562` records the intent:

> *"Penalties 5/7 ≈ 7-10% of typical caster max_mp (**Cleric 70, Mage 80**), matching
> the **8-12% calibration of the max_hp arms vs Fighter's 100 base**."*

Those bases no longer exist:

| | tuned against | ships today | drift |
|---|---|---|---|
| Fighter max_hp | 100 | **1,320** base / 1,816 at Lv1 | ~13–18x |
| Cleric max_mp | 70 | 111 | ~1.6x |
| Mage max_mp | 80 | 125 | ~1.6x |

So *Internal bleeding* — the harshest HP injury in the game — costs **12 of 1,816
HP = 0.66%** against an authored intent of 8–12%. Level scaling does not rescue it:
at L20 the penalty doubles to 24, and party HP has grown too.

**The asymmetry is the finding.** HP was rescaled and MP was not, so MP injuries
still land inside their intended band (Spirit fracture = 7 of 111 = 6.3% vs 7–10%
intended) while HP injuries are an order of magnitude light. A uniform multiplier
applied to all twelve templates would fix HP and break MP.

## 3. ⚠️ Do NOT tune the penalties yet

The party HP scale is itself under review. struktured, 2026-07-30:

> *"the Lv1 HP numbers for the party are too high"*
> *"typical JRPGs I'm mimicking start in tens to hundreds, then you get to thousands,
> and end is maybe tens of thousands"*

Lv1 party members ship at 850–1,320 — already in the mid-game band — and Mordaine,
the **World 1** boss, is the highest-HP monster in the game at 16,500. If the party
table is rescaled toward hundreds, the injury penalties become correct **without any
edit to INJURY_TYPES**.

**Tuning penalties before the rescale lands means calibrating twice, and the second
pass silently undoes the first.** This plan is written to be run *after* that call.

## 4. Test protocol

Headless, driving the real production path — not a source-text pin. The existing
guards on this system check persistence and typed-array roundtrip, not magnitude.

**T1 — penalty as a fraction of the stat, per template.**
For each of the 12 templates, at L1 / L10 / L20, against each of the 5 starter jobs:
compute `penalty / max_<stat>` and record it. This is the number the calibration
comment is about, and nothing currently measures it.

**T2 — band assertion.** Assert each template lands in its authored band:
`max_hp` 8–12%, `max_mp` 7–10%. Pick bands for the other four stats — they have
never had one stated, which is its own gap.

**T3 — frequency over a campaign.** 25% per KO per battle is the *rate*; what matters
is expected injuries across a real playthrough. Drive the story-spine integration
test and count KOs, then report expected injuries. A penalty that is correctly
calibrated but fires twice per campaign is still invisible.

**T4 — accumulation and the floor.** `Combatant.gd:1007` floors `max_hp` at
`max(1, max_hp - penalty)`. Confirm N stacked injuries degrade gracefully and cannot
zero a stat, and decide whether a cap on total accumulated penalty is wanted.

**T5 — level-scaling shape.** `1.0 + level * 0.05` is linear while stat growth may
not be. Measure whether penalty-as-a-fraction stays flat, rises, or decays across
L1→L28. Flat is almost certainly the intent; nothing asserts it.

## 5. Acceptance criteria

- Every template's penalty sits in a stated band, at every tested level, for every job.
- The band is asserted by a test that **fails** if the party table is rescaled again —
  derive the expected penalty from the live `max_<stat>`, never from a pinned literal.
  A pinned number is what let this drift silently for months.
- Expected injuries per campaign is a stated, measured number rather than an emergent one.

## 6. Prior art in this repo

The same defect class, already fixed once: a guard pinned to a coincidental absolute
value goes green on a wrong change and red on a correct one. See CLAUDE.md's
"Ratchets pinned to a COINCIDENTAL value" entry. **Assert the relationship
(penalty ÷ live max_stat), not the coordinate (penalty == 12).**
