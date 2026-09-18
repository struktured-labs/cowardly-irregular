#!/usr/bin/env bash
# Say that the store is SPLIT, when a publish dies after some channels are already live.
#
# WHY THIS EXISTS
# ---------------
# publish_all.sh runs `deploy_<ch>.sh --publish` per channel, and that one invocation both
# GATES and UPLOADS. So channel N's refusal happens after channel N-1's butler push, which is
# irreversible. Measured 2026-09-18: v3.33.422-alpha went live on linux and windows, then RED
# on web, and the store served .422 to desktop players and .421 to web players until the next
# publish fixed it.
#
# The mid-batch state IS reasoned about in that loop — for the OTHER cause. The supersession
# branch says "Published so far: … Not swapping mid-batch." The RED branch says only
# "Published so far: linux windows", which is an EVENT ("this run got that far") where the
# operator needs a STATE ("the store is inconsistent right now"). Those read the same and are
# not the same, and the difference is what you do next.
#
# ⛔ THIS IS AN INTERIM AND I WANT THAT ON RECORD RATHER THAN IMPLIED. The real repair is
# ordering: gate all three channels, THEN upload all three, so a refusal cannot follow a push.
# deploy_*.sh already has the halves — without --publish it runs every gate and stops at gate 4
# — but hoisting it costs a second full pass or a phase split in the publish path, which is not
# a change to make in the same hour as the incident that motivated it. Until then the stranded
# state is at least legible instead of silent.
#
# Usage:  tools/report_split_store.sh <tag> "<channels already published>"
#         tools/report_split_store.sh --selftest
# Exit:   0 always on the reporting path — it REPORTS, it does not gate. The caller is already
#         exiting non-zero for its own reason and must not have that verdict overwritten.
set -uo pipefail

_report() {
    local tag="$1" published="$2"
    # Whitespace-only must read as "nothing went live", not as a split with no channels named.
    # An empty corpus printing a SPLIT warning would be this lane's own vacuity bug.
    local trimmed; trimmed="$(printf '%s' "$published" | tr -d '[:space:]')"
    if [ -z "$trimmed" ]; then
        echo "[split] nothing was published before the stop — the store is unchanged."
        return 0
    fi
    echo "[split] ⚠ THE STORE IS NOW INCONSISTENT, and that is a state, not an event."
    echo "[split]   live at ${tag}: ${published}"
    echo "[split]   every other channel is still serving the PREVIOUS release, and will keep"
    echo "[split]   serving it until a publish succeeds — players on those channels are behind."
    echo "[split]   Confirm with: tools/store_status.sh   (asks butler, not this log)"
    return 0
}

case "${1:-}" in
    --selftest) exec "$(dirname "$0")/report_split_store_selftest.sh" ;;
    -h|--help|'') echo "usage: $0 <tag> \"<published channels>\"  |  $0 --selftest" >&2; exit 2 ;;
    *)
        [ "$#" -ge 2 ] || { echo "usage: $0 <tag> \"<published channels>\"" >&2; exit 2; }
        _report "$1" "$2"
        ;;
esac
