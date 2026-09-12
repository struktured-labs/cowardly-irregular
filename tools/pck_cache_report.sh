#!/usr/bin/env bash
# Report a web pck's size against the three thresholds that matter, in labelled units.
#
# WHY THIS EXISTS
# ---------------
# deploy_web.sh reported `$((PCK / 1048576)) MB` -- a MiB division wearing an MB label. Both
# readings are plausible and neither is flagged, so I got the same number wrong TWICE in one
# day and handed @cowir-main 13.4 MiB of headroom where there was 4.8. A figure whose unit is
# ambiguous is worse than no figure.
#
# ⛔ AND THE THRESHOLD THE OLD REPORT COULD NOT SEE. The chain warns at PCK_WARN (171.7 MiB)
# and blocks at PCK_LIMIT (189.8 MiB). Measured 2026-09-11/12, headless chromium, per file on
# reload:
#
#     167,772,160 B  (160.0 MiB)   served FROM CACHE   at default AND 2 GB disk cache
#     170,917,888 B  (163.0 MiB)   re-fetched
#     175,000,656 B  (166.9 MiB)   re-fetched   <- synthetic file at EXACTLY the pck's size
#
# Controls: a synthetic random file at the pck's exact byte count behaves identically, so it is
# SIZE and not the pck or Godot's XHR loader; and index.wasm (43.7 MiB) IS cached in the same
# run, which is what proves the instrument can see a cache hit at all.
#
# So BOTH shipped thresholds sit ABOVE the only line a returning player feels, and a build can
# cross it in silence. This does not block -- removing content is struktured's call -- it
# reports. Chromium-family measured; Firefox/Safari not measured.
#
# ⛔ THE LINE THIS TOOL GOT WRONG, AND WHY IT COULD NOT HAVE GOT IT RIGHT. Until v3.33.334-alpha
# this report ended every over-the-line run with "a returning web player re-downloads N MiB
# EVERY visit." That became FALSE the moment the web build shipped as a PWA -- and it printed
# the false line IN THE CHAIN THAT PUBLISHED THE FIX, into the archived evidence for .334.
#
# The cause is not a stale string. THE TOOL'S ONLY INPUT WAS A BYTE COUNT, and no byte count can
# answer "does a service worker cache this". An instrument whose input cannot contain the fact
# that decides its conclusion will state that conclusion confidently and be wrong on a schedule
# nobody controls. So the fix is the SIGNATURE, not the wording: it is now given the build
# directory and looks.
#
# Four states, deliberately not three, because "I was not told" must never render as "not
# cached" -- that is the direction that re-creates the original defect:
#
#     covers             a worker ships AND names index.pck        -> cached after the warm-up
#     present-uncovered  a worker ships and does NOT name the pck  -> NOT cached, and a REGRESSION
#     none               no worker in the build                    -> NOT cached
#     unknown            no build directory given                  -> SAY NOTHING about visits
#
# Usage:  tools/pck_cache_report.sh <bytes> [cache_line] [warn] [limit] [build_dir]
#         tools/pck_cache_report.sh --selftest
set -uo pipefail

_mib() { awk -v b="$1" 'BEGIN{printf "%.2f", b/1048576}'; }
_mb()  { awk -v b="$1" 'BEGIN{printf "%.1f", b/1000000}'; }

# Does a service worker in this build actually name index.pck? Godot puts it in CACHEABLE_FILES
# (opt-cache, fetched then stored) rather than CACHED_FILES, so BOTH lists are read -- keying on
# the list Godot happens to use today would go quietly wrong if it moved the entry.
_sw_state() {
    local dir="${1:-}"
    [ -n "$dir" ] && [ -d "$dir" ] || { printf 'unknown'; return; }
    local sw="$dir/index.service.worker.js"
    [ -f "$sw" ] || { printf 'none'; return; }
    if command grep -aoE '(CACHED_FILES|CACHEABLE_FILES) = \[[^]]*\]' "$sw" \
         | command grep -qaF 'index.pck'; then printf 'covers'; else printf 'present-uncovered'; fi
}

