# Victory Method Influence — Design

**Origin:** Carmelo, addendum to msg 19478 (relayed verbatim as 19479): *"HOW you beat each boss
(manual BD-style vs autobattle vs one-shot) must influence your characters, the world, and the
ending."* He asked for three things by name — (a) what the game already tracks and branches on
today, with code citations, (b) a per-boss proposal for what each victory method changes, (c) how it
ties into the existing story and ending structure without contradicting it — and ruled: **design
proposal first, nothing lands on story or endings before he reviews.**

**Status: PROPOSAL. Nothing in this document is implemented.** No flags, no scene ids, no step
types are specified here; naming and wiring are cowir-main's. This is the shape and the questions.

---

## (a) What exists today

### The one live branching mechanism

`CutsceneDirector.gd:1985-1993` — a **step-level** `condition: "playstyle"` selects from a `cases`
dictionary, falling back to `default`:

```
var playstyle = _detect_playstyle()
var cases = step.get("cases", {})
branch_steps = cases.get(playstyle, cases.get("default", []))
```

### What the detector can say

`_detect_playstyle()` at `CutsceneDirector.gd:2035` returns **exactly five strings** — `automator`,
`manual`, `grinder`, `exploiter`, `balanced`. Thresholds at `:148-150`: sample floor 20 battles,
automator above a 0.7 autobattle ratio, manual below 0.3, volume separating the rest.

The ratio's denominator is `GameState.organic_battles_won()`, which excludes the five party-unlock
duels — his own ruling of 2026-07-29, on the grounds that forced-manual tutorials say nothing about
automation habits.

`exploiter` is **categorical and outranks the ratio arms**. It keys on
`permakilled_monster_types` and `corruption_effects` (`_has_exploited_systems`) — **not** on
one-shot play. So one-shot and exploit are genuinely orthogonal in the current code, and a
one-shot build does not get routed into the exploiter arm.

### What is recorded per boss

Both stores are keyed per monster, which is what makes a per-boss design possible at all:

| store | shape | written |
|---|---|---|
| `SaveSystem.one_shot_records` (`:80`) | `{monster_id: {count, best_rank, best_setup}}` | `BattleManager` victory path |
| `SaveSystem.autobattle_records` (`:83`) | `{monster_key: {count, best_turns, best_multiplier}}` | same |

One-shot's rule is `_check_one_shot()`: every enemy dead in the same execution phase as the first
damage. Setup turns are unbounded and only set the rank (`BattleManager.gd:9135-9141`) — S at ≤1,
A at ≤3, B at ≤5, C beyond.

### Which scenes actually fork

| scene | arms authored |
|---|---|
| `world1_chapter2` | automator · grinder · exploiter · manual · default |
| `world6_chapter3` | automator · grinder · exploiter · manual · default |
| `world1_warden_encounter` | grinder · default |
| `world1_{arbiter,curator,tempo}_encounter` | default only |

**`world6_chapter3`'s five arms already answer the canon question.** Each opens *"A game without
challenge is…"* — a system to be understood (automator), a place to rest (grinder), impossible
(exploiter), still a game (manual), a story (default). Those are the Core Answers column of the
Ending Matrix in `docs/narrative_tree.md:231`, already in the player's hands.

### What does not fork

⛔ **The ending itself is linear.** `data/cutscenes/world6_ending.json` is one scene, 41 steps, and
**zero** `branch`, `choice` or `lead_branch` steps. Step types present: narration ×9, dialogue ×6,
wait ×16, set_flag ×2, and one each of letterbox_in/out, chapter_title, play/stop_music,
screen_flash, play_sfx, roll_credits.

**So "ending weight" is new structure, not a weight added to an existing fork.** This is the single
largest constraint on everything below.

### Other consumers, and what is inert

`TrialRouting.gd` (shipped `.735`) asks the Director for the same playstyle rather than re-deriving
it — the one precedent for reading the save instead of prompting, and the right one to follow.

Inert today, both worth knowing before authoring against them:

