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