_report() {
    local pck="$1" line="$2" warn="$3" limit="$4" build="${5:-}"
    # Units are spelled out on every figure: MiB (1048576) and MB (1000000) differ by 4.9% at
    # this scale, which is larger than the entire headroom to PCK_WARN.
    echo "[deploy] index.pck: $(_mib "$pck") MiB ($(_mb "$pck") MB decimal, ${pck} bytes)"
    if [ "$pck" -gt "$line" ]; then
        # The first line is the SIZE FACT and is identical in every state; only the line below
        # it -- the claim about what a player experiences -- depends on the worker.
        echo "[deploy] CACHE: OVER the browser cache line by $(_mib $(( pck - line ))) MiB."
        echo "[deploy]        cacheable at or below $(_mib "$line") MiB (${line} B), measured on chromium."
        case "$(_sw_state "$build")" in
          covers)
            echo "[deploy]        service worker caches it: a returning player pays $(_mib "$pck") MiB on the"
            echo "[deploy]        first two visits of each release, then nothing until the next release."
            echo "[deploy]        A FIRST-TIME player still downloads $(_mib "$pck") MiB, and itch-iframe"
            echo "[deploy]        registration is UNVERIFIED — over the line is still over the line." ;;
          present-uncovered)
            echo "[deploy]        ⛔ a service worker ships but does NOT name index.pck — it did at"
            echo "[deploy]        v3.33.334-alpha. A returning player re-downloads $(_mib "$pck") MiB EVERY visit." ;;
          none)
            echo "[deploy]        no service worker in this build — a returning web player re-downloads"
            echo "[deploy]        $(_mib "$pck") MiB EVERY visit." ;;
          *)
            echo "[deploy]        per-visit cost UNKNOWN: no build directory was given, so this report"
            echo "[deploy]        did not look for a service worker. It is not claiming either way." ;;
        esac
    else
        echo "[deploy] CACHE: under the browser cache line with $(_mib $(( line - pck ))) MiB spare — returning players load from cache."
    fi
    if [ "$pck" -ge "$limit" ]; then
        echo "[deploy]        itch: AT OR OVER the $(_mib "$limit") MiB embed limit."
    elif [ "$pck" -ge "$warn" ]; then
        echo "[deploy]        itch: within $(_mib $(( limit - pck ))) MiB of the $(_mib "$limit") MiB embed limit."
    fi
}

case "${1:-}" in
    --selftest) ;;
    "" ) echo "usage: $0 <bytes> [cache_line] [warn] [limit] [build_dir] | --selftest" >&2; exit 2 ;;
    -*)  echo "usage: $0 <bytes> [cache_line] [warn] [limit] [build_dir] | --selftest" >&2; exit 2 ;;
    *)   case "$1" in *[!0-9]*) echo "$0: <bytes> must be a plain byte count, got '$1'" >&2; exit 2 ;; esac
         _report "$1" "${2:-167772160}" "${3:-180000000}" "${4:-199000000}" "${5:-}"; exit 0 ;;
esac

# ── selftest ─────────────────────────────────────────────────────────────────────────────
pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-52s %s\n' "$1" "$2";
        else fail=$((fail+1)); printf '  FAIL  %-52s got %s want %s\n' "$1" "$2" "$3"; fi; }
said() { printf '%s' "$1" | command grep -qF "$2" && echo yes || echo no; }

LINE=167772160
# 1/2 — the verdict must SWITCH at the line. A report that always said OVER would pass arm 1
#       alone, and one that always said under would pass arm 2 alone.
over=$(_report $(( LINE + 1 ))  "$LINE" 180000000 199000000)
under=$(_report $(( LINE - 1 )) "$LINE" 180000000 199000000)
chk "1 byte OVER the line says OVER"            "$(said "$over"  'CACHE: OVER')"  yes
chk "1 byte OVER does not also say under"       "$(said "$over"  'CACHE: under')" no
chk "1 byte UNDER the line says under"          "$(said "$under" 'CACHE: under')" yes
chk "1 byte UNDER does not also say OVER"       "$(said "$under" 'CACHE: OVER')"  no
# 3 — exactly ON the line is cacheable (the measured 167772160 DID cache), not over.
onit=$(_report "$LINE" "$LINE" 180000000 199000000)
chk "exactly ON the line is cacheable"          "$(said "$onit"  'CACHE: under')" yes

# 4 — the real shipped number, so the arm moves when the pack does.
real=$(_report 175014432 "$LINE" 180000000 199000000)
chk "v3.33.309-alpha's pck reports OVER"         "$(said "$real" 'CACHE: OVER')" yes
chk "…and names the 6.91 MiB overage"           "$(said "$real" 'by 6.91 MiB')" yes

# 5/6 — UNITS. The old line divided by MiB and printed "MB"; both must now appear, labelled.
chk "reports MiB explicitly"                    "$(said "$real" '166.91 MiB')" yes
chk "reports decimal MB explicitly"             "$(said "$real" '175.0 MB decimal')" yes
chk "reports raw bytes"                         "$(said "$real" '175014432 bytes')" yes