- **Line-level `_condition` is not read.** The Director's own comment at `:1986` records five
  dialogue lines in `world1_transition` / `world2_transition` carrying `_condition: "playstyle_*"`
  that play for every player — a hand-playing one is told "the automation translated."
- `playstyle_tags` has no consumer in `src/`.

---

## Three hazards any design here must clear

These are the reason this document exists rather than a patch.

**1. `completionist` has no detector value, so the Collaborator ending cannot fire as written.**
The Ending Matrix names Collaborator as the hidden fifth ending for completionists, and
`docs/novellas/ending_collaborator.md` is a finished short story. The detector returns five values
and `completionist` is not among them. **This exact key was already wired and already dead:** four
W1 encounters gated a hospitality beat on a `completionist` branch key, it never played for any
player, and it was repaired on 2026-07-28 by making the beat unconditional. The fix notes are still
in those files' `description` fields. Implementing Collaborator against the current detector would
reproduce that bug at the most expensive point in the game.

**2. `one_shot` is not a playstyle the game can detect.** It is recorded richly per monster and read
by nobody as an identity. Carmelo's three methods are manual / autobattle / one-shot; the detector's
axes are automation ratio, grind volume, and exploitation. One-shot is a sixth axis the Ending
Matrix never had.

**3. Manual victory is not recorded as a positive fact.** It is the absence of an autobattle record
and the absence of a one-shot record. That is adequate for a whole-save ratio and **cannot carry
per-boss weight** — "you fought this one yourself" is not a thing the save currently knows. A
per-boss design needs a new record, named below rather than assumed.

---

## (b) Per-boss proposal

### The premise: three relationships to a fight

The three methods are not three difficulty settings. They are three answers to *were you there?*

| method | what it says | what the party experiences |
|---|---|---|
| **Manual** | You were present. Every turn was a decision you made. | They were fought *with*. |
| **Autobattle** | You delegated. You trusted the script — and **Trust** is the player's own word for that toggle (his playtest phrasing, msg 1878). | They were trusted to handle it. |
| **One-shot** | You declined the fight. You solved it as arithmetic. | They never got to the part where it mattered. |

The third is the sharpest and it is factually true of that save: a one-shot ends in the same
execution phase as the first damage, so **the player never saw phase 2 of anything.** Every boss's
second-phase content — the dialogue, the escalation, the thing it does when it is losing — went
unwitnessed. A Calibrant that has been reading logs all game can say so.

### What each method changes, per boss, in three registers

**Register 1 — the party (characters).** Each boss defeat marks the PCs who were in the winning
formation, with the method. Accumulated across the campaign this gives each PC a disposition that
is *earned per fight* rather than set globally:

- **Fought manually** → that PC remembers the fight specifically. Later dialogue can reference the
  particular boss, because the player was there for it.
- **Won on autobattle** → the PC grows in self-reliance; their own script won. This is the spine the
  strict-5 spotlight arc already carries — the five PCs are coming-of-age individuals, and Trust
  extended or withdrawn is the arc. A PC who won three bosses unsupervised is a different person
  from one who was driven every turn.
- **Won by one-shot** → the PC was a component in a sum. The Bard's marginalia is the natural
  chronicler of that, and the marginalia beat already exists.

**Register 2 — the world.** Each Masterite's world keeps a trace of *how* its guardian fell, and
the traces differ. This is diegetic rather than bolted on: the Calibrant's faces keep records
already — the W5 firewall access log (`docs/side_quests.md:273`) ends `PASSED: reason
unclassified`, a record that notes the party got through and cannot say why. A manual defeat
leaves a witness account; an autobattle defeat leaves a transcript with no observer; a one-shot
leaves a gap in the log where the fight should have been.

**Register 3 — the ledger (ending weight).** The ending reads the **per-boss ledger**, not a single
global ratio. The two record stores are already per-monster, so "you automated the Warden, fought
Mordaine yourself, and deleted the rest" is answerable today for two of the three methods.

### The per-boss shape, concretely

For each of the Masterites and the three Vertex trials, the proposal is one row:

