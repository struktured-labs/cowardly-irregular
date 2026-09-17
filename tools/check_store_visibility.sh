#!/usr/bin/env bash
# Is the itch project reachable WITHOUT the password? Answers from the page itch serves an
# anonymous visitor, not from memory and not from the dashboard.
#
# WHY THIS EXISTS
# ---------------
# docs/DEPLOYMENT_PLATFORMS.md asserted for months that two dead channels were "publicly
# visible" and that "anyone clicking those plays a build from many versions ago". Nobody had
# fetched the page. Measured 2026-09-16: the whole project is password-gated, so no channel is
# reachable anonymously, dead or live — the claim was false in the direction that invents a
# problem, and it sat beside a `web` version that was 168 releases stale.
#
# ⛔ THE FACT IS LIVE AND NOTHING ELSE WATCHES IT. If struktured unlocks the page, the corrected
# sentence ("nobody can reach them") becomes wrong in the OPPOSITE and worse direction — it
# would say the dead builds are unreachable while anyone could click them. A note cannot notice
# that. This can, and it is one command.
#
# ⚠️ DELIBERATELY NOT IN THE PUBLISH CHAIN. It needs the network, and a publish must not fail
# because itch is slow or this box is offline. Run it when the claim matters.
#
# Usage:  tools/check_store_visibility.sh [url]
#         tools/check_store_visibility.sh --from-file <html>    classify a saved page
#         tools/check_store_visibility.sh --selftest
# Exit:   0 GATED (password required) · 1 PUBLIC (reachable anonymously) · 2 UNKNOWN/refused
set -uo pipefail

URL_DEFAULT="https://struktured.itch.io/cowardly-irregular"

# Two independent markers, because ONE of them cannot tell a verdict from an empty response.
# `game_password_page` is itch's gate form. `game_cell|game_link|upload_id|html_embed` are the
# things a reachable page carries. Absence of both is NOT a verdict — it is a failed fetch
# wearing a verdict's clothes, and this refuses rather than picking the reassuring reading.
classify() {
    local body="$1"
    local gate links
    gate=$(printf '%s' "$body" | command grep -aoc 'game_password_page' || true)
    links=$(printf '%s' "$body" | command grep -aoc 'game_cell\|game_link\|upload_id\|html_embed' || true)
    gate=${gate:-0}; links=${links:-0}
    if [ "$gate" -gt 0 ]; then
        echo "GATED     password required — no channel is reachable anonymously (gate=${gate} links=${links})"
        return 0
    elif [ "$links" -gt 0 ]; then
        echo "PUBLIC    reachable anonymously — every channel including html5/html5-v2 can be clicked (gate=${gate} links=${links})"
        return 1
    fi
    echo "UNKNOWN   neither marker present (gate=0 links=0) — this is a failed fetch, not a verdict. Refusing to answer." >&2
    return 2
}

selftest() {
    local pass=0 fail=0
    _eq() {
        if [ "$2" = "$3" ]; then printf '  ok    %-56s %s\n' "$1" "$2"; pass=$((pass+1))
        else printf '  FAIL  %-56s got %s want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
    }
    mkdir -p "$HOME/.cache"
    local d; d="$(mktemp -d "$HOME/.cache/storevis.XXXXXX")"

    # the real shapes, reduced to the markers each one carries
    printf '%s' '<div id="game_password_4304125" class="game_password_page page_widget"><input name="game_password"></div>' > "$d/gated.html"
    printf '%s' '<div class="game_cell"><a class="game_link" href="/x"></a><div class="upload_id">1</div></div>'            > "$d/public.html"
    : > "$d/empty.html"
    printf '%s' '<html><body>itch.io is down for maintenance</body></html>'                                                 > "$d/neither.html"

    local out ec
    out="$(bash "$SELF" --from-file "$d/gated.html" 2>&1)"; ec=$?
    _eq "a gated page is GATED"                            "$ec" "0"
    case "$out" in *GATED*) _eq "  ...and says so"  yes yes ;; *) _eq "  ...and says so" no yes ;; esac

    out="$(bash "$SELF" --from-file "$d/public.html" 2>&1)"; ec=$?
    _eq "a reachable page is PUBLIC"                       "$ec" "1"
    case "$out" in *PUBLIC*) _eq "  ...and says so" yes yes ;; *) _eq "  ...and says so" no yes ;; esac

    # ⛔ THE ARM THAT MATTERS: an empty body must not read as either verdict. With one marker
    # it would — no password form looks exactly like "public" to a gate-only check.
    out="$(bash "$SELF" --from-file "$d/empty.html" 2>&1)"; ec=$?
    _eq "an EMPTY body is UNKNOWN, not a verdict"          "$ec" "2"
    case "$out" in *UNKNOWN*) _eq "  ...and refuses out loud" yes yes ;; *) _eq "  ...and refuses out loud" no yes ;; esac

    out="$(bash "$SELF" --from-file "$d/neither.html" 2>&1)"; ec=$?
    _eq "a page with neither marker is UNKNOWN"            "$ec" "2"

    out="$(bash "$SELF" --from-file "$d/does-not-exist" 2>&1)"; ec=$?
    _eq "an unreadable file is REFUSED"                    "$ec" "2"

    rm -rf "$d"
    printf '\nselftest: %s passed, %s failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

case "${1:-}" in
    --selftest)  selftest; exit $? ;;
    --from-file) [ -r "${2:-}" ] || { echo "UNKNOWN   cannot read ${2:-<no file>} — refusing to classify." >&2; exit 2; }
                 classify "$(cat "$2")"; exit $? ;;
    *)           _url="${1:-$URL_DEFAULT}"
                 _body="$(curl -s --max-time 20 -A 'Mozilla/5.0' "$_url" 2>/dev/null)"
                 [ -n "$_body" ] || { echo "UNKNOWN   empty response from ${_url} — refusing to classify." >&2; exit 2; }
                 printf '[store-vis] %s\n' "$_url"
                 printf '[store-vis] '; classify "$_body"; exit $? ;;
esac
