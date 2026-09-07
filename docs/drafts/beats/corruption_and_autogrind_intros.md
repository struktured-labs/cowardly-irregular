# Two Missing Explanations — Corruption, and the Forced Autogrind Introduction

Design brief. Source: struktured, 2026-09-06 — *"corruption system never explained either"* and
*"[autogrind] def needs a tutorial and a forced introduction at some point in the game (probably
overworld 3 or earlier)."* Relayed via cowir-main. Placement and voice only; scene shape is
cowir-cutscenes', mechanic hooks are cowir-autogrind's.

---

## 1. Why corruption reads as unexplained

It is not under-mentioned. It is **over-mentioned in the wrong sense of the word.**

The shipped game contains two different things called corruption:

| | what it is | how well explained |
|---|---|---|
| **World corruption** | the plot's spreading blight — the cave, the forest near Eldertree, the trade routes, court magic | 21 files in `data/`, 12 cutscenes. Thoroughly seeded. |
| **Player corruption** | `GameState.corruption_level` — ratcheted, save-threatening, raised by meta-job abilities in 8+ `BattleManager` sites, driving `visual_glitch` / `stat_drain` / `encounter_surge` / `bp_instability` / `ability_corruption` | **nowhere** |

Measured across the 12 cutscenes that say "corruption": `stat_drain`, `encounter_surge`,
`bp_instability` and `ability_corruption` appear **zero** times in any form, plain-language
variants included; so do "your save" and "save file". The only hits for "glitch" are two
`"reality_glitch"` tokens in the two W6 Calibrant scenes — a cutscene **VFX directive**, not
player-facing text, and not the `visual_glitch` corruption effect. **Not one line of dialogue
anywhere connects the word to the number on the save.**

(Controls on that sweep: "forest" 7, "cave" 10, "corruption" 12, a fabricated term 0. Worth
recording because my first pass piped the file list through `xargs command grep` — `command` is a
shell builtin, so xargs exits 127 and prints nothing. Every effect scored 0 **and so did "forest"
and "cave"**, in files I had already read containing both. The zeros above are from the re-run.)

So the player hears "corruption" constantly as *weather* — something happening to the kingdom —
and then a meter with the same name quietly fills up on their own file. The two never touch. That
is the whole defect, and it means **the fix is not to introduce a concept. It is to collapse two
meanings the player already carries into one.**

That collapse is the game's fourth pillar working as designed: the meta is diegetic. The blight in
the forest and the number on the save are the same substance. The player has been told about it
for ten hours and did not know they were being warned.

> The exposure gap was already noticed on the engine side — `OverworldMenu.gd:483` carries the
> note *"outside autogrind UI the player had NO surface showing corruption — a save-threatening
> core [mechanic]"*, and a readout was added. A number with no story is the state we're fixing;
> the readout is the surface it lands on.

### Who says it — not the obvious choice

The obvious mouth is Scholar Milo. It should not be Milo, and the reason is structural.

Milo already exists in Harmonia and already preaches the thesis, in shipped W1 text:

> *"Imagine a world where you don't fight your battles. You design them."*
> *"Not laziness. **Enlightenment.**"*

Milo's dramatic function is **to sell automation**. Corruption is the bill. Putting the invoice in
the salesman's mouth costs us the only unqualified evangelist in W1, and it makes the game
pre-emptively apologise for its own central pleasure. Automation should stay seductive.

**Use Phil the Lost.** He is already in Harmonia, in the same village, in the same chapter, and he
already introduces himself like this:

> *"Phil. Phil the Lost. Called that because I lose things. Mostly I lose track of what's happened
> before."*

Phil is a man whose save is corrupted. That is the entire joke, and it is already written and
shipped — nobody planted it, it just happens to be true. He recurs in W1, W3, and W6
across seven shipped cutscene files — `world1_chapter1`, `world1_harmonia_npcs`,
`world1_transition`, `world1_orrery`, `world3_chapter2`, `world3_orrery`, `world6_orrery` — so he
can carry the ratchet across the whole game rather than delivering one lecture and leaving.

And the Backwards Warren's new boss is **The Lost Cartographer**. The name rhyme with Phil the
Lost is free and should be paid off, not explained: the same condition, further along.

### The device: Phil's notebook, not Phil's speech

Phil cannot explain corruption. He cannot remember it — that is his defect and it is the point. So
he does not explain it. **He hands the player his notebook**, because writing things down is what
he does instead of remembering.

The notebook is the explainer. It can be explicit about all five effects, because it is a symptom
list kept by a man cataloguing his own decline in his own handwriting — which is exactly the tone
the mechanic deserves and exactly what a tutorial popup cannot do:

