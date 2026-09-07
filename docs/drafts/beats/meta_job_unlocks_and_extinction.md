# Four Beats — the three unwritable jobs, and the world that notices

Spec. struktured, 2026-09-07, in response to "anything else we can do to add more depth or layering
or nuance or punch to the story?"

## The finding these four come from

The world already reacts to **what kind of player you are** — `_detect_playstyle()` classifies
exploiter / automator / grinder / manual / balanced, and **42 data files branch on it**. That system
is healthy and none of this touches it.

What the world never reacts to is **specific irreversible things you did**:

| tracked, save-persisted | referenced in `data/` |
|---|---|
| `permakilled_monster_types` | **0** |
| `save_history` (rewind) | **0** |
| `boss_splits` / `boss_personal_best` | **0** |

And those three acts are the signatures of **Necromancer, Time Mage and Scriptweaver** — the exact
three jobs that are unreachable outside debug mode, because they have no `unlock_condition`
authored. **The access gap and the acknowledgement gap are the same gap.** Nobody wrote reactions
to those acts because nobody could perform them.

## The spine: all three jobs are about writing

The game already supplies the word. `BattleManager.gd:6386`, on permakill:

> *"The %s species has been UNWRITTEN. It will not respawn."*

```
Necromancer   unwrites a species        permakill, corrupt_save
Time Mage     rewrites what happened    rewind, undo_death, restore_point
Scriptweaver  rewrites the rules        edit_formula, modify_constant
```

So the three unlock beats are one idea in three keys, and the idea is **you do not earn these by
being strong. You earn them by noticing that somebody has already done this to the world.** Each
beat is the player finding evidence of a prior edit — and the job is the ability to answer in kind.

That is also the cleanest available statement of the game's premise: the Calibrant has been tuning
this world the whole time, and these three jobs are the first tools that let you tune back.

🛑 **Design rule for all three: the beat NEVER grants the power as a reward.** It shows the damage
first and then hands you the instrument. The player should feel implicated at the moment of unlock,
not congratulated.

---

## Mechanics available (verified, not assumed)

`JobSystem.is_job_unlocked()` supports four condition types. The flexible one is `achievement`,
which resolves through `gs.is_story_flag_set(achievement_id)` — **so any story flag a cutscene sets
can gate a job.** All three specs below use it; no engine change is required.

```json
"unlock_condition": { "type": "achievement", "id": "<flag the beat sets>",
                      "description": "<shown in the job menu>" }
```

Set the flag with a normal `set_flag` cutscene step. `_set_cutscene_flag_and_mirror`
(`GameLoop.gd:2114`) writes `game_constants` and mirrors the bare name to `set_story_flag`, so a
cutscene flag and a story flag are the same thing from the unlock's point of view.

---

# BEAT 1 — Scriptweaver: *the herb that heals backwards*

**Do this one first.** It is the cheapest, it is already half-written, and it teaches the grammar
the other two reuse.

W1 Eldertree dialogue already ships this line:

> *"The corruption changes the plants. Not just kills them — changes them. I found a healing herb
> yesterday that heals backwards. Took damage to use it. Fascinating, in a deeply upsetting way."*

**A healing item with a flipped sign is not blight. It is an edited constant.** The speaker has
correctly observed a Scriptweaver artifact and filed it under weather — exactly the mistake the
whole corruption arc is about.

**The beat:** the party brings the herb to someone who can read it. The Mage is the right party
voice — he is the one who revises without flinching. ⚠️ Note for whoever writes it: that
characterisation is established in **the novella** (`world1_the_usurpers_crown.md`), not in any
shipped in-game line, so the scene must carry it on its own rather than assume the player has met
it. The realisation is not "this plant is sick." It is *"this plant is correct. Something changed
what correct means."*

**The turn:** if a value can be edited, the edit has an author, and the author is still working.

**Unlock:** `scriptweaver`, flag `unwritten_witnessed_edit`.
**Placement:** W2. Late enough that the player has met formal court-magic seals; early enough that
Scriptweaver's automation payload is useful for most of the game.
**Punch:** the first job you unlock by *reading* rather than fighting.

```json
"scriptweaver": {
  "unlock_condition": { "type": "achievement", "id": "unwritten_witnessed_edit",
                        "description": "Recognise an edited constant in the world" } }
```

---

# BEAT 2 — Time Mage: *Phil remembers something that did not happen*

Phil the Lost loses track of what happened before. **A man who cannot hold continuity is the one
person who would notice when continuity is edited** — he has no intact copy to be overwritten.

**The beat:** Phil recounts something with total confidence. It is wrong. Not vague — *specifically*
wrong, in a way the player can check: a person who is alive describing their funeral, a door on the
wrong side of a room the player has walked through, the Rat King's death in a place it did not
happen. He is not confused. He is remembering accurately. **The version he remembers was rewound by
somebody else.**

The player has no rewind yet. That is the point: they are seeing the phenomenon from the outside
before they can cause it. The first time they use `rewind` afterwards, they know exactly what they
have just done to everyone who was there.

**Ties to shipped canon:** `world1_transition` already has the party writing Phil down —
*"Phil said something about dreams — metal walls, blinking lights. I wrote it all down."* In World 1
nothing has metal walls or blinking lights; that is a **later world** bleeding backwards. (I would
not pin which — it reads as industrial W4 or the digital Network of W5, and the ambiguity is worth
keeping.) Phil is already remembering forward in shipped text. This beat only supplies the reason:
the memory is not prophecy, it is residue.

