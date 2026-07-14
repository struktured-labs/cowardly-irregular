# Lens System + Job Evolutions — Design Proposal

> **Source:** cowir-battle's design conversation (session `82cf9733`), reconstructed from the transcript. This is the "trait-layer / Lens" thread that was parked mid-discussion — the design is *tentatively landed* on shape, with five sub-questions still open. Nothing here is locked in code.

---

## 1. Status at a glance

- **Tentatively agreed:** a three-layer character model — **Primary (locked)** + **Secondary (one base job)** + **Lens (masterite-axis bundle)**.
- **Recommended granularity:** Option **C (Hybrid)**.
- **Open:** 5 sub-questions (slots, acquisition, binding, world-variants, sprite-visibility) + the name "Lens" itself.
- **Party:** strict-5 is already live in-game; non-lead PCs are AI-controlled until their spotlight chapter unlocks manual control + the autoscript editor.

---

## 2. The three-layer character model

Three independent layers that preserve story's identity guarantee while opening up Bravely-Default-style build flexibility. Each layer does *different* work, so nothing feels mushy.

| Layer | Locked? | What it does | Visual impact |
|-------|---------|--------------|---------------|
| **Primary** (identity) | Hard-locked to the PC | Personality voice, dialogue lens, per-world rename, final essence | Full silhouette |
| **Secondary** (a base job) | Fluid — swappable in camp | One other base job → ability bundle + personality blend + accent | Accent palette + small accessories; silhouette unchanged |
| **Lens** (1–2 slots) | Earned from masterite defeats | Small combat-axis bundle (stat tilt + atomic passive + dialogue tint) | Invisible on sprite; HUD icon only (recommended) |

Example build: **Fighter (primary) + Cleric (secondary, "trained with her") + Warden Lens (from a defeated Warden masterite)** → a *stoic protector who heals a bit and shrugs off damage*. Three layers, three different kinds of weight.

This is essentially **Octopath secondary-job × Diablo paragon-trait × per-world reskin**, with the trait pool being "every other base archetype + every defeated masterite axis."

---

## 3. Job Evolutions by World

Jobs don't "unlock" — they **contextually transform** at world transitions. Your Fighter doesn't learn to be a Security Guard; in a world where swords become batons and armor becomes a uniform, they simply *are* one. The arc across the game: **archetype → individual → essence**.

**World 1 is the exception** — jobs keep base names (Fighter/Cleric/Mage/Rogue/Bard) because the characters are still tropes, easing the player into combat. The first evolution (W1→W2) is disorienting *on purpose* — genre shock is the point, and it's a player-bonding beat ("wait, mine's *also* Security Guard?").

| Base | W1 Medieval | W2 Suburban | W3 Steampunk | W4 Industrial | W5 Digital | W6 Abstract |
|------|-------------|-------------|--------------|---------------|------------|-------------|
| Fighter | Fighter | Security Guard | Steamknight | Enforcer | Firewall | **Resolve** |
| Cleric | Cleric | School Nurse | Steampriest | Safety Officer | Antivirus | **Faith** |
| Mage | Mage | Science Nerd | Alchemist | Lab Technician | Compiler | **Logic** |
| Rogue | Rogue | Skater Kid | Saboteur | Whistleblower | Exploit | **Edge** |
| Bard | Bard | Band Kid | Busker | PA Announcer | Broadcaster | **Voice** |

Key decisions already made:
- **Per-world renames stay deterministic** — everyone becomes "Security Guard." Trait/Lens influence shows up as **personality drift / dialogue tone**, not a different name.
- Each evolution isn't cosmetic — it **shifts the lens** the character thinks through (the Steamknight thinks in mechanical precision; the Alchemist in reactions and catalysts).
- **W6 essences (Resolve/Faith/Logic/Edge/Voice)** are the endpoint; the W6 "collaborator" ending is **story-mandated to require all 5 essences simultaneously** — which is why 4-active + rotating-bench was ruled out and strict-5 shipped.

---

## 4. Trait granularity — the hinge decision

How chunky is a "trait"? Three options were weighed:

**A — Atomic traits** (Path of Exile style): many small passives, slot ~3–5.
- 👍 Rich build-craft; clean masterite economy. 👎 Little narrative weight per trait; doesn't fit the existing sprite-accent canon; nowhere for cowir-story's 5×5 blend grid to live.

**B — Sub-jobs** (FF5 / Bravely Default / Octopath style): one secondary *whole* base job.
- 👍 Heavy narrative weight ("the Fighter trained with the Cleric"); cowir-story's 5×5 grid is built for exactly this; meaningful sprite accents. 👎 Only one secondary at a time; masterites aren't base jobs, so they don't fit cleanly.

**C — Hybrid: one sub-job + one or two atomic Lens slots** ✅ *recommended*
- Primary (locked) + Secondary (base job, the FF5/BD heavy lifting) + Lens (1–2 atomic slots where the masterite axes live).
- 👍 Best of both — narrative-weighty Secondary *and* build-craft via Lenses; masterite economy stays atomic/clean; maps to cowir-story's grid (Secondary) **and** masterite axes (Lenses) without forcing either into the other's shape. 👎 Three layers take longer to teach.

