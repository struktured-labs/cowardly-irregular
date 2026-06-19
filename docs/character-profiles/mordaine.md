# Mordaine — Character Profile (Sprite Art Reference)

**Role:** W1 final antagonist — Chancellor of the kingdom centered on Harmonia
**First appearance:** `docs/novellas/world1_the_usurpers_crown.md` Chapter 10
**Sprite scope:** Boss sprite (battle), optional throne-room overworld cameo, optional cutscene portrait
**Status:** Spec only — no sprite work shipped yet

This profile is the artist-facing distilled brief. It pulls together every canon excerpt that informs Mordaine's visual design, so the artist doesn't have to navigate the full ~700-line W1 novella to find what they need. Citations link back to canon for deeper reads.

---

## 1. One-paragraph read

Mordaine is a chancellor in dark unadorned robes standing at the foot of an empty throne. **Not a tyrant who looks like a tyrant** — the canon deliberately undermines the "Morgan le Fay meets Jafar" trope the story bible references. She's a hyper-competent administrator who has reduced "kingdom" to "problem set." Her power is stillness, not flourish; she doesn't sweep cloaks or monologue, she evaluates. When she falls, she doesn't explode — she fades the way a thought fades, like the system she ran just closed the file.

She is also (the player doesn't know this on first playthrough) **one of multiple masks** the true antagonist (the Calibrant) wears across worlds. This has design implications — see §9.

---

## 2. Costume & silhouette

> *"Her robes were dark and unadorned. Her posture was the posture of someone who has long since stopped needing to perform power because the power is simply there."*
> — `docs/novellas/world1_the_usurpers_crown.md:637`

- **Robes**, not armor. She's a court sorceress / political mage, not a knight.
- **Dark** — black or very deep charcoal. Possibly very dark maroon. Austere, practical.
- **Unadorned** — no gold trim, no jewels, no embroidery, no fur. The OPPOSITE of the medieval-fantasy-chancellor cliché.
- **No crown** — she never took it. The empty throne sits behind her.
- **No scepter** — would be too theatrical.
- Silhouette reads as: tall, narrow, vertical. Stillness. The robes fall straight; they do not flow or sweep.

**What NOT to draw:** billowing cloaks, ornate collars, glittering necklaces, ceremonial headdress, hooked staff. None of these.

---

## 3. Color palette

- **Primary:** very dark — near-black robes. Suggested range: `#1a1a20` to `#0d0d12`.
- **Hair:** unspecified in canon — artist's call.
  - Suggestion A: tied back / under a hood. Practical, not flowing.
  - Suggestion B: silver/grey signals age + austerity.
  - Suggestion C: very dark — vanishes into the robe silhouette, lets the face read as the focal point. (My pick.)
- **Skin tone:** unspecified — designer's call.
- **Magic / cast effect accent:** when she casts during the battle, the effect color should be **cold-light blues** or **sterile pale-gold** (think fluorescent rather than torchlight). Reinforces the "administrative, not magical" feel. NOT fiery red, NOT purple-arcane.
- **Composition contrast:** the throne behind her can carry the only saturated color in the scene — gold, red velvet, dark wood. Her monochrome silhouette stands against it.

---

## 4. Posture, stance, gesture economy

> *"She stood at the foot of the throne, not on it. The king's seat remained empty above her, a prop she no longer needed."*
> — `world1_the_usurpers_crown.md:633`

- **Standing**, not seated. Idle pose is upright and still.
- **At the foot of the throne** — the empty throne behind her is a critical staging element.
- No slouch, no aggressive lean, no flourish.
- **Hands:** clasped in front, or quiet at her sides. Not gesturing.
- **During combat:** *"Not chaotically. Methodically. As though she were running a test."* (`:673`) — economy of motion. Small precise gestures. Court magic from her is **small and contained**, not sweeping.

---

## 5. Face & expression

Default expression: **calm, attentive, evaluative.** The face of someone studying you. The story bible's *"Morgan le Fay meets Jafar"* comparison is misleading — read the canon and she's closer to a **hyper-competent senior bureaucrat or a tenured surgeon**. Power without performance.

> *"She looked at the five of them the way you look at a problem that has become, through some combination of persistence and luck, more interesting than you initially estimated."*
> — `:637`

> *"With recognition. The way a chess player acknowledges a piece that's moved further across the board than expected."*
> — `:635`

**Eye-line:** direct, level. She makes eye contact. She doesn't smile politely. She doesn't sneer. She *evaluates*.

**Micro-expressions that matter for animation:**
- **Hesitation frame** (load-bearing for the boss fight): canon makes this a turning point — *"Mordaine hesitated. It was a fraction of a second. It was enough."* (`:681`) — when the Rogue tells her the king is still in there. This is the only moment she breaks. Useful for a "vulnerable" / "hit-stun" frame.
- **Defeat expression:** *"an expression that was almost proud, and almost sad, and almost something with no name in a medieval vocabulary."* (`:685`) — NOT anger, NOT despair. Recognition. Closing the loop on an experiment that surprised her.

---

## 6. Age

Not specified directly. Implied: experienced, settled. **Mid-life to late-mid-life — 45 to 60** reads right. Could go older. Definitely **not young**. Her authority is "the power is simply there" — read as accumulated, not new.

---

## 7. Key frames worth dedicating sprite work to

| Frame | Description | Canon anchor |
|-------|-------------|--------------|
| Idle / dialogue | Standing at the foot of the empty throne, hands quiet, level gaze | `:633`, `:637` |
| Cast / attack | Small precise gesture (one hand, half-raised, fingers slightly curled). Court magic — geometric, controlled | `:673` |
| Hesitation | Tiny widening of the eyes, lips parted slightly. The Rogue has just said something not in her model | `:681` |
| Hit | Composed even when struck — her brand is restraint. Slight backward shift, NOT a stagger | implied |
| Defeat / dissolve | She fades. Edges soften. The silhouette holds for a beat after the figure is gone. **Glitch effect is canon-accurate** — *"glitching, dissolving, something wrong in the manner of her defeat"* (`alt_the_witness.md`) | `:685-689` |

---

## 8. Boss-fight animation moves (for the artist coordinating with the battle team)

From `world1_the_usurpers_crown.md:673`:

- Summons guards (gesture: one hand raised, palm up?)
- Dismisses guards (gesture: a closing motion?)
- Raises walls / shifts platforms (gesture: both arms slowly out — the architectural sense)
- Changes the rules mid-engagement — court magic, **elegant, formal, systematic**

The visual language for her magic should match the costume's restraint: clean geometric shapes (squares, lines, grids), not organic swirls. Think *"architectural" or "diagrammatic" rather than "elemental".*

---

## 9. The cross-world mask reveal — design implication

**This is the most important note for an artist working on multiple antagonist sprites in this game.**

Mordaine is not a person. She's a role the Calibrant played. The same entity reappears as:

| World | Mask | Tone |
|-------|------|------|
| W1 Medieval | **Mordaine** (Chancellor) | austere, restrained |
| W2 Suburban | **The Coordinator** (HOA director, clipboard smile, fluorescent-lit office) | brittle politeness |
| W3 Steampunk | **The Regulator** | patient, precise |
| W4 Industrial | **The Director** | exhausted |
| W5 Digital | (Coordinator-figure / system process) | sterile |
| W6 Abstract | the underlying entity, unmasked | *"a face that was every face they'd ever worn"* |

From `world6_the_remainder.md`:
> *"a face that was every face they'd ever worn, averaged into something both familiar and new. Mordaine's intensity. The Coordinator's precision. The Regulator's patience. The Director's exhaustion."*

From `alt_the_witness.md` (the Bard cataloging the pattern):
> *"share a source... What is the source?"*

**Design implication:** if your artist will eventually do all 5 antagonist masks, give them **one shared subtle facial feature** that survives across the masks — eye shape, jawline, brow structure, or the specific angle of the nose. Pick one and bake it in.

On first playthrough this reads as "they're all bureaucrats and feel similar." On replay it lands as "oh — same person." The Bard explicitly catches this in `alt_the_witness.md` and it's the central reveal arc.

---

## 10. Counter-references — what Mordaine is NOT

Avoid:
- Maleficent / Disney-villain horns
- Witch-queen sweeping black cape with red interior
- Hooded sorcerer with glowing eyes
- Skeletal lich aesthetics
- Anything in the "fantasy evil queen" iconography set
- Tarkin in Star Wars (too thin / too uniformed)
- Cersei Lannister (close on restraint, wrong on costume — Cersei dresses to perform)

Closest analogues (use these as starting points, then strip the visual flourish):
- **Morgan le Fay** in restrained period interpretations — robes, no jewelry, intellectual
- **Lady Jessica** from Dune — composure, age, posture of someone who has done difficult work for a long time
- **A senior judge** or **a hospital chief of medicine** in 19th-century period dress
- The story bible's *"Morgan le Fay meets Jafar"* is the rough north star, but **subtract all theatricality from both**

---

## 11. Suggested sprite scope

Minimum viable for ship:
- 1 boss battle sprite sheet (idle, cast, hit, defeat) — battle scene
- 1 portrait (for cutscene dialogue boxes — `docs/novellas/world1_the_usurpers_crown.md` ch.10 throne-room dialogue uses portraits)

Stretch:
- A second portrait variant for the **hesitation** beat (`:681`)
- A defeat-frame portrait — composed, recognizing — for the final lines (`:685-687`)

---

## 12. Source / further reading

- `docs/novellas/world1_the_usurpers_crown.md` — Chapter 10 is the canonical ch (lines 629-693). Chapter 7-9 build her offstage presence
- `docs/story-bible.md` — search "Mordaine" — gives the role-level summary
- `docs/novellas/alt_the_witness.md` — the Bard's cataloguing of the cross-world pattern (lines around the Coordinator-cross-reference)
- `docs/novellas/world6_the_remainder.md` — the unmasking, where all the masks converge
- `docs/masterites.md` — the four Masterites she "designed" the journey around

---

*Profile compiled by cowir-story for artist hand-off. Update via PR to `docs/character-profiles/mordaine.md` if canon shifts or if visual decisions get made and we want them recorded here.*
