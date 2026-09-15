#!/usr/bin/env bash
# Does the GitHub Release for a tag actually contain the game's audio?
#
#   tools/verify_release_artifact.sh <tag>
#   tools/verify_release_artifact.sh --file <built binary>   (floor at HEAD; what CI runs before publishing)
#   tools/verify_release_artifact.sh --selftest
#
# WHY THIS EXISTS
# ---------------
# The release workflow checks out with `actions/checkout@v4` and NO `lfs: true`, so the 500
# LFS-backed .ogg files arrive as pointer text, the godot import of them fails, and the export
# packs a game with no audio. It boots. It does not crash. It cannot load music -- measured by
# sandboxed boot: `No loader found for resource: (expected type: AudioStreamOggVorbis)` on
# title.ogg, against a gated control with 0 audio errors. Nothing has ever checked it, and the
# builds are downloadable.
#
# Measured 2026-09-13 at v3.33.345-alpha:
#     GitHub Release  cowardly-irregular.x86_64   126,151,088 B
#     itch store      cowardly-irregular.x86_64   321,271,424 B
#     shortfall                                   195,120,336 B  (186.1 MiB)
#
# ⛔ DO NOT COUNT 'OggS' PAGE HEADERS. It is the obvious probe and it is BLIND: both builds
# above contain exactly 334, so it reports "100% of the audio present" about a build missing
# 186 MiB of it. Byte size against the LFS manifest is what separates them.
#
# THE CHECK IS A FLOOR, NOT A COMPLETENESS TEST
# ---------------------------------------------
# The repo declares its own audio corpus, so the expected size is DERIVED, never a constant
# that would go stale the next time a track lands: an artifact that packs the game's audio
# cannot be smaller than that audio. Passing means "not obviously audio-less"; it does not
# certify the build. Failing is conclusive.
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

REPO="${RELEASE_REPO:-struktured-labs/cowardly-irregular}"

# Total bytes of the LFS-backed .ogg corpus, read from git, not remembered.
# ⛔ AT A REF, NOT THE CHECKOUT. This read the CURRENT tree whatever tag it was asked about,
# so every older release was judged against today's corpus. Measured 2026-09-14: v2.2.0-alpha
# carried 194 LFS .ogg / 321 MB, the tree at v3.33.349-alpha 502 / 192 MB -- the "floor" for
# the March release was off by 129 MB. And "the current tree" meant whichever CHECKOUT the tool
# ran from: run from a stale lane worktree (425 .ogg) it gave v3.33.349-alpha a 425-object floor,
# where that tag's own tree has 502. The answer depended on where you stood, not what you asked.
# No real release's verdict flipped (every downloaded asset was below every floor), but a floor
# describing the wrong tree is a coincidence waiting for the corpus to move.
# Arg: a ref; empty means HEAD, which is what it always did.
lfs_audio_floor() {
    git lfs ls-files -s ${1:+"$1"} 2>/dev/null | awk '
        /\.ogg/ {
            if (match($0, /\(([0-9.]+) (B|KB|MB|GB)\)/)) {
                s = substr($0, RSTART + 1, RLENGTH - 2)
                split(s, a, " ")
                m = (a[2] == "B") ? 1 : (a[2] == "KB") ? 1024 : (a[2] == "MB") ? 1048576 : 1073741824
                total += a[1] * m; n++
            }
        }
        END { printf "%d %d\n", total, n }'
}

# stdin: "<name> <bytes>" per asset. $1: floor. Prints a verdict line per asset.
# Exit 0 = every asset clears the floor · 5 = at least one does not.
classify() {
    local floor="$1"
    awk -v floor="$floor" '
        { name = $1; size = $2 + 0
          if (size < floor) { bad++; printf "  ⛔ SHORT  %-34s %14d B  <  %d B of LFS audio\n", name, size, floor }
          else              { printf "  ok       %-34s %14d B\n", name, size } }
        END { exit (bad > 0) ? 5 : 0 }'
}

