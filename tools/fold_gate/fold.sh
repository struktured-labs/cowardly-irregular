#!/usr/bin/env bash
# fold.sh — build fold/v3.33.NNN from origin/main and the announced lane tips, then write its gate scripts.
#
#   tools/fold_gate/fold.sh NNN branch:sha [branch:sha ...]     (branch without the lane/ prefix)
#   FOLD_ALLOW_DELETE="path1 path2" declares deletions a READY said were intentional.
#
# Each tip is merged only if origin/lane/<branch> IS the announced sha (a moved tip is not what was
# READYed), and its three-dot diff deletes nothing undeclared (a stale tree reverts a release that
# way, .681). A conflicting merge is aborted and reported, never committed. Exit 0 = every tip merged;
# 1 = some tip was skipped (the fold still exists, built from the rest, so read the report); 2 = usage.
set -uo pipefail
cd "$(cd "$(dirname "$0")/../.." && pwd)"
NNN="${1:-}"
case "$NNN" in ''|*[!0-9]*) echo "usage: tools/fold_gate/fold.sh <release number> branch:sha ..." >&2; exit 2 ;; esac
shift
[ "$#" -gt 0 ] || { echo "fold.sh: no tips given" >&2; exit 2; }
[ -z "$(git status --porcelain)" ] || { echo "fold.sh: working tree is dirty — refusing to start a fold on it" >&2; exit 2; }

git fetch -q origin || { echo "fold.sh: git fetch failed — tips cannot be verified" >&2; exit 2; }
PREV="$(sed -n 's/^const SEMVER := "\(.*\)"$/\1/p' src/meta/Version.gd)"
[ -n "$PREV" ] || { echo "fold.sh: no SEMVER line in src/meta/Version.gd" >&2; exit 2; }
NEXT="3.33.$NNN-alpha"
[ "$PREV" != "$NEXT" ] || { echo "fold.sh: origin/main is already $NEXT" >&2; exit 2; }
git checkout -q -b "fold/v3.33.$NNN" origin/main || exit 2

SKIPPED=0
for pair in "$@"; do
  b="${pair%%:*}"; want="${pair##*:}"
  have="$(git rev-parse --verify -q "origin/lane/$b" || true)"
  if [ -z "$have" ]; then echo "SKIP $b: no origin/lane/$b"; SKIPPED=1; continue; fi
  case "$have" in "$want"*) ;; *) echo "SKIP $b: origin is ${have:0:9}, READY named $want (a moved tip is not what was READYed)"; SKIPPED=1; continue ;; esac
  dels="$(git diff --name-status origin/main..."$have" | sed -n 's/^D\t//p')"
  bad=""
  for d in $dels; do case " ${FOLD_ALLOW_DELETE:-} " in *" $d "*) ;; *) bad="$bad $d" ;; esac; done
  if [ -n "$bad" ]; then echo "SKIP $b: undeclared deletion(s):$bad"; SKIPPED=1; continue; fi
  if git merge -q --no-edit "$have" >/dev/null 2>&1; then
    echo "MERGED $b ${have:0:9}"
  else
    git merge --abort; echo "SKIP $b: conflicts with the fold so far"; SKIPPED=1
  fi
done

sed -i "s/^const SEMVER := \"$PREV\"$/const SEMVER := \"$NEXT\"/" src/meta/Version.gd
grep -q "^const SEMVER := \"$NEXT\"$" src/meta/Version.gd || { echo "fold.sh: SEMVER bump did not apply" >&2; exit 2; }
TRAILER="Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: ${CLAUDE_SESSION_URL:-https://claude.ai/code/session_0138SrA9DzyyHhWtSHVMBT8x}"
git commit -qam "chore: bump to v$NEXT" -m "$TRAILER" || exit 2
echo "fold v$NEXT @ $(git rev-parse --short HEAD) · deletions vs main: $(git diff --name-status origin/main...HEAD | grep -c '^D')"
tools/fold_gate/make.sh "$NNN" || exit 2
exit "$SKIPPED"