```
boss × method  ->  (party mark, world trace, ledger entry)
```

The trials cowir-main shipped are the natural demonstration, because routing already matched the
player to a method: `the_operator` (automation), `the_examiner` (classic), `the_margin` (one-shot).
**Beating your own trial by a method other than the one it was chosen for is the most interesting
cell in the table** — the one-shotter who finally stands and fights the Margin, the automator who
turns the script off for the Operator. The game measured you, picked a face, and you refused it.
That is worth more than any of the matching cells, and it is free: the routing already knows which
face it picked.

### New records required

Stated rather than assumed, per the constraint above:

1. **A per-boss manual-victory record.** Minimum: that this monster was beaten with neither an
   autobattle record nor a one-shot record for that victory. Without it, manual is invisible per
   boss and register 1 has nothing to mark.
2. **A per-boss "phase 2 seen" fact**, if the one-shot register is to assert what went unwitnessed.
   Derivable from the one-shot record's existence, but worth being explicit about whether it means
   "never saw it on this boss" or "never saw it on any boss."
3. **Whether the winning formation is recorded per victory**, for register 1 to mark PCs rather than
   the save. If it is not, register 1 degrades to a party-wide fact.

Shapes and names are cowir-main's; this names only what has to exist.

---

## (c) How this ties into the existing structure

**It extends the chapter3 fork rather than replacing it.** `world6_chapter3` already asks the canon
question and already answers it five ways. That scene stays the *thesis* — the Calibrant naming what
kind of player you are. The ending becomes the *evidence*: not a sixth answer, but the ledger read
back. Chapter 3 says what you are; the ending says what you did, boss by boss.

**The Ending Matrix is not contradicted, it is completed.** Five of its six rows are implemented as
chapter3's arms. What this proposal adds is the per-boss resolution underneath those arms, so
"Heavy autobattle → Automation" stops being a single threshold and becomes a record of where the
automation was pointed.

**The ending's linearity is the real work.** Any fork there is new structure. The cheapest version
that satisfies 19479 is a **single ledger-driven beat inside the existing 41 steps** rather than a
branched ending per playstyle — the Calibrant reads back three or four specifics from the ledger,
and the surrounding scene is unchanged. That keeps one ending, preserves the existing prose, and
still makes HOW you won visible at the end. A fully branched ending is the larger option and should
be a separate ruling.

**Post-game already wants this data.** The Ending Matrix's neighbours in
`docs/design-canon.md` §11 list build leaderboards tracking "cleanest one-shot" and "most novel
build" as post-final-confrontation systems. A per-boss method ledger is the same data.

---

## Open questions for Carmelo

1. **Collaborator.** The hidden fifth ending keys on completionist, which the detector cannot
   return. Add a detector value, re-key the ending onto something countable, or leave the short
   story as prose that no code gates? This is a canon question, not an engine one.
2. **One-shot as an identity.** Should one-shot become a sixth playstyle the detector can return —
   which would make it eligible for the chapter3 fork and every future `cases` block — or stay a
   per-boss record read only by the ending?
3. **Ending scope.** One ending with a ledger-driven beat inside it, or a branched ending per
   playstyle? The first is cheap and preserves the shipped prose; the second is the bigger feature.
4. **The refusal cell.** Is beating your own trial by the wrong method worth special content? It is
   the most expressive cell in the table and the routing already knows.
5. **Does method influence mechanics, or only narration?** 19479 says "influence your characters" —
   traits that only speak, or traits that change stats. Narration-only is safe and reversible;
   mechanical traits intersect cowir-main's live balance work.

---

## Not building (recorded, deliberate)

- No flags, scene ids or step types specified — cowir-main's surface.
- No cutscene JSON authored. Per his ruling, nothing on story or endings lands before review.
- No change proposed to `_detect_playstyle`'s thresholds. The ratio arms were repaired on
  2026-07-28 and 2026-09-16 and are not this document's subject.
- No per-boss table filled in. The shape is proposed here; populating 24 Masterites × 3 methods is
  authoring work that should follow the ruling, not precede it.