**Unlock:** `time_mage`, flag `unwritten_witnessed_rewind`.
**Placement:** W3. Phil is already referenced in `world3_orrery`, so he has standing there without
new staging.
**Punch:** the reveal that somebody has been rewinding this world since before W1 — which is the
Calibrant thesis delivered by the village drunk instead of by a boss.

```json
"time_mage": {
  "unlock_condition": { "type": "achievement", "id": "unwritten_witnessed_rewind",
                        "description": "Meet someone who remembers a rewritten timeline" } }
```

---

# BEAT 3 — Necromancer: *the thing that used to live here*

The heaviest of the three, and it must come last.

**The beat:** the party finds a species-shaped hole. An empty ecological niche — a nest with no
occupant, a predator with nothing to hunt, a food chain missing a link. Somebody has already
permakilled something, long ago, and the world closed over it imperfectly.

The horror is not the killing. It is that **nobody can name what is missing.** The bestiary has no
entry. No NPC remembers. The only evidence is a shape in the world that implies an animal, and no
animal. The party can tell something was removed and cannot tell what.

**The turn:** Necromancer is not offered as power. It is offered as the *only* instrument that can
do this, handed over immediately after the player has seen what it looks like from the far side. The
player unlocks the ability to make more holes exactly when they understand what a hole costs.

**The bill:** `permakill` also calls `GameState.add_corruption(corruption_risk)`. So this beat is
where the corruption arc closes — Phil's notebook told them the meter is theirs, and this tells
them what the most expensive purchase on it buys.

**Unlock:** `necromancer`, flag `unwritten_found_the_hole`.
**Placement:** W3–W4, and strictly after both other beats.
**Punch:** the game's third pillar — stakes must be real — stated as an absence rather than a
warning.

```json
"necromancer": {
  "unlock_condition": { "type": "achievement", "id": "unwritten_found_the_hole",
                        "description": "Find a species-shaped hole in the world" } }
```

---

# BEAT 4 — The extinction witness (the one that pays the other three off)

Right now the player can drive a species to extinction and **the world says nothing**. Six systems
honour `permakilled_monster_types` — `EncounterSystem`, `MonsterSpawner` (both despawn and
spawn-block), `AutogrindController`, `BattleManager`, and `GameState` save/load — so the species
genuinely stops existing. The only acknowledgement is one battle-log line, in the fight, once.

Four reactions, cheapest first. **All read the same array; none needs new tracking.**

### 4a. The bestiary marks it — `BestiaryMenu` has **0** permakill references
The entry stays, and gains a state: **UNWRITTEN**. Not greyed out, not removed — removal would be
the game colluding. The record persists and says what happened, which is the same principle as the
alcove vial keeping both labels and Phil's notebook crossing nothing out. *The bestiary is the only
thing left that remembers.*

### 4b. NPCs stop being able to mention it
Any NPC line naming an extinct species gains a variant. Not a lament — a **gap**. Someone reaching
for a word that is no longer there: *"There used to be — "* and then moving on, because they cannot
finish the sentence and do not know why. Cheap: one alternate line per species that appears in
dialogue.

### 4c. One NPC who does notice, once
A single reactive beat, gated on `permakilled_monster_types.size() >= 1`, delivered by somebody
whose livelihood was the species — a hunter with nothing to hunt, a cook without an ingredient. They
do not accuse the player. They cannot; nobody knows it was them. **That is the punch.** The player
is the only entity in the world who knows what happened, and there is no mechanism for confessing.

### 4d. Phil's notebook gets an entry (nearly free — the provider already exists)
Phil writes down what he cannot hold. An extinct species is the purest possible case: a thing that
now exists **only** as an entry in a notebook kept by a man who forgets. Gate one page on
`permakilled_monster_types.size() >= 1`:

> *Entry 47. There is a word here I cannot read any more. I wrote it myself. I remember writing it.
> I do not remember what it was for.*
>
> *I am leaving the page. Somebody should keep the shape of it.*

That page requires no new mechanism — the provider is re-invoked per open and already reads live
`GameState`, so it is one `if` in the function that shipped in .225.

---

## Build order and cost

```
1  Scriptweaver beat   W2   dialogue only, half-written already in Eldertree
2  Bestiary UNWRITTEN  --   UI state on an existing menu, 0 prose
3  Phil notebook page  --   one `if` in the shipped provider
4  Time Mage beat      W3   dialogue only, Phil already referenced in world3_orrery
5  NPC gap variants    --   one alternate line per species named in dialogue
6  Necromancer beat    W3-4 needs a location dressed as an empty niche -- the only art ask
7  The one who noticed W2+  one reactive scene
```

Six of the seven are data and prose. **No engine work**: the unlock type already resolves arbitrary
story flags, and every permakill reaction reads an array that six systems already maintain.

## Deliberately not specced

- **`boss_splits` / `boss_personal_best` reactivity** — a boss remarking that you are killing it
  faster each time is strong and on-thesis, but it belongs to whoever owns boss dialogue, and it
  wants the Masterite framing rather than mine. Flagging it as the fourth unreferenced tracker, not
  claiming it.
- **Anything touching `_detect_playstyle`.** It works and 42 files depend on it.