**Constraints that favor B/C over A:** sprite trait-mixing at the *accent* level is already canon (e.g. "fighter + mage secondary = armored character with pointed-hat accents"); cross-class behavior in cutscenes is greenlit (a Fighter with Cleric secondary can visibly heal on-screen); cowir-story's 5×5 blend grid already exists.

---

## 5. What a "Lens" is

Each Lens is a tight **bundle of three things**, so it carries weight in stats, mechanics, *and* voice — without being a full sub-job:

1. **A small stat tilt** (~5–10%) in its axis direction
2. **One atomic passive** (a permanent in-battle effect)
3. **A dialogue tint flag** (late-W5/W6 lines shift tone for that PC — cowir-story authors these)

The **4 masterite axes**, sketched concretely (22 masterite fights across the game map onto these):

### Warden Lens — defense
- **Stats:** +8% DEF, +5% HP · **Passive:** *Iron Will* — incoming critical damage −50% · **Voice:** stoic, measured ("hold the line," "wait it out")
- Fighter+Warden → *stoic-defensive Resolve*; Cleric+Warden → *protective-shield Faith*

### Arbiter Lens — offense
- **Stats:** +8% ATK, +5% CRIT · **Passive:** *Final Word* — guaranteed crit on enemies below 25% HP · **Voice:** judgmental, precise ("they've made their choice," "this ends now")
- Rogue+Arbiter → *executioner Edge*; Mage+Arbiter → *judgment-call Logic*

### Tempo Lens — speed
- **Stats:** +10% SPD · **Passive:** *Stolen Beat* — when you act, your next ally action costs 1 less AP · **Voice:** present-tense, urgent ("now," "between the breaths")
- Bard+Tempo → *rhythmic Voice*; Rogue+Tempo → *blink-edged Edge*

### Curator Lens — resource
- **Stats:** +10% MAG, +15% MP cap · **Passive:** *Accounting* — gain 1 MP each time a party member spends MP · **Voice:** transactional, archival ("we have," "we lack," "we owe")
- Mage+Curator → *librarian Logic*; Cleric+Curator → *bookkeeper Faith*

Voice tints **stack with the Secondary blend**: Fighter (primary) + Cleric (secondary) + Warden Lens reads as *stoic protector who serves* — three layers, none redundant.

---

## 6. Open sub-questions (with cowir-battle's votes)

| # | Question | Options | cowir-battle's vote |
|---|----------|---------|---------------------|
| Q1 | **Slots per PC** | 1 Lens vs 2 | Start with **1**, grow to 2 late-game (post-W4?) |
| Q2 | **Acquisition** | auto-grant the axis you defeated vs pick 1-of-4 | **Auto-grant** (diegetic — "absorb what you faced") |
| Q3 | **Binding** | bound to the killing-blow PC vs pooled for anyone | **Bound-to-killer**, with a camp re-bind option as a late-game sink |
| Q4 | **World variants** | same Lens with stacking dialogue tint vs mechanically distinct per world | **Same mechanically, world tints stack** (avoids balancing 22 Lenses) |
| Q5 | **Sprite visibility** | small sprite accent vs HUD-icon only | **Invisible on sprite, HUD strip icon** (keeps accent-canon clean) |

**The name itself:** "**Lens**" (recommended — implies seeing the world through a filter without changing who you are). Alternatives floated: *Stance* (combat), *Mark* (permanent/branded), *Discipline* (pedagogical), *Inheritance* (spoils-of-war), *Bearing* (behavioral).

---

## 7. Pre-decided constraints (context)

- **Primary is locked** per PC (story-mandated; cannot be swapped).
- **Per-world renames are deterministic** — traits drive personality drift, not the name.
- **Masterites = 4 axes** (Warden/Arbiter/Tempo/Curator), 22 fights, explicitly written as "tests that report back on the player's strengths and weaknesses."
- **Cross-class cutscene behavior is greenlit** (loose diegetic identity lock — one self-identifying line in 60K+ words of canon).
- **cowir-story** recommends the tinting stay **light-touch** (dialogue tone, not path locks) and can draft per-masterite tint tags in ~1 day once the mechanics lock.

---

## 8. Adjacent parked items (from the same session)

- **"Trust"** as the name for the per-PC delegate/autoscript toggle (diegetic: "I'm trusting the Bard to manage this"); UI placement still parked.
- **Masterite-as-essence-tinting** — a Fighter who eats Warden abilities all game lands closer to "stoic-defensive Resolve"; cheap flavor lever, cowir-story can draft tint tags.

---

*Reconstructed by cowir-adhoc from cowir-battle's session transcript, 2026-07-05, at struktured's request. Faithful synthesis of cowir-battle's proposal messages; not a cowir-battle-authored document.*