selftest() {
    local pass=0 fail=0 saw_ok=0 saw_short=0 rc
    chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok    $1 -> $2"
            else fail=$((fail+1)); echo "  FAIL  $1 -> got $2, want $3" >&2; fi; }

    # the real numbers, so the arms are pinned to a measurement and not to a guess
    printf 'store.x86_64 321271424\n' | classify 192182170 >/dev/null; rc=$?
    chk "a complete build clears the floor" "$rc" "0"; [ "$rc" = 0 ] && saw_ok=1

    printf 'gh.x86_64 126151088\n' | classify 192182170 >/dev/null; rc=$?
    chk "the audio-less build is SHORT" "$rc" "5"; [ "$rc" = 5 ] && saw_short=1

    # one bad asset among good ones must still red -- a release ships more than one file
    printf 'a 321271424\nb 126151088\nc 349103520\n' | classify 192182170 >/dev/null; rc=$?
    chk "one short asset reds the whole release" "$rc" "5"

    # boundary, both sides
    printf 'edge 192182170\n' | classify 192182170 >/dev/null; rc=$?
    chk "exactly at the floor passes" "$rc" "0"
    printf 'edge 192182169\n' | classify 192182170 >/dev/null; rc=$?
    chk "one byte under the floor reds" "$rc" "5"

    # the SHORT line must name the shortfall, or a red says nothing actionable
    local out; out="$(printf 'gh.x86_64 126151088\n' | classify 192182170)"
    case "$out" in *SHORT*126151088*192182170*) chk "the short line names both numbers" "yes" "yes" ;;
                   *) chk "the short line names both numbers" "no" "yes" ;; esac

    # the floor is DERIVED: it must be a real number read out of this repo, not a constant
    local got n; read -r got n <<<"$(lfs_audio_floor)"
    if [ "${n:-0}" -ge 100 ] && [ "${got:-0}" -gt 100000000 ]; then
        pass=$((pass+1)); echo "  ok    floor derived from this repo -> ${n} .ogg objects, ${got} B"
    else
        fail=$((fail+1)); echo "  FAIL  floor derived from this repo -> n=${n:-?} bytes=${got:-?}" >&2
    fi

    # the floor is read AT THE REF. Pair derived from history, never named: the latest commit
    # that ADDED an .ogg, against its own parent. The two must differ, in the right direction,
    # and HEAD read with no argument must equal HEAD read explicitly.
    local addc; addc=$(git log -n1 --format=%H --diff-filter=A -- '*.ogg' 2>/dev/null)
    if [ -n "$addc" ]; then
        local na fa np fp nh fh ne fe
        read -r fa na <<<"$(lfs_audio_floor "$addc")"
        read -r fp np <<<"$(lfs_audio_floor "${addc}^")"
        if [ "${na:-0}" -gt "${np:-0}" ] && [ "${fa:-0}" -gt "${fp:-0}" ]; then
            pass=$((pass+1)); echo "  ok    floor follows the ref -> ${addc:0:9}: ${na} ogg · its parent: ${np} ogg"
        else
            fail=$((fail+1)); echo "  FAIL  floor follows the ref -> ${addc:0:9}: n=${na:-?} vs parent n=${np:-?} (must be more)" >&2
        fi
        read -r fh nh <<<"$(lfs_audio_floor)"; read -r fe ne <<<"$(lfs_audio_floor HEAD)"
        if [ "$fh $nh" = "$fe $ne" ]; then
            pass=$((pass+1)); echo "  ok    no argument still means HEAD -> ${nh} ogg"
        else
            fail=$((fail+1)); echo "  FAIL  no argument vs HEAD disagree -> '${fh} ${nh}' vs '${fe} ${ne}'" >&2
        fi
    else
        fail=$((fail+1)); echo "  FAIL  no commit that added an .ogg -- cannot derive a ref pair" >&2
    fi

    # --file: the CI gate, both directions, on real files sized either side of this tree's floor.
    # Sparse, so the arm costs no disk. Run through the SHIPPED dispatch ("$0"), not classify alone.
    local ff fd rcf; read -r ff _ <<<"$(lfs_audio_floor)"
    fd="$(mktemp -d "$HOME/.cache/vra_file.XXXXXX")"
    truncate -s $(( ff - 1 )) "$fd/short.x86_64"; truncate -s $(( ff + 1 )) "$fd/full.x86_64"
    "$0" --file "$fd/short.x86_64" >/dev/null 2>&1; rcf=$?
    chk "--file: one byte under this tree's floor is SHORT" "$rcf" "5"
    "$0" --file "$fd/full.x86_64" >/dev/null 2>&1; rcf=$?
    chk "--file: one byte over it passes" "$rcf" "0"
    "$0" --file "$fd/absent.x86_64" >/dev/null 2>&1; rcf=$?
    chk "--file: a missing binary BLOCKS, not passes" "$rcf" "2"
    rm -rf -- "$fd"

    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw_ok$saw_short" != "11" ]; then
        echo "selftest: BROKEN — outcomes seen: pass=${saw_ok} short=${saw_short}; both required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    --file)
        # CI's gate, run on the binary BEFORE it is attached to a release. Same floor and same
        # classify as the tag mode, so the rule exists once. Floor at HEAD: in CI the checkout IS
        # the tag being built, which is exactly the tree whose audio the binary must carry.
        f="${2:-}"
        [ -f "$f" ] || { echo "[release] BLOCKED: --file needs an existing binary, got '${f}'" >&2; exit 2; }
        read -r FLOOR NOGG <<<"$(lfs_audio_floor)"
        if [ "${NOGG:-0}" -lt 1 ] || [ "${FLOOR:-0}" -lt 1 ]; then
            echo "[release] BLOCKED: no LFS .ogg corpus in this tree -- a floor of zero clears everything." >&2
            exit 4
        fi
        echo "[release] $(basename "$f") — floor ${FLOOR} B from ${NOGG} LFS .ogg object(s) at HEAD"
        printf '%s %s\n' "$(basename "$f")" "$(wc -c < "$f")" | classify "$FLOOR"
        exit $? ;;
    "") echo "usage: $0 <tag> | --selftest" >&2; exit 2 ;;
