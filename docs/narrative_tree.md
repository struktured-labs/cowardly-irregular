# Narrative Branching Tree

## Purpose

This is the MASTER GRAPH that maps game decisions to story branches. Every novella, short story, and dialogue variant is a path through this tree. The game implements the tree through systems; the novels implement it through prose. Both must align.

**Rule: If it's not in this tree, it doesn't exist in the story. If it's in this tree, the game must support it.**

---

## Decision Axes (what creates branches)

### Axis 1: Player 1 Base Job (5 branches)
The single biggest story influence. Sets the core voice and how the player sees every world.

```
Fighter ─── direct, earnest, action-first
Cleric ──── attentive, patient, faith-driven
Mage ────── analytical, curious, system-minded
Rogue ───── perceptive, pragmatic, edge-finding
Bard ────── expressive, observant, narrative-minded
```

### Axis 2: Job Evolution Path (per job)
Each base job has evolution targets. Evolution shifts personality and opens/closes story content.

```
Fighter ─┬─ Guardian (type 1, tank/brave-default)
         └─ [future: Champion, Knight, Masterite-tier]

Cleric ──┬─ [future: High Priestess (devotion path)]
         └─ [future: Paladin (militant path)]

Mage ────┬─ [future: Wizard (scholarly path)]
         └─ [future: Dark Mage (destructive path) → Necromancer (meta)]

Rogue ───┬─ Ninja (type 1, speed/skip)
         └─ [future: Assassin, Trickster]

Bard ────┬─ [future: Troubadour (support path)]
         └─ [future: Cantor (offensive path)]
```

### Axis 3: Secondary Job (moderate influence)
Blends personality. 5 base × 5 secondary = 25 combinations (minus self = 20).

### Axis 4: Masterite Job Adoption (MAJOR BRANCH POINT)
**When you defeat a Masterite, you can adopt their job class as a sub-job.** This is a choose-your-own-adventure moment with story consequences:

```
Masterite Archetypes available as sub-jobs:
├── Warden ─── defensive specialist, guardian philosophy
├── Arbiter ── offensive specialist, judgment philosophy
├── Tempo ──── speed specialist, time/sequence philosophy
└── Curator ── resource specialist, management philosophy
```

**Each adoption creates a narrative fork:**
- Taking a Warden sub-job → your character starts thinking in terms of protection/walls/boundaries
- Taking an Arbiter sub-job → your character becomes more judgmental, precise, evaluative
- Taking a Tempo sub-job → your character becomes time-aware, speed-obsessed, or presence-focused
- Taking a Curator sub-job → your character becomes resource-conscious, draining, or archival

**The philosophical tension:** Masterites are agents of the Calibrant. Taking their job class means absorbing a piece of the Calibrant's design philosophy. Are you co-opting the enemy's tools, or are they changing you?

### Axis 5: Meta Job Adoption (type 2 — GAME-CHANGING)
Meta jobs break the fourth wall mechanically AND narratively:

```
Scriptweaver ─── edits damage formulas, autobattle verbs. Story: sees the code.
Time Mage ────── rewind/save manipulation. Story: remembers other timelines.
Necromancer ──── save corruption risk. Story: death is a door, saves are mortal.
Bossbinder ───── control-swap with bosses. Story: becomes the thing you fight.
Skiptrotter ──── warp/skip content. Story: the game notices you're skipping.
```

**Each meta job opens unique story content:**
- Scriptweaver: can read the Calibrant's code comments, unlocks Scriptweaver Guild content
- Time Mage: remembers previous attempts/deaths, dialogue references undone timelines
- Necromancer: NPCs react with fear, Masterites react differently, save corruption is narratively real
- Bossbinder: the Calibrant's Masterites recognize you as "one of theirs" — unsettling
- Skiptrotter: the Calibrant comments on skipped content, the world notices gaps

### Axis 6: Playstyle (continuous, tracked)

```
Playstyle Spectrum:
├── Combat approach: manual ←→ autobattle ←→ autogrind
├── Pacing: thorough/completionist ←→ speedrun/skip
├── Risk: conservative ←→ aggressive/risky
├── Builds: balanced ←→ one-shot ←→ many-turn
├── Engagement: dialogue-reading ←→ dialogue-skipping
└── Exploration: side-quest-hunter ←→ main-path-only
```

### Axis 7: The Calibrant Class (post-game, ultimate)
Defeating the Calibrant and accepting the class. This is the final branch — do you become the designer?

---

## The Job Evolution Tree (Game → Story Mapping)

### Tier 0: Base Jobs (World 1)
Five starting classes. Generic names. Trope personalities. The comfort zone.

| Job | Game Role | Story Role | World 1 Name |
|-----|-----------|------------|-------------|
| Fighter | Physical DPS/tank | The one who stands in front | Fighter |
| Cleric | Healer/support | The one who keeps people alive | Cleric |
| Mage | Magic DPS | The one who understands systems | Mage |
| Rogue | Speed/utility | The one who finds edges | Rogue |
| Bard | Buff/debuff/support | The one who gives voice | Bard |

