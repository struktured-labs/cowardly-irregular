
# Cowardly Irregular – Consolidated Conversation Summary
Generated: 2026-03-08T03:37:14.159677

This document summarizes prior design discussions for use by automated story-writing or code agents.

---

## Core Project Concept
**Cowardly Irregular** is a replayable JRPG-inspired game combining classic JRPG structure with modern automation systems.  
Key influences include Chrono Trigger, Bravely Default, and some CRPG mechanics.

Design goals:
- Strong narrative with replay variability
- Job-driven personality systems
- Automation systems (autobattle, autogrind) that alter gameplay style
- Player style influences narrative tone and ending
- Meta-aware final antagonist that acknowledges the player as victor

---

# Narrative Framework

## Central Theme
The game world exists partly to challenge the player. The final villain ultimately acknowledges the player’s victory and admits it cannot keep sustaining the challenge.

The narrative adapts based on:
- Job affinities
- Party composition
- Playstyle (traditional combat vs automation)

Possible tones:
- Heroic
- Abstract / cold
- Philosophical

---

# Job System

## Philosophy
Jobs determine:

1. Combat abilities
2. Character personality
3. Dialogue variations
4. Evolution paths
5. Sprite appearance

Personality influenced by:
- Primary job
- Secondary job
- Optional tertiary job
- Player behavior

Example behavior influences:
- Autobattle use
- One-shot builds
- Autogrind use
- Traditional play

---

# Base Jobs Discussed

## Fighter
Classic melee frontline.

Traits:
- Protective
- Direct personality
- Physical damage focus

Abilities:
- Fight
- Guard (take damage for allies)
- Passives around durability and leadership

Evolution ideas:
- Knight
- Champion
- Possibly Masterite-level evolution

Sprite style:
- Western medieval inspiration
- 8–12 bit pixel style

---

## Mage (Base Magic Class)

Base magical job that evolves in multiple moral directions.

Traits:
- Curious
- Analytical

Evolution examples:
- Wizard (scholarly path)
- Dark Mage
- Necromancer (chaotic destructive path)

Necromancer traits:
- High damage
- Can harm party and self
- Potentially destructive to save states

Movement style:
- Reserved
- Staff-based combat

---

## Cleric

Early accessible healing class.

Design direction:
More traditional Christian aesthetic rather than modern JRPG priest tropes.

Typical archetype:
- Pious
- Quiet but strong-willed
- Beautiful but serious
- Devout faith

Abilities:
- Healing
- Protection
- Sacrifice-based mechanics

Potential mechanic:
The more devout or sacrificial the character becomes, the stronger abilities grow.

---

## Rogue / Skiptrotter
Fast evasive class.

Traits:
- Speed
- Sneak attacks
- High crit chance

Design concept:
Can bypass or manipulate core damage systems.

Evolution directions:
- Ninja
- Assassin
- Trickster variants

---

## Speculator (Economic Class)

Origin world:
90s / Earthbound / steampunk-like environment.

Possible variants:
- Merchant
- Gambler
- Statistician
- Quant
- Wallstreet archetypes

Mechanics:
- Macro volatility manipulation
- Economy-influenced combat mechanics
- Probability manipulation

---

# Job Evolution System

Jobs evolve depending on:

1. Player choices
2. World phase
3. Moral alignment
4. Gameplay behavior

Examples:

Mage → Wizard  
Mage → Dark Mage  
Mage → Necromancer  

Fighter → Knight → Masterite

Evolution sprites change significantly across overworld eras.

---

# Masterites

Renamed from “Asterik”.

Definition:
Elite evolved classes or boss-tier entities.

Functions:
- Major bosses
- Advanced evolutions
- Endgame challenges

Late-game content includes:

**Boss Rush**
- Masterites fought sequentially
- Sometimes grouped together

---

# Combat Systems

## Traditional Battle
Classic JRPG command combat.

## Autobattle
Basic AI-controlled combat.

## Autogrind (Major Feature)

Advanced automated leveling system.

Players configure grinding parameters.

Benefits:
- Rapid leveling
- Efficient farming

Restrictions:
- Boss fights normally excluded
- Some late-game exceptions

Endgame challenge:
Autogrind the entire boss rush.

Extremely difficult but possible.

Rewards may include:
- Special equipment
- Alternate ending variations

---

# Endgame & Multiplayer

After final boss defeat:

Unlocks:
- Offline multiplayer simulation
- Strategy leaderboards

Leaderboard categories:
- Largest hits
- Fastest victories
- Most creative builds
- Automation strategies

---

# Art Direction

## Pixel Art

Target style:
- 8-bit to 16-bit hybrid
- Slightly western aesthetic
- Clear readable sprites

Sprite sizes tested:
- 32x32
- 48x48
- 64x64
- 128x128

Preferred direction:
~48 or 64 for overworld sprites.

Evolution sprites must visibly transform between job stages.

---

# Overworld Design

Multiple thematic eras / worlds.

Jobs visually adapt across worlds.

Examples:
- Medieval fantasy
- 90s earthbound-like world
- Abstract worlds

---

# Core Design Pillars

1. Replayability through personality systems
2. Automation without removing player agency
3. Strong job identity
4. Meta-aware storytelling
5. JRPG nostalgia with mechanical innovation

---

# Intended Audience

Players who enjoyed:
- Bravely Default
- Chrono Trigger
- Classic JRPG job systems

But want:
- deeper mechanics
- automation systems
- more replay variability

---