# 7/8 — itch thresholds still reported, and ONLY when applicable.
warnband=$(_report 185000000 "$LINE" 180000000 199000000)
chk "in the warn band names the itch limit"     "$(said "$warnband" 'of the 189.78 MiB embed limit')" yes
chk "below the warn band stays quiet on itch"   "$(said "$under" 'embed limit')" no
atlimit=$(_report 199000000 "$LINE" 180000000 199000000)
chk "at the itch limit says AT OR OVER"         "$(said "$atlimit" 'AT OR OVER')" yes

# 9 — a non-numeric argument is refused rather than silently treated as 0.
"$0" not-a-number >/dev/null 2>&1
chk "refuses a non-numeric byte count"          "$?" 2
"$0" 175014432 >/dev/null 2>&1
chk "accepts a plain byte count"                "$?" 0


# 10-17 — THE WORKER STATES. Fixtures are built here rather than pointed at a real build, so the
# arms keep working when no web build exists on disk. Each state must produce a DIFFERENT claim
# about the player, and the two that mean "not cached" must still say EVERY visit.
_fx="$(mktemp -d)"; trap 'rm -rf "$_fx"' EXIT
mkdir -p "$_fx/covers" "$_fx/uncovered" "$_fx/none"
printf 'const CACHED_FILES = ["index.html"];\nconst CACHEABLE_FILES = ["index.wasm","index.pck"];\n' > "$_fx/covers/index.service.worker.js"
printf 'const CACHED_FILES = ["index.html"];\nconst CACHEABLE_FILES = ["index.wasm"];\n'              > "$_fx/uncovered/index.service.worker.js"

chk "state: worker naming the pck   -> covers"      "$(_sw_state "$_fx/covers")"    covers
chk "state: worker without the pck  -> uncovered"   "$(_sw_state "$_fx/uncovered")" present-uncovered
chk "state: build dir, no worker    -> none"        "$(_sw_state "$_fx/none")"      none
chk "state: no build dir            -> unknown"     "$(_sw_state "")"               unknown
chk "state: nonexistent dir         -> unknown"     "$(_sw_state "$_fx/nope")"      unknown

OVER=$(( LINE + 7000000 ))
cov=$(_report  "$OVER" "$LINE" 180000000 199000000 "$_fx/covers")
unc=$(_report  "$OVER" "$LINE" 180000000 199000000 "$_fx/uncovered")
non=$(_report  "$OVER" "$LINE" 180000000 199000000 "$_fx/none")
unk=$(_report  "$OVER" "$LINE" 180000000 199000000)

# the defect this change exists to kill: the EVERY-visit claim must appear ONLY when earned.
chk "covers does NOT claim EVERY visit"          "$(said "$cov" 'EVERY visit')" no
chk "covers names the service worker"            "$(said "$cov" 'service worker caches it')" yes
chk "covers still warns first-time players pay"  "$(said "$cov" 'FIRST-TIME player still downloads')" yes
chk "covers does not overclaim on itch"          "$(said "$cov" 'UNVERIFIED')" yes
chk "uncovered DOES claim EVERY visit"           "$(said "$unc" 'EVERY visit')" yes
chk "uncovered names it as a regression"         "$(said "$unc" 'does NOT name index.pck')" yes
chk "none DOES claim EVERY visit"                "$(said "$non" 'EVERY visit')" yes
chk "unknown claims NEITHER way"                 "$(said "$unk" 'EVERY visit')" no
chk "unknown says so out loud"                   "$(said "$unk" 'UNKNOWN')" yes
chk "unknown does not claim the worker either"   "$(said "$unk" 'service worker caches it')" no

# 18 — the size fact is state-independent: every state reports the same overage line.
for _v in "$cov" "$unc" "$non" "$unk"; do
  chk "size fact identical across states"        "$(said "$_v" 'OVER the browser cache line by 6.68 MiB')" yes
done

# 19 — under the line, the worker is irrelevant and must not add noise.
u2=$(_report $(( LINE - 1 )) "$LINE" 180000000 199000000 "$_fx/covers")
chk "under the line stays the under message"     "$(said "$u2" 'CACHE: under')" yes
chk "under the line says nothing about workers"  "$(said "$u2" 'service worker')" no

echo; echo "selftest: ${pass} passed, ${fail} failed"; [ "$fail" -eq 0 ]