esac

TAG="$1"
command -v gh >/dev/null || { echo "[release] BLOCKED: gh is not installed" >&2; exit 3; }

# The tag must be IN this clone. Falling back to HEAD when it is absent would silently restore
# the defect above for exactly the tags most likely to be missing -- old ones.
REF="$(git rev-parse --verify -q "${TAG}^{commit}" 2>/dev/null)"
if [ -z "$REF" ]; then
    echo "[release] BLOCKED: ${TAG} is not a commit in this clone (fetch tags?). The audio floor" >&2
    echo "          must be read from the tag's own tree; refusing to substitute HEAD's." >&2
    exit 4
fi
read -r FLOOR NOGG <<<"$(lfs_audio_floor "$REF")"
if [ "${NOGG:-0}" -lt 1 ] || [ "${FLOOR:-0}" -lt 1 ]; then
    echo "[release] BLOCKED: no LFS .ogg corpus found in this tree, so there is no floor to" >&2
    echo "          check against. Refusing to report a release as fine on an empty corpus." >&2
    exit 4
fi

ASSETS="$(gh release view "$TAG" --repo "$REPO" --json assets \
            --jq '.assets[] | "\(.name) \(.size)"' 2>/dev/null)"
if [ -z "$ASSETS" ]; then
    echo "[release] BLOCKED: no release assets for ${TAG} on ${REPO} (absent release, or gh" >&2
    echo "          cannot see it). That is not the same as a release that is fine." >&2
    exit 4
fi

echo "[release] ${TAG} on ${REPO} — floor ${FLOOR} B from ${NOGG} LFS .ogg object(s) in ${TAG}'s own tree"
printf '%s\n' "$ASSETS" | classify "$FLOOR"
RC=$?
if [ "$RC" = 5 ]; then
    echo "[release] SHORT: this release ships a build smaller than the audio it should contain." >&2
    echo "          The workflow checks out without \`lfs: true\`, so the .ogg files arrive as" >&2
    echo "          pointer text and the export packs a game that boots and cannot load music." >&2
    echo "          A passing result is a FLOOR, not a certificate." >&2
fi
exit $RC
