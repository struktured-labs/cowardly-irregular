#!/usr/bin/env bash
# Does the GitHub Release for a tag actually contain the game's audio?
#
#   tools/verify_release_artifact.sh <tag>
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
lfs_audio_floor() {
    git lfs ls-files -s 2>/dev/null | awk '
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

    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw_ok$saw_short" != "11" ]; then
        echo "selftest: BROKEN — outcomes seen: pass=${saw_ok} short=${saw_short}; both required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    "") echo "usage: $0 <tag> | --selftest" >&2; exit 2 ;;
esac

TAG="$1"
command -v gh >/dev/null || { echo "[release] BLOCKED: gh is not installed" >&2; exit 3; }

read -r FLOOR NOGG <<<"$(lfs_audio_floor)"
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

echo "[release] ${TAG} on ${REPO} — floor ${FLOOR} B from ${NOGG} LFS .ogg object(s)"
printf '%s\n' "$ASSETS" | classify "$FLOOR"
RC=$?
if [ "$RC" = 5 ]; then
    echo "[release] SHORT: this release ships a build smaller than the audio it should contain." >&2
    echo "          The workflow checks out without \`lfs: true\`, so the .ogg files arrive as" >&2
    echo "          pointer text and the export packs a game that boots and cannot load music." >&2
    echo "          A passing result is a FLOOR, not a certificate." >&2
fi
exit $RC