- entries getting shorter as they go
- the same entry written twice, in different hands, neither crossed out
- a page that just says *ask about the mountain* with nothing after it

This reuses a motif the W1 novella already runs hard: the Bard's marginalia, *"I am writing it down
so I will know it next time."* The Bard writes to understand. Phil writes to survive. Same act,
opposite reason — and the Bard is the one party member who would recognise what she is holding.
**Give her the reaction line.** She has been keeping the same book for a better reason and it will
land on her hardest.

It also rhymes with the alcove vial already in W1 canon: a label with the correction and the
original both left on it, neither removed. Corruption in this game has always looked like a record
that disagrees with itself. The notebook makes that legible.

### Placement

**Late W1, Harmonia, after the Rat King.** Constraints that fix it there:

- must land **before** the player can bank meaningful corruption, or the reveal arrives as a
  punishment for something already spent
- must land **after** enough lore mentions that the collapse has something to collapse *into* —
  post-Rat King, the player has heard the cave, the forest, and the court-magic seals
- Milo and Phil are already in Harmonia in W1, so no new location and no new cast
- it sits naturally next to the Courtier at the Inn (`world1_spotlight_bard_ch7`), also Harmonia,
  also post-Rat King — the Bard is already in the neighbourhood and already being catalogued by
  someone. Being *measured* and being *eroded* are the same evening's business.

**Not a wall.** Optional-but-signposted. The player who ignores Phil should meet the Cartographer
in the Warren and feel the floor drop; the player who read the notebook should recognise him.

---

## 2. The forced autogrind introduction

### Current state

`data/cutscenes` + `data/quests` mentioning autogrind: **0 files.** Autogrind is reachable from
turn one as an always-`enabled` overworld menu row (`OverworldMenu.gd:52`) and is introduced by
nothing. `TutorialHints` already carries `autogrind`, `autogrind_menu`, `autogrind_presets`,
`autogrind_resume`, `autogrind_export` — the *mechanical* hints exist. What is missing is a
**reason to open the menu at all**, which is why the hints never fire for most players.

So this is not "write a tutorial." The tutorial is built. This is **a forced first run with a
motive**, and then the existing hints do their job.

### Shape: the game's second pillar, staged

Automation is core gameplay, not a shortcut — so the introduction must not be a convenience pitch
("save time!"). It must be a **task no person can stay awake for.** The player doesn't automate
because it's faster. They automate because the alternative is not available to a human.

Recommended trigger: **a gate the player cannot pass by playing well.** Something wants a number of
repetitions that is flatly unreasonable — a toll, a quota, a ledger that must balance, a door that
counts. Skill does not shorten it. Presence does not shorten it. The only move is to stop being
present and let the system do it.

That is the sermon delivered as a mechanic instead of a speech, and it is the first time the game
asks the player to *leave*.

### Voice and placement

**Milo, escalated — and this is what he is for.** He sold autobattle in W1 with *"you don't fight
your battles, you design them."* Autogrind is that same sentence with the stakes moved: *you don't
attend your victories either.* He gets to be right twice, which is much better than being right
once and then apologetic.

**By W3, and earlier is better** — struktured said "overworld 3 or earlier." W2 is defensible if
cowir-autogrind wants the runway, because the corruption beat lands in late W1 and the two want
separation: **learn what the meter is, then get handed the thing that fills it.** In that order.
Reversed, the forced grind reads as the game corrupting the player's save without warning.

That ordering is the one hard constraint in this document.

### The join

The two beats are one arc and should be built as one:

1. **Late W1** — Phil's notebook. The player learns corruption is theirs, and costs.
2. **W2/W3** — Milo's gate. The player is *forced* to use the thing that generates it.
3. The player now runs their first autogrind **knowing what it spends.** That is a decision, not a
   convenience. Every autogrind session afterwards is a wager the player understands.

Without (1), (2) is the game corrupting a save it never mentioned. Without (2), (1) is a lecture
about a resource the player never spends. Shipped together they convert corruption from an
unexplained meter into the game's actual risk economy.

---

## Open questions

- **cowir-autogrind** — what is the smallest forced run that teaches the loop without stalling
  W2/W3 pacing? What does the gate count, and does `TutorialHints` need a new trigger id for a
  *forced* first run vs the existing opportunistic `autogrind` hint?
- **cowir-cutscenes** — is the notebook a readable prop (an item / inspect target) or a dialogue
  tree? Preference is a prop: it can be re-read later, which is the whole point of a book kept by
  a man who forgets.
- **struktured** — Phil recurs in W1/W3/W6. Should his condition visibly worsen with the player's
  own `corruption_level`, or on a fixed story track? Reactive is the better joke and the more
  expensive build.
