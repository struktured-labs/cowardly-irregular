# Provenance — store assets

**This directory is `.gitignore`d on `main` (line 118) and lives on ONE disk in ONE worktree.
This branch exists so that stops being true.**

Checked 2026-09-10 with a filesystem-wide search: `CAPTIONS.md` existed in exactly one place.
The screenshots had a single second copy, inside `tmp/shots-225/tmp/marketing/` — itself an
ignored directory inside a worktree that `tools/reap_release_worktrees.sh` spares only because
its name does not start with `rel-`. One `rm -rf` from gone, and the same hour I reclaimed
69 GB by removing 34 worktrees.

## What is and is not recoverable without this branch

| | recoverable? |
|---|---|
| the 19 screenshots | in principle — re-run the capture tooling against a tag, but several needed specific game states and one (`eldertree_village`) had to be re-shot after a masterite fix |
| `cover/`, `cover-test/` | provisional cover options derived from the title screen; regenerable with effort |
| `CAPTIONS.md` | **NO.** 165 lines of authored editorial prose — gallery ordering, the honest caveat about `battle_storm`'s alpha-0.2 weather reading as a text tag, which shot to lead with. Judgement, not output. |

The PNGs are the bulk; the markdown is the value.

## ⚠️ THE BRANCH IS CANONICAL. THE LANE WORKTREE COPY IS A MIRROR.

There are two copies of this directory: this one (on `store-assets`, versioned) and a
gitignored one in the lane worktree. **They diverged within two hours of this file being
written, and this file caused it** — the refresh procedure below originally read "copy from
the lane worktree into the branch", so I edited PNGs in both places and captions only here.

    lane worktree   CAPTIONS.md 9026 B · 7 caption headings
    this branch     CAPTIONS.md 12633 B · 9 headings, + PROVENANCE.md + MANIFEST.txt

Nothing detected it. The lane copy is the one you reach for by habit, and it was the stale
one — an ignored working copy silently disagreeing with the versioned original, which is the
second failure mode of [ignored means unbacked]: not just unbacked, but *unbacked and wrong*.

**Edit HERE. Mirror outward, never inward.** The lane copy exists so the shot tooling and eye
checks have something local to look at; it is downstream.

## Detecting drift

`tools/verify_store_artifact.sh --compare` already does exactly this job — set comparison
plus per-file checksums, selftested both directions. No second tool:

```sh
tools/verify_store_artifact.sh --compare <lane>/itch-assets <branch>/itch-assets lane branch
# exit 0 identical · 5 they have drifted, naming which files
```

Verified 2026-09-10: it reported the drift above (exit 5, naming CAPTIONS.md and the two
branch-only files), and reported `43 file(s), every checksum matches` after the sync.

## Branch policy

`store-assets` is an ARCHIVE branch. **Do not fold it into `main`** — the `.gitignore` entry on
`main` is deliberate and keeps marketing artifacts out of the game tree. Files here were added
with `git add -f`. To refresh after a re-shoot:

```sh
git worktree add store-assets-wt store-assets
cp -a <lane-worktree>/itch-assets/. store-assets-wt/itch-assets/
cd store-assets-wt && git add -f itch-assets && git commit && git push
```

## Verifying a restore

`MANIFEST.txt` carries a `cksum` per file. After restoring, regenerate and diff it — a restore
that was never read back is a claim, not a backup.

```sh
find itch-assets -type f ! -name MANIFEST.txt -print0 | sort -z \
  | while IFS= read -r -d '' f; do printf '%s ' "$f"; cksum < "$f"; done
```

## ⛔ 2026-09-12 — "LAST RE-TAKEN AT v3.33.267-alpha" IS WRONG FOR 17 OF 20 SHOTS

Measured by sha256 against seven surviving capture directories in the lane's `tmp/`. The
shipped set is a MIXTURE of at least five capture eras, not one:

```
shots-225        battle_storm · field_elite_steampunk · grimhollow_spiral
                 infernal_grotto_f3 · warren_lever_portals · warren_wrap_field
shots-262        battle · frosthold_village · harmonia_village · inn_interior
                 tavern_interior · whispering_cave
shots-267        eldertree_village · grimhollow_village · sandrift_village
shots-262 OR 267 ironhaven_village · shop_interior   (byte-identical in both — unchanged between)
shots-62a1a2d6   title_screen
no local match   field_elite_medieval · field_elite_prompt_medieval
```

⛔ **So `--from v3.33.267-alpha` is the wrong baseline for most of this set**, and
`tools/store_shot_staleness.py`'s documented usage said to use it. Staleness is PER SHOT:
a `shots-225`-era frame has ~119 tags of drift behind it, not 76.

