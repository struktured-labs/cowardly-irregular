# Character Art Brief — Chancellor Mordaine

> **For:** Artist reference (portrait + boss sprite)
> **Status:** Visual design OPEN. Current in-game art is placeholder only — `shadow_knight` sprite (tier T1) and the generic "mysterious" cutscene portrait. Nothing canon to preserve; this is a clean design.
> **Role:** World 1 final boss, Castle Harmonia, Level 20. Theme: "The Usurper's Shadow."

---

## One-line concept

A sorceress-bureaucrat who rules a kingdom through ledgers, not swords. **Morgan le Fay meets Jafar — but if Jafar were a competent middle-manager who genuinely believed he was helping.**

## The twist the art should quietly support

Mordaine is the **first mask of the Calibrant** — a single meta-entity that role-plays as the final boss of every world (the Coordinator/HOA tyrant in W2, the Regulator/engineer in W3, etc.). The player is NOT supposed to realize this until World 3+. So her medieval-fantasy look must be **100% genre-authentic** — a real sorceress-usurper, no glitch effects, no anachronisms. The only "tell" is subtle: a coldness, a watchfulness, the sense she's *evaluating* rather than *fighting*. Replayers should look back and go "ohhh." First-timers should just see a great fantasy villain.

---

## Personality (drives the face and posture)

- **Calm, precise, never raises her voice.** She does not draw a sword. She audits you.
- Genuinely believes order requires control. **Not cartoonishly evil** — she thinks the kingdom is *better* under her rule, and she's partly right. Her final dialogue is meant to make the player uncomfortable because it's almost reasonable.
- Seized power through manipulation, not conquest — whispered policy, replaced advisors, turned the kind-but-weak King Aldric into a puppet/"a process."
- Treats the party as an **anomalous variable** in her data, not as enemies. Recognition, not contempt.
- The cracks only show at low HP and in death — a flicker of something almost proud, almost sad, "almost something with no name in a medieval vocabulary."

### Key flavor line (sets the mood better than anything)
> "She does not so much fight you as audit you — testing variables, recording responses, allowing some attacks through to confirm the damage formula still holds. The throne room is exactly the temperature of a server room."

---

## Setting / staging (for the boss scene & portrait background)

The throne room is deliberately **NOT** the expected dramatic villain lair. It's a **working room**:
- Maps on every surface. Ledgers stacked in careful columns. A single open window admitting ordinary village sounds (markets, children, someone arguing about a fence).
- She's first seen with her **back turned, studying a document**, not turning when the party enters.
- Her hands are always doing something purposeful — folding paper, setting down a ledger. When her hands go still, it means something.
- A **blue-bound ledger** (the "third ledger") is a recurring prop — she references its margin notes in her death scene.
- On defeat she **dissolves "the way a thought dissolves,"** not in smoke/light/theatrics — present and specific one moment, a fading memory the next. The room briefly **flickers to reveal suburbs behind the walls** (the W2 bleed — but that's an FX/cutscene note, not part of her design).

---

## Visual direction (suggested — artist's call)

The writing implies, but never locks, the following. Treat as a starting palette:

- **Archetype:** elegant sorceress-administrator, not an armored warlord. Authority through bearing, not bulk.
- **Read at a glance:** more *chancellor/magistrate* than *witch* — robes of office, clean lines, controlled. Think high-functionary regalia with arcane undertones rather than a pointy-hat caster.
- **Color:** cold, muted, orderly. Slate, ink-black, deep blue (echo the blue ledger), restrained gold for office/rank. Avoid hot, chaotic, "evil sorcerer" reds/greens — she's the antithesis of chaos.
- **Hands:** expressive and important — she's defined by what her hands do (documents, ledgers). Worth featuring in the portrait.
- **Eyes:** the one constant across ALL the Calibrant's masks is the eyes — "the same as Mordaine's" recurs in later worlds. Give her a distinctive, calm, measuring gaze. This is the design element that should carry forward.
- **Silhouette:** composed, vertical, precise. She should look like she's mid-evaluation even standing still.
- **What to avoid:** snarls, dramatic villain poses, glitch/digital artifacts, anything that breaks medieval-fantasy genre.

### Expressions to cover (for portrait set)
1. **Neutral/measuring** (default) — polite recognition, filing you as data.
2. **Low-HP composure crack** — "This was not in the schema." First genuine surprise.
3. **Defeat** — almost proud, almost sad, unreadable. The honest silence.

---

## Combat identity (in case it informs the sprite's kit)

- Court sorceress: high-tier elemental magic (Firaga/Blizzaga/Thundaga), Life Drain, Void Pulse; summons palace guards.
- Stats favor magic (MAGIC 72) over physical; weak to **Holy**, resists **Dark/Ice/Fire**.
- Drops the **Calibrant Token** — the first hint of the meta-arc.

---

## Sources in repo (if the artist wants more)
- `data/cutscenes/world1_mordaine_intro.json` — "The Chancellor's Accounting" (full pre-fight dialogue)
- `data/cutscenes/world1_mordaine_defeat.json` — "The Last Calculation" (death scene)
- `data/monsters.json` → `chancellor_mordaine` (stats, battle dialogue)
- `data/bestiary.json` → `chancellor_mordaine` (the "audits you" flavor text)
- `data/lore.json` → `villain` (the Calibrant meta-arc & all masks)
- `docs/story-bible.md` (Key Characters + Act 4) and `docs/novellas/world1_the_usurpers_crown.md`