### Tier 1: Advanced Jobs (gated behind progression)
Branching evolution from base jobs. Personality shifts.

| Advanced Job | Evolves From | Unlock | Personality Shift |
|-------------|-------------|--------|------------------|
| Guardian | Fighter | Story ch.2, quest | Duty → sacrifice, brave/default mentality |
| Ninja | Rogue | Speed achievement | Pragmatism → efficiency, skip-oriented |
| Summoner | (any, story) | Story ch.3, quest | Individual → collective, recursive thinking |
| Speculator | (any, story) | Story ch.2, quest | Pragmatism → risk calculus, probability-minded |

### Tier 2: Meta Jobs (gated behind debug mode / progression)
Fourth-wall-breaking jobs. Massive story implications.

| Meta Job | Story Implication | Risk Level |
|----------|------------------|------------|
| Scriptweaver | Sees the game's code. The Calibrant's notes become readable. | Low |
| Time Mage | Remembers undone timelines. Death is reversible. Dialogue shifts. | Medium |
| Necromancer | Death magic that can corrupt saves. NPCs fear you. | High |
| Bossbinder | Control-swap with bosses. Masterites see you as kin. | Very High |
| Skiptrotter | Skip content. The game notices. The Calibrant comments. | Varies |

### Tier 3: Masterite Sub-Jobs (adopted from defeated bosses)
Each of the 4 Masterite archetypes can be taken as a sub-job. 22 bosses × 4 archetypes = many options, but the archetype is what matters narratively:

| Archetype | Sub-Job Effect | Personality Drift | Story Tension |
|-----------|---------------|-------------------|---------------|
| Warden | +DEF, +HP, guardian abilities | More protective, boundary-aware | "You fight like one of them now" |
| Arbiter | +ATK, +precision abilities | More judgmental, evaluative | "You measure things the way they do" |
| Tempo | +SPD, +turn manipulation | More time-aware, present or rushed | "You move between moments" |
| Curator | +resource abilities, drain/manage | More resource-conscious, archival | "You're starting to count like they count" |

**KEY: Taking a Masterite sub-job in a later world uses THAT world's version.**
- Taking Warden in W1: honorable guardian abilities, noble personality drift
- Taking Warden in W4: industrial protocol abilities, tragic/systematic drift
- Taking Warden in W6: conceptual obstacle abilities, philosophical drift

### Tier Ultimate: The Calibrant Class
Post-game. Defeat the Calibrant. Accept the class. Become the designer.

| Ability | Effect | Story Meaning |
|---------|--------|--------------|
| Design Encounter | Create custom enemy configurations | You build the challenges now |
| Set Parameters | Adjust difficulty variables | You decide what "fair" means |
| Calibrate | Rebalance any system | The mirror ability — what the Calibrant did to you |
| Build World | Access world-construction tools | Post-game creative mode |

---

## World Evolution Names (Cosmetic, Automatic)

These are NOT gameplay evolutions — they're visual/dialogue reskins per world. The base job stays mechanically the same. The name and appearance shift to fit the genre.

| Base | W1 Medieval | W2 Suburban | W3 Steampunk | W4 Industrial | W5 Digital | W6 Abstract |
|------|-------------|-------------|--------------|---------------|------------|-------------|
| Fighter | Fighter | Security Guard | Steamknight | Enforcer | Firewall | Resolve |
| Cleric | Cleric | School Nurse | Steampriest | Safety Officer | Antivirus | Faith |
| Mage | Mage | Science Nerd | Alchemist | Lab Technician | Compiler | Logic |
| Rogue | Rogue | Skater Kid | Saboteur | Whistleblower | Exploit | Edge |
| Bard | Bard | Band Kid | Busker | PA Announcer | Broadcaster | Voice |

---

## Story Branch Map

### Major Branches (each warrants its own novella/short story)

```
                         ┌── The Automator (Mage lead, autobattle)     [WRITTEN]
                         ├── The Faithful (Cleric lead, grind)         [WRITTEN]
Player 1 Base Job ───────┼── The Breaker (Rogue lead, exploit)         [WRITTEN]
                         ├── The Witness (Bard lead, manual)           [WRITTEN]
                         └── Canonical (Fighter lead, balanced)        [WRITTEN]
```

### Medium Branches (short stories, ~5-10K words each)