🔑 **AND IT RETRACTS A CLAIM THIS LANE PUBLISHED TWICE TODAY.** The `.343` report said
`whispering_cave`'s frame had drifted while its script had not, from a fresh capture at 4.5x
the shipped bytes (50,654 -> 230,970). The cause is not drift:

```
shipped whispering_cave.png   50,654 B   sha 1913253999384…  == shots-262, byte-identical
shots-267 capture            230,992 B   sha 4c7ca5afb04f…   ~= a fresh .342 capture (230,970)
```

**A 231 KB capture already existed at `.267`. The shipped file is the older `.262` one, and it
was never replaced when the rest of that batch was.** The frame changed BEFORE `.267`; the
staleness was an un-updated file, not content moving underneath a stable script. The tool's
"unchanged" verdict on the script axis was right, my reading of what the byte gap MEANT was
wrong, and only the surviving capture directories could have told the difference.

📌 The `.343` framing also credited `--compare` with finding "the frame changed". What it
actually found is that the shipped file disagrees with a current capture — which is the useful
signal and does not say WHY. Attributing it to drift was inference, not measurement.

## `unshipped-captures/` — captures that existed in exactly one place

Rescued from orphaned worktree directories that a `git worktree prune` had unregistered while
leaving the files (the residue of the prune this lane removed from
`reap_release_worktrees.sh` in `484e7dc7`). None of these was on this branch; the containing
directories are ~18 GB of reclaimable scratch, and deleting it would have taken them.

```
brasston_lift.png · eldertree_canopy.png      shots-225, in store_shots_225.gd's list,
infernal_grotto_f2.png · infernal_grotto_f4.png   captured and never shipped
field_elite_medieval.shots-239-variant.png    1,082,794 B vs the shipped 1,125,674 — a
                                              DIFFERENT frame, kept beside it, not over it
whispering_cave.shots-267.png                 the 231 KB capture the shipped set skipped
```

**These are candidates, not decisions** — whether any belongs in the gallery is @struktured's
call, and `CAPTIONS.md` carries the order and the lead. They are here so the choice survives
the scratch being cleaned.

## `capture-history/` — every surviving capture era, preserved wholesale

**2026-09-12, and it exists because my first rescue was SAMPLED.** I checked two of seven
capture directories, rescued six files, and reported the set safe. Checking all seven found
**31 more files on no branch** — superseded era-variants of shots that ARE shipped, plus the
`shots-267` batch that never replaced the `.262` one.

Preserving all of it beat curating it: **57 files, 9.0 MB.** At that size, deciding which
era-variant matters is a judgement nobody needs to make, and I had just been wrong once about
which files were covered.

```
shoot-prep · shots-225 · shots-239 · shots-262 · shots-267 · shots-62a1a2d6
```

🔑 **`shots-267/` is the forensically useful one** — it holds what the `.267` re-shoot actually
produced for `battle`, `frosthold`, `harmonia`, `inn` and `tavern`, none of which reached the
shipped set. It is the evidence for the era map above, and without it the shipped
`whispering_cave` would still look like drift.

⚠️ **Recoverable in principle, not in practice:** re-running the capture tools at an old tag
needs that tag's tree, a warm import and a sandboxed xvfb run, and would not reproduce a frame
whose difference came from an asset that has since changed. Cheaper to keep 9 MB.

## 2026-09-13 — re-shoot at v3.33.345-alpha: 2 of 11 replaced, and why not the third

`capture-history/shots-345/` holds the full fresh set (11 shots, the scenes
`marketing_shots.gd` can reach). Captured from a worktree at v3.33.345-alpha with
`XDG_DATA_HOME` pointed at a sandbox — verified both directions: 0 files touched in
struktured's live profile during the run, 8 in the sandbox.

`--compare` against the shipped set called three MOVED. The eye disagreed with the bytes on
one of them, which is exactly what that tool's own closing line warns about:

| shot | bytes | verdict |
|---|---|---|
| `whispering_cave` | 50,654 -> 230,968 (+356%) | **REPLACED.** The stored frame is flat-lit; the dungeon lighting that landed after the shot was taken is absent from it. The shipped image shows a version of the cave that no longer exists. ⚠️ The new one is *dark* — accurate, and a harder read as a thumbnail. Editorial call, easy to revert. |
| `frosthold_village` | 83,598 -> 101,696 (+22%) | **REPLACED.** Straight improvement: snow banks, pines, lampposts and a fence where the stored frame is bare brick. |
| `battle` | 153,385 -> 176,134 (+15%) | **NOT replaced — the fresh frame is WORSE.** Two speech bubbles overlap each other and the action menu, and a tooltip sits across the field; the text is illegible where they collide. The capture lands mid-dialogue. Bytes grew because the frame gained clutter. |

