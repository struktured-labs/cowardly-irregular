# W4 — The Director's Medium: Surveillance

*cowir-story, 2026-07-28. Spec for @cowir-overworld (props/UI) and @cowir-cutscenes (the events half).
Quoted from `docs/novellas/world4_the_assembly.md`. Completes the medium set — W1 presence,
W2 memos, W3 timing, W4 surveillance, W5/W6 endgame.*

## The medium

> *"The monitors were the first thing they noticed — not the buildings, not the people, but
> the monitors."*

The Director's presence is **being watched, and knowing it.** He's the most evenly distributed
antagonist in the game — present in every chapter of W4 — because he doesn't need to appear.
The monitors are him.

And unlike W1–W3, **his medium addresses the player directly**: the screens show *their* data.

---

## The four authored behaviours

| # | Behaviour | Canon | Owner |
|---|---|---|---|
| 1 | **Monitors everywhere**, unavoidable, the first thing you see | *"not the buildings, not the people, but the monitors"* | @cowir-overworld |
| 2 | **Your profile data in the corner of every screen** — small, under the main display | *"in the corner of the screen, small, running underneath the main display: their profile data"* | @cowir-overworld |
| 3 | **A counter appears, and counts down** — on the second day, in the corner of every screen | *"a counter she hadn't noticed before — and then realized she was supposed to not notice it"* · *"Just a number, in the corner of every screen, going down."* | @cowir-cutscenes (the *appearance* is an event) |
| 4 | **The maintenance tunnels are the only place without monitors** | *"the maintenance tunnels were the only part of Rivet Row that didn't have monitors"* | @cowir-overworld |

---

## The one that matters: show the player's REAL data

Behaviour 2 is the whole medium, and it is cheap and devastating: **the corner of every W4
monitor displays the party's actual live stats** — real level, real HP, real battles won, real
automation ratio. Not flavour text. The numbers the player recognises as theirs.

Every other antagonist watches the party. **The Director shows them the file, in public, on
the wall, in a font too small to be a threat.** Nothing needs to be said about it.

This also makes W4 the world where the game's own telemetry becomes diegetic — which is on
thesis for a game about automation being visible to the system.

### ⚠️ WHICH fields — two are currently broken (@cowir-battle, msg 3247)

Making telemetry player-facing **promotes any defect in it from cosmetic to visible**, because
the whole power of the idea is *"those are MY numbers."* Two of the obvious fields have known
defects on struktured's ruling queue right now:

| field | state |
|---|---|
| level, HP, playtime | ✅ no known defects — safe to display |
| **`battles_won`** | ❌ **under-counts by five** — the spotlight-duel short-circuit returns above the increment, so every W1 duel the player fought and won is missing |
| **automation ratio** | ❌ derived from `battles_won`, so inflated; same signal that makes two W6 endings unreachable |

A player who fought five duels and sees a total excluding them has a **visible discrepancy in
the one place the game claims to be showing them the truth.** That would be the feature
undermining itself.

**Ship with the safe fields; leave hooks for the other two.** They're also the two that most
sell the premise, so they're worth waiting for the ruling rather than shipping wrong.

---

## The escalation: the counter

W1 escalates by how much the game stops. W2 by the Coordinator's certainty eroding. W3 by the
Schedule slipping. **W4 escalates by a number going down that nobody explains.**

```
arrival      monitors show generic Rivet Row output
early        your profile data appears in the corner, small
mid          a counter appears — no label, no explanation. It decreases.
late         it is decreasing faster, and it is on EVERY screen
```

**Nothing in the game should ever explain the counter.** Canon is explicit that it's designed
to be half-noticed — *"she was supposed to not notice it"* — and the Director's whole method is
information delivered without confrontation. A tooltip would destroy it.

Gate count-based on W4 quest completions, same as W2's memos and W3's drift, so player
ordering can't scramble it.

---

## The refuge, and why it's worth building

> *"the maintenance tunnels were the only part of Rivet Row that didn't have monitors"*

One location with **no screens and no corner data**. It costs nothing — it's the absence of
the prop — and it makes the monitors legible by contrast. A player who never consciously
registered being watched will feel the tunnels as relief and not know why.

If anything wants to be *found* down there, that's the natural home for it.

### ⚠️ The relief is AUDIO, not visual (@cowir-sfx, msg 3246)

The above is incomplete as originally written. **Contrast needs two terms** — if the monitors
are silent, the tunnels are silent too, and the refuge is visually identical to everywhere
else with nothing to feel.

**The monitored spaces need a continuous low room-tone; the tunnels are where it stops.**
That's the fridge-you-stop-hearing effect, and it's one of the few tricks that works *better*
on a player who never consciously noticed.

No new asset required: **`ambient_office` already ships**, and @cowir-overworld already
consumed it for the two W2 civic interiors — the wiring pattern is proven in the same lane
that owns W4's props. One `play_ambient()` per monitored area.

**It must be boring.** If the bed is interesting the player attends to it consciously, and the
tunnels then read as *"the music stopped"* rather than as relief. This argues for reusing the
flat office tone rather than composing something characterful — the sound should only exist in
its own absence.

### Corollary: the counter is SILENT

The no-explanation rule applies to audio, and a cue is the obvious thing to reach for.
**No sound when the counter ticks.** A sound is an explanation — it tells the player this is a
thing to attend to, which is exactly what canon forbids. If it ever wants audio at all, the
moment is the *last* decrement, and none of the ones before it.

---

## The split @cowir-cutscenes asked for

- **Yours:** the *appearance* of the counter (behaviour 3). Something changing on every screen
  at once is an event, and it wants a moment — even a small one. Possibly a camera beat on a
  single monitor.
- **@cowir-overworld's:** monitors as props, the live corner readout, the monitor-free tunnels.
  Standing world state, not events.

**Neither needs a puppet.** The Director never stands in a corridor. He is on the wall, and
the wall is everywhere.
