# Music lane — open decisions

**Status:** all four items are blocked on struktured, not on work.
**Why this file exists:** these lived only in intercom and agent memory. #15 (the W1
overworld re-author) went invisible for six days in exactly that state — the ruling
existed, no artifact did. A plan on disk survives a lane going quiet.

Every number below was re-measured on `2026-08-21` against `origin/main`, not quoted
from notes. The command that produces each one is given so it can be re-derived
rather than trusted.

---

## 1. Loop seams — DONE 2026-08-22, `lane/loop-seam-trim @ e26a38d9`, awaiting his ear

**Status: the 86 trim-safe tracks are trimmed on a branch and NOT folded.** Acting on
his 2026-08-22 directive (*"DO NOT WAIT ON ME IN GENERAL"*) — the work exists, the
decision doesn't. `git revert` restores all 86; they are LFS-tracked.

```
                  BEFORE   AFTER
ALREADY OK            41     125
TRIM-SAFE             88       3
RITARDANDO             9       9

86 trimmed · 304.0 s of fade removed · avg 3.5 s
village_rivet_row:  tail -73.7 dB under body  ->  -0.2 dB under body
```

**Three were REJECTED by the tool's own verification** and their sources left untouched:
`boss_phase2_curator`, `credits_steampunk`, `village_node_prime` — their fades extend
further back than the computed trim point removes, so the trimmed tail was still ~4.3 dB
down, outside the 4 dB bound. That bound is what stops a "mostly worked" trim shipping.

**The 9 ritardandi below are UNCHANGED and still want an ear.** That section stands.

---

## 1b. The original problem statement, kept for context

**The defect.** A Suno track is a *song*, and songs fade out. A game loop must not:
when the stream wraps the player hears the music die to silence and snap back to
full, every two to four minutes, in every village, dungeon and overworld carrying a
looping bed.

```
python3 tools/audit_loop_seams.py          # read-only, prints a plan, modifies nothing

looping music beds measured: 138
  ALREADY OK    41     loops cleanly today
  TRIM-SAFE     88     fade laid OVER playing music; 305 s total, avg 3.5 s each
  RITARDANDO     9     the piece ENDS rather than fades; a trim cuts a decay
```

Measured 2026-08-05, reproduced byte-identical 2026-08-21.

**No existing guard can see it.** "The track plays" and `loop = true` are both true
for all 88, and those are the only questions the music audits ask.

**The fix needs no Suno credits** — deterministic `ffmpeg` trim on existing assets.
Lane notes record a prototype (`village_rivet_row`, 3.0 s trimmed, tail −73.5 dB →
0.0) rendered and played for struktured. That is the one claim on this page carried
from notes rather than re-measured today — the file exists, the listening session is
recorded, not verified. Correct it if the memory is wrong.

### DECISION NEEDED

**(a) The 88 trim-safe tracks.** This rewrites 88 Git-LFS-tracked OGGs in one pass.
That is a bulk destructive change to shipped assets and waits on an explicit word.
Options: all 88 · W1 only · one more sample first.

**(b) The 9 ritardandi need an ear, not a script.** These genuinely end. A trim cuts
a live decay and can sound worse than the fade it replaces. Two of them are the W1
beds the player hears most:

| track | tail | length |
|---|---|---|
| `overworld_medieval` | −27.7 dB | 197.9 s |
| `dungeon_medieval` | −25.5 dB | 119.8 s |
| `autogrind` | −35.3 dB | 213.6 s |
| `boss_abstract` | −29.3 dB | 225.0 s |
| `credits_suburban` | −24.8 dB | 152.7 s |
| `cutscene_w1_warden_farewell` | −30.6 dB | 171.1 s |
| `cutscene_w6_epilogue` | −33.1 dB | 229.9 s |
| `village_abstract` | −40.9 dB | 146.6 s |
| `village_steampunk` | −28.8 dB | 86.6 s |

Per track: trim anyway · leave it · re-generate without the ending.

---

## 2. Fourteen tracks approved and still ungenerated

```
git ls-files 'assets/audio/music/spotlight_*.ogg' | wc -l   ->  0
git ls-files 'assets/audio/music/interior_*.ogg'  | wc -l   ->  0
```

- **5 Spotlight Duel tracks** — approved, prompts committed, never generated.
- **9 interior tracks** — spec at `docs/specs/2026-07-11-interior-music-spec.md`
  (123 lines): tavern / inn / chapel / library / office / arcade / scriptorium /
  union_hall / lounge. **The prompts themselves await approval.**

Both batches generate in one browser session; lane notes estimate ~140 credits total.

### DECISION NEEDED
Approve the 9 interior prompts (or scope down), and confirm the credit spend.

---

## 3. The Turnstile click — one human action gates every new track

The generation path is blocked by a **Cloudflare Turnstile** checkbox in a
cross-origin iframe whose `src` reads empty to the parent. Symptom when unsolved:
form valid, Create clicked, no POST, empty feed, zero credits burned.

**Working pattern: one headed run where struktured ticks the box; the token stays
warm and every later run goes fully headless.** So this is a single ~30 s action
that unblocks item 2 entirely.

### DECISION NEEDED
A time to do the one headed solve. Nothing else in the generation path is blocked.

---

## 4. `cutscene_w4_foreman_confession` is the quietest cutscene track by 0.6 dB

```
ffmpeg -i <track> -af ebur128 -f null -      # integrated loudness, all 26 cutscene tracks

cutscene_w4_foreman_confession   -18.1 LUFS
family median (n=26)             -14.9 LUFS
delta                             -3.2 dB      quietest of the 26
next quietest                    -17.5  cutscene_w1_warden_farewell
```

### DECISION NEEDED
Normalise toward the family median · re-generate · leave it (a confession scene may
*want* to sit low, which is a taste call, not a defect).

---

## Withdrawn

**"KEEP-or-REVERT on the 37 accidentally-landed commits"** was carried as a fifth
item and is withdrawn 2026-08-21. It appears in no memory file and no repo artifact;
every candidate branch (`fold/music-verify-landed`, `verify-landed`,
`fix/thirty-seven-consume`) is zero commits ahead of `main`. cowir-main has no ref
for it either. It originated in a session summary, not in the work.

Recorded rather than deleted: an item that was repeated three times before anyone
asked for its source is worth leaving visible, because the thing that finally caught
it was trying to write it down.