```
Masterite Job Adoption:
├── "The Shield" ── Fighter takes Warden sub-job
│   (becomes more like the enemy, party notices)
├── "The Judge" ── Mage takes Arbiter sub-job
│   (starts grading everything, uncomfortable echoes)
├── "The Rush" ── Rogue takes Tempo sub-job
│   (speed addiction, arriving before being sent)
└── "The Ledger" ── Cleric takes Curator sub-job
│   (starts counting resources obsessively, faith vs accounting)
│
Meta Job Stories:
├── "The Coder" ── Any lead takes Scriptweaver
│   (reads the Calibrant's code, understands the system too well)
├── "The Rewinder" ── Any lead takes Time Mage
│   (remembers deaths that didn't happen, dialogue gets weird)
├── "The Risk" ── Any lead takes Necromancer
│   (save corruption as lived experience, NPCs avoid you)
├── "The Swap" ── Any lead takes Bossbinder
│   (plays as Masterites, sees from their side)
└── "The Skip" ── Any lead takes Skiptrotter
    (the Calibrant's reaction to skipped content)
```

### Minor Branches (dialogue variants, not separate stories)

```
Secondary job combos (20 combinations):
  Fighter+Cleric, Fighter+Mage, Fighter+Rogue, Fighter+Bard
  Cleric+Fighter, Cleric+Mage, Cleric+Rogue, Cleric+Bard
  ... etc. (dialogue color, not plot changes)

Playstyle variants:
  Autobattle %, grind rate, exploit count, dialogue skip rate
  → Affect Calibrant's mirror behavior
  → Affect ending selection
  → Affect NPC reactions in W4+
```

---

## Ending Matrix

The ending is determined by a weighted combination of playstyle factors:

| Primary Factor | Ending | Core Answer to "What is a game without challenge?" |
|---------------|--------|--------------------------------------------------|
| Heavy autobattle | Automation | "A system to be understood" |
| Manual/traditional | Manual | "Still worth playing — the playing is the point" |
| Grind-heavy | Grind | "A place to rest" |
| Exploit-heavy | Exploit | "Impossible — there's always another edge" |
| Completionist (all side quests) | Collaborator | "A world to build together" (unique) |
| Mixed/balanced | Hybrid | Blended response drawing from multiple answers |

**The Collaborator ending** is the hidden fifth ending for completionists who did everything — all side quests, all NPC dialogues, all Masterite reflections. The Calibrant offers to let them stay in The Vertex and build the next world together.

---

## Story File Inventory

### Existing
| File | Type | Branch | Status |
|------|------|--------|--------|
| world1-6 canonical | Novel (63K) | Fighter lead, balanced | V2 complete |
| alt_the_automator | Novella (11K) | Mage lead, autobattle | V1 complete |
| alt_the_faithful | Novella (19K) | Cleric lead, grind | V1 complete |
| alt_the_breaker | Novella (15K) | Rogue lead, exploit | V1 complete |
| alt_the_witness | Novella (9K) | Bard lead, manual | V1 complete |

### Planned
| File | Type | Branch | Status |
|------|------|--------|--------|
| ms_the_shield | Short story (~8K) | Warden sub-job adoption | Not started |
| ms_the_judge | Short story (~8K) | Arbiter sub-job adoption | Not started |
| ms_the_rush | Short story (~8K) | Tempo sub-job adoption | Not started |
| ms_the_ledger | Short story (~8K) | Curator sub-job adoption | Not started |
| meta_the_coder | Short story (~8K) | Scriptweaver path | Not started |
| meta_the_rewinder | Short story (~8K) | Time Mage path | Not started |
| meta_the_risk | Short story (~8K) | Necromancer path | Not started |
| meta_the_swap | Short story (~8K) | Bossbinder path | Not started |
| meta_the_skip | Short story (~8K) | Skiptrotter path | Not started |
| ending_collaborator | Short story (~5K) | Completionist ending | Not started |

---

## Open Questions (to resolve with game design)

1. **Evolution branching**: The game currently has Fighter→Guardian and Rogue→Ninja as the only implemented evolutions. Cleric, Mage, Bard have `future_targets` but no implementation. How do unimplemented evolutions affect the story? Do we write ahead of the game, or wait?

2. **Masterite sub-job adoption**: This mechanic exists in the story but not yet in the game code. How does it work mechanically? Auto-offered after defeating a Masterite? Player chooses from a menu? Costs something?

3. **Multiple Masterite sub-jobs**: Can you hold more than one? If you take Warden AND Arbiter, does the personality drift compound?

4. **World-specific Masterite versions**: Taking Warden in W1 vs W4 — same archetype, different flavor. How does the game distinguish these?

5. **The Calibrant class**: Post-game only? Or available in NG+? Does it replace your base job or stack?

6. **Tertiary job slot**: The game has a "2 jobs + 1 ability slot" system. The ability slot is "not really story relevant" per design notes. Confirm this stays minimal in story influence.

7. **Job evolution vs world evolution**: The GAME evolution (Fighter→Guardian) is a permanent mechanical change. The WORLD evolution (Fighter→Security Guard) is cosmetic. These are separate systems. The story treats them as separate. Confirm this is correct.

8. **Speculator and Summoner**: These are type 1 (advanced) but don't evolve FROM a specific base job. They're unlocked via story quests. Does this mean any base job can access them? Story implications?