⛔ **`--compare`'s 5% MOVED threshold is below this capture's noise floor.** Two independent
captures of the *identical tree*, identical protocol:

```
tavern_interior   6.82%   <-- MOVED on one run, "same" on the other. Same commit.
eldertree 1.48 · ironhaven 1.38 · inn 1.34 · battle 1.16 · frosthold 1.04
sandrift 0.87 · harmonia 0.34 · grimhollow 0.21 · whispering_cave 0.02 · shop 0.00
median 1.04%
```

Villages and interiors spawn wandering NPCs and the script waits a fixed number of frames, so
the frame differs run to run. 10 of 11 stay under 1.5%, but one exceeds the threshold on noise
alone. **A single-run MOVED under ~7% is not evidence.** The three above were stable across
both runs; `tavern_interior` was not, and was not touched.

📌 `MANIFEST.txt` was stale before this change: it listed 42 files against a tree of 116 (the
whole `capture-history/` archive was missing), and `CAPTIONS.md` + `PROVENANCE.md` checksums
had already drifted. Regenerated here. A manifest that is not regenerated when the archive
grows cannot detect the loss it exists to detect.

## 2026-09-16 — `capture-history/shots-356/`, a full era at `v3.33.356-alpha`

Twelve captures, the whole `marketing_shots.gd` set, taken while the store served
`v3.33.356-alpha+93272a40d` and read back identical on all three channels the same hour. Stored
wholesale per this file's own rule — the first rescue was sampled, so eras go in complete.

```
harmonia · ironhaven · frosthold · sandrift · eldertree · grimhollow   villages
inn · tavern · shop   interiors        whispering_cave   dungeon
battle          the shipped framing, re-taken
battle_advance  NEW — never shipped, never captured before this era
```

`battle_advance.png` is also in `unshipped-captures/`, which is the directory for candidates
rather than decisions. `CAPTIONS.md` carries why I did not place it in the gallery myself.

**Capture conditions, stated because a shot's provenance is its conditions:**

```
worktree     <lane>/tmp/pub356, the publish's own worktree, at the tag, already imported
command      XDG_DATA_HOME=$PWD/tmp/shot_xdg xvfb-run -a godot --rendering-driver opengl3 \
             --audio-driver Dummy --resolution 1920x1080 -s tools/marketing_shots.gd
sandbox      the XDG prefix is NOT optional — godot resolves user:// by application name, so
             an unprefixed run writes into struktured's live save directory from any worktree.
             Two runs, both prefixed; the profile they created is in tmp/shot_xdg and nowhere else.
output       1280x720, matching the shipped set, despite --resolution 1920x1080
```

⛔ **This era exists BECAUSE of a measurement that told me not to re-shoot.** The script axis said
`harmonia_village` had moved since `.345` and the frame axis said it had not — 0.50% against a
0.01% run-to-run swing. Preserving the era is worth doing anyway; replacing the shipped frames
was not, and the `capture-history/` convention is what lets the second half be true without
losing the first.

⚠️ **The comparison is only trustworthy because it used two fresh captures.** `tavern_interior`
swings **3.37%** between two runs of the same build — so a single-capture comparison would have
reported it MOVED at −4.5% and been wrong. Ten of the eleven swing 0.00–0.03%; that one frame is
the reason the second directory is not optional.

## 2026-09-20 — `title_screen.png` re-shot at `v3.33.468-alpha`

The store's primary image displayed **`v3.33.215-alpha (62a1a2d6)`** in its bottom-right corner
while the store served `v3.33.468-alpha` — **253 releases stale**, on the first image a
prospective player sees. Re-shot from a worktree AT the shipped tag (`e2c65092`), sandboxed,
so the frame depicts what players actually download. New stamp: `v3.33.468-alpha (e2c65092)`.
The superseded image is kept at `capture-history/shots-62a1a2d6/title_screen.png`.

⚠️ **AND THE MEASUREMENT THAT MATTERS FOR THE OTHER NINETEEN: THE ART DID NOT CHANGE.**
Old vs new, same 1280x720 frame:

```
pixels differing >8 : 898 of 921,600  (0.1%)
  in the version-label box : 656
  everywhere else          : 242       (0.026% of the frame)
```

`tools/store_shot_staleness.py` reports `title_screen` as **changed** because
`src/ui/TitleScreen.gd` moved between the two tags — and it is right, and its own caveat is
the important half: *"changed -> a candidate for a re-shoot, NOT proof the image is wrong."*
Here the script moved and the rendered frame did not. **A script-level signal over-predicts
frame change; only a pixel diff answers "does this image need re-taking".** So the standing
"11 of 20 depict a scene script that changed" is a candidate list, not a work list, and
anyone planning a re-shoot should diff the frames first — the method is one `ImageChops`
call and it cost minutes here.
