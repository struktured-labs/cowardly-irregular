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
