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
# Usage:  tools/pck_cache_report.sh <bytes> [cache_line] [warn] [limit]
#         tools/pck_cache_report.sh --selftest
set -uo pipefail

_mib() { awk -v b="$1" 'BEGIN{printf "%.2f", b/1048576}'; }
_mb()  { awk -v b="$1" 'BEGIN{printf "%.1f", b/1000000}'; }

_report() {
    local pck="$1" line="$2" warn="$3" limit="$4"
    # Units are spelled out on every figure: MiB (1048576) and MB (1000000) differ by 4.9% at
    # this scale, which is larger than the entire headroom to PCK_WARN.
    echo "[deploy] index.pck: $(_mib "$pck") MiB ($(_mb "$pck") MB decimal, ${pck} bytes)"
    if [ "$pck" -gt "$line" ]; then
        echo "[deploy] CACHE: OVER the browser cache line by $(_mib $(( pck - line ))) MiB — a returning web player re-downloads $(_mib "$pck") MiB EVERY visit."
        echo "[deploy]        cacheable at or below $(_mib "$line") MiB (${line} B), measured on chromium."
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
    "" ) echo "usage: $0 <bytes> [cache_line] [warn] [limit] | --selftest" >&2; exit 2 ;;
    -*)  echo "usage: $0 <bytes> [cache_line] [warn] [limit] | --selftest" >&2; exit 2 ;;
    *)   case "$1" in *[!0-9]*) echo "$0: <bytes> must be a plain byte count, got '$1'" >&2; exit 2 ;; esac
         _report "$1" "${2:-167772160}" "${3:-180000000}" "${4:-199000000}"; exit 0 ;;
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

echo; echo "selftest: ${pass} passed, ${fail} failed"; [ "$fail" -eq 0 ]
