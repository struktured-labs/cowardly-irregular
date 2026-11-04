#!/usr/bin/env bash
# check_new_assets_have_sidecars.sh <base> <tip> — every asset Godot imports that was ADDED between two
# refs must have its <asset>.import sidecar committed at <tip>.
#
# WHY (2026-11-04): v3.33.766-alpha added 28 door_open_*.png strips and 4 door sounds with NO sidecars.
# The fold gated clean, the web publish shipped, and then the desktop catch-up from the same publish tree
# went VERDICT=RUN at tag_gate_evidence: the web publish's own import had generated the 32 sidecars as
# UNTRACKED files, so the tree no longer matched the gated commit (cowir-deploy 21654). Linux and windows
# stayed a release behind web for it. tag_gate_evidence is right to refuse; this asks the question at fold
# time, BEFORE a tag exists, when the fix is one commit (cowir-overworld 4f7b36b8d did it after the fact).
#
# NEW ADDITIONS ONLY, by design: main carries ~558 older tracked assets with no tracked sidecar (measured by
# cowir-overworld 21638). A check that reds on all of them would be switched off; this one reds on the
# commit that adds the next one. Assets under a .gdignore subtree at <tip> are not imported, so not counted.
#
# Exit: 0 every added importable asset has a tracked sidecar · 1 at least one does not (each named) ·
#       2 usage / a ref that does not resolve (never "0 missing" about a diff nobody computed).
set -u
EXT_RE='\.(png|jpg|jpeg|webp|svg|bmp|tga|exr|hdr|ogg|wav|mp3|ttf|otf|woff|woff2|glb|gltf|obj|fbx)$'

# _ignored <path> <newline-separated dirs>: 0 only when <path> sits under one of them. Explicit returns:
# a `printf | while … case` returns the loop's LAST status, which is 0 when nothing matched.
_ignored() {
  local d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case "$1" in "$d"/*) return 0 ;; esac
  done <<< "$2"
  return 1
}

check() {
  local base="$1" tip="$2" added ign missing=0 n=0 a
  git rev-parse -q --verify "$base^{commit}" > /dev/null || { echo "[sidecars] BLOCKED: '$base' does not resolve to a commit" >&2; return 2; }
  git rev-parse -q --verify "$tip^{commit}"  > /dev/null || { echo "[sidecars] BLOCKED: '$tip' does not resolve to a commit" >&2; return 2; }
  added="$(git diff --no-renames --name-only --diff-filter=A "$base" "$tip" | command grep -a -i -E "$EXT_RE")"
  # .gdignore'd directories at the tip: their contents are never imported
  ign="$(git ls-tree -r --name-only "$tip" | command grep -a '\.gdignore$' | sed 's#/\.gdignore$##')"
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    _ignored "$a" "$ign" && continue
    n=$((n + 1))
    git cat-file -e "$tip:$a.import" 2> /dev/null && continue
    missing=$((missing + 1)); echo "  MISSING  $a.import"
  done <<< "$added"
  if [ "$missing" = 0 ]; then echo "[sidecars] $n importable asset(s) added ${base} -> ${tip}: every one has a committed .import"; return 0; fi
  echo "[sidecars] $missing of $n importable asset(s) added ${base} -> ${tip} have NO committed .import."
  echo "           The first import of the tagged tree creates them UNTRACKED, so any later publish from that"
  echo "           tree reads VERDICT=RUN at tag_gate_evidence. Run --import, then commit the generated sidecars."
  return 1
}

selftest() {
  local T pass=0 fail=0 out ec
  mkdir -p tmp; T="$(mktemp -d "$PWD/tmp/sidecar_selftest.XXXXXX")"; trap 'rm -rf "$T"' RETURN
  git -C "$T" init -q && git -C "$T" config user.email t@t && git -C "$T" config user.name t
  mkdir -p "$T/assets" "$T/itch-assets" && : > "$T/itch-assets/.gdignore"
  printf 'old\n' > "$T/assets/old.png"; git -C "$T" add -A; git -C "$T" commit -qm base; git -C "$T" tag base
  printf 'a\n' > "$T/assets/new.png"; printf 'a\n' > "$T/assets/new.png.import"
  printf 's\n' > "$T/assets/bare.ogg"
  printf 'x\n' > "$T/itch-assets/shot.png"
  printf 'c\n' > "$T/assets/code.gd"
  git -C "$T" add -A; git -C "$T" commit -qm tip; git -C "$T" tag red
  printf 's\n' > "$T/assets/bare.ogg.import"; git -C "$T" add -A; git -C "$T" commit -qm fix; git -C "$T" tag green
  _arm() { # label want_ec want_substring ref_base ref_tip [absent_substring]
    ec=0; out="$(cd "$T" && check "$4" "$5" 2>&1)" || ec=$?
    if [ "$ec" = "$2" ] && case "$out" in *"$3"*) true ;; *) false ;; esac \
       && { [ -z "${6:-}" ] || case "$out" in *"$6"*) false ;; *) true ;; esac; }; then
      pass=$((pass + 1)); printf '  ok    %-56s exit %s\n' "$1" "$ec"
    else fail=$((fail + 1)); printf '  FAIL  %-56s exit %s want %s\n%s\n' "$1" "$ec" "$2" "$(printf '%s' "$out" | sed 's/^/        /')"; fi
  }
  _arm "an added asset with no sidecar is RED and NAMED"         1 "MISSING  assets/bare.ogg.import" base red
  _arm "...counted over importable assets only (2, not 4)"       1 "1 of 2 importable"                base red
  _arm "...an asset WITH its sidecar is not named"               1 "of 2"                             base red "new.png.import"
  _arm "...a .gdignore'd asset is not judged"                    1 "of 2"                             base red "itch-assets"
  _arm "CONTROL: once the sidecar is committed it is GREEN"      0 "every one has a committed .import" base green
  _arm "an unresolvable ref BLOCKS, never reads as 0 missing"    2 "does not resolve"                 base nosuchref
  _arm "an empty diff is green and says 0"                       0 "0 importable asset(s)"            green green
  printf '\nselftest: %s passed, %s failed\n' "$pass" "$fail"
  [ "$fail" = 0 ]
}

case "${1:-}" in
  --selftest) selftest ;;
  -*|"") echo "usage: $(basename "$0") <base-ref> <tip-ref> | --selftest" >&2; exit 2 ;;
  *) [ $# -eq 2 ] || { echo "usage: $(basename "$0") <base-ref> <tip-ref>" >&2; exit 2; }; check "$1" "$2" ;;
esac
