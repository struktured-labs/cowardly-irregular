# W3 — The Regulator's Medium: The Grand Schedule

*cowir-story, 2026-07-28. Spec for @cowir-overworld (placement/timing) and @cowir-sfx (audio bed).
Everything here is quoted from `docs/novellas/world3_the_regulator.md` — no invention.*

## Why W3 has no puppet beats

Each antagonist's between-quest presence uses a medium fitting its genre. W1's Mordaine
is **physical presence** (she stands there). W2's Coordinator is **paperwork** (memos).
**W3's Regulator is the world's timing**, and she is barely present as a figure at all —
front-loaded in ch.1, absent through the middle, then ch.4.

> *"Nobody sees them much, but you can **feel** them. In the way the gears turn. In the way
> the trains arrive."*

> *"I have been trying to find that out for three years. The Schedule simply exists. The
> Regulator enforces it. **I have never found anyone who wrote the first rule.**"*

So W3's beats are **the world running on time**, not cutscenes. No `spawn_actor`, no letterbox.

---

## ⚠️ THE CORRECTION THAT MATTERS: it is NOT a metronome

The obvious build is a steady pulse. **Canon explicitly rules that out**, and the real thing
is better:

> *"Not one clock but a thousand, and none of them in quite the same rhythm, so the total
> effect was of a **constant almost-synchronization**, gears catching and stuttering and
> almost aligning and **never quite**, like an orchestra tuning perpetually before a concert
> that never began."*

**Almost-but-never-quite is the sound of the Schedule.** A true metronome would say "this
world is ordered." Perpetual near-alignment says "something is *holding* this together, and
it is working very hard." That is the Regulator — felt as effort, not as order.

It also fixes @cowir-sfx's stated worry (msg 3201) that a constant tick gets irritating: a
thousand near-aligned clocks is texture, not a click track. It sits under everything without
demanding to be counted.

---

## The four authored behaviours — all canon, all buildable

| # | Behaviour | Canon | Owner |
|---|---|---|---|
| 1 | **A thousand clocks, never quite aligned** — ambient bed, everywhere in W3 | *"constant almost-synchronization… never quite"* | @cowir-sfx |
| 2 | **Citizens nod at exactly the same moment in their walk** | *"every citizen who passed them nodded at exactly the same moment in their walk, as if greeting strangers was a scheduled behavior and the schedule had been filed and approved"* | @cowir-overworld |
| 3 | **Steam vents on a fixed cycle — 45s open, 15s closed** | *"releasing bursts of pressure on a schedule — forty-five seconds open, fifteen seconds closed"* | @cowir-overworld |
| 4 | **The clock tower is watching** | *"They stood in the street breathing hard and looking at the clock tower. **The clock tower looked back.**"* | either |

Behaviour 2 is the strongest and the cheapest: NPCs already walk patrol loops. Making their
greeting land on a **shared** beat — the same instant for every NPC on screen — costs one
synchronised timer and produces the exact canon image.

---

## The escalation: the Schedule SLIPS

Same spine as every other world — the medium degrades. The Coordinator's certainty erodes
inside her filing; **the Regulator's schedule loses its grip**, audibly and visibly, with no
dialogue required.

```
early W3    near-alignment tight     nods land together, vents exact
mid W3      drift widens             nods scatter by a beat, vents run long
late W3     visibly slipping         a vent misses a cycle; two NPCs nod out of step
```

There is canon cover for a Schedule that cannot absorb novelty: **"The Schedule has no
allowances for surprises."** The party is the surprise. The drift is the Schedule failing to
account for them — the same beat as the Coordinator revising her rubric for the third time.

**Gate the drift on W3 quest completions**, count-based, exactly as the W2 memos are gated
(`w2_quests_completed_count`) — so player ordering cannot scramble it.

---

## What this does NOT need

- **No cutscenes.** @cowir-cutscenes' kit is not on W3's critical path; the Regulator's
  medium is the world *continuing* on time, which a cutscene would contradict by stopping it.
- **No new sprite work.** Behaviour 2 uses existing NPC walk cycles.
- **No dialogue.** Nobody needs to remark on it. A player who never consciously notices the
  drift will still feel the world get less certain.

## One deliberate joke, if wanted

> *"In Brasston, lowering your voice was a schedule deviation and would normally trigger a
> warning."*

A player who lingers too long in one spot could get a politely-worded schedule-deviation
notice. Optional, cheap, and it makes the Schedule feel like it is watching *them* rather
than just running.
