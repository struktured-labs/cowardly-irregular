#!/usr/bin/env bash
# Notice new or changed artist files on Google Drive and SAY SO. Nothing else.
#
# DETECT-ONLY, deliberately (struktured, 2026-09-23). The previous version pulled, ran
# embed_artist_idle_attack.py and committed+pushed on its own. That embed script was
# superseded by the tag-driven ingest, its cron line was commented out on 2026-06-14,
# and drops then sat unnoticed until struktured asked (bard ~21h, rogue longer). Ingest
# needs a person: tag names differ per file, ranges shift between drops, and artist
# pixels get exactly one permitted transform. So this only notices, notifies and logs.
# Ingest with the artist-drop-sync skill.
#
# Cron runs the INSTALLED copy:   15 * * * * $HOME/.local/bin/cowir-artist-drop-watch
# This repo file is the source. After editing it:   <this file> --install
#
# Usage:
#   check_for_new_artist_sprites.sh                one poll (what cron runs)
#   check_for_new_artist_sprites.sh --selftest     offline; no network, no notification
#   check_for_new_artist_sprites.sh --test-notify  send ONE visible desktop notification
#   check_for_new_artist_sprites.sh --install      copy to ~/.local/bin (crontab untouched)
# COWIR_DROP_WATCH_NOTIFY=0 logs "would notify" instead of notifying (testing while live).
set -uo pipefail

# cron gives a minimal PATH and no desktop session; notify-send needs the session bus.
export PATH="/usr/bin:/bin:${PATH:-}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

# ⛔ The Drive root folder is named " cowir" -- LEADING SPACE. "gdrive:cowir" is
# "directory not found", and a checker with that path found nothing for months.
REMOTE="${COWIR_DROP_WATCH_REMOTE:-gdrive: cowir}"
STATE="${COWIR_DROP_WATCH_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/cowir-artist-drop-watch}"
SNAP="$STATE/snapshot.tsv"
LOG="$STATE/watch.log"
# A listing this short is a broken listing, never a real Drive. Accepting it as the
# baseline would make every real file look NEW on the next run -- or, worse, silence.
MIN_FILES=10

mkdir -p "$STATE"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

notify() {  # title body -> 0 if the notification was delivered (or deliberately suppressed)
    if [ "${COWIR_DROP_WATCH_NOTIFY:-1}" = "0" ]; then
        log "would notify: $1 | ${2//$'\n'/ | }"
        return 0
    fi
    notify-send --app-name="Cowir drop watch" --icon=folder-download "$1" "$2" 2>>"$LOG"
}

fail() {  # say it is broken -- at most once a day, so a dead token is loud but not hourly
    log "FAIL: $*"
    local stamp="$STATE/last_fail_notice" now last
    now=$(date +%s)
    last=$(cat "$stamp" 2>/dev/null || echo 0)
    if [ $((now - last)) -ge 86400 ]; then
        notify "Artist drop watch is NOT working" "$*
Retrying hourly. Log: $LOG" && echo "$now" > "$stamp"
    fi
}

# rclone lsl line: "<size> <date> <time> <path>". The path can hold spaces, so capture it
# with one regex instead of splitting fields (awk field-rebuild collapses double spaces).
parse_lsl() { sed -E 's/^ *([0-9]+) ([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]+) (.*)$/\3\t\1\t\2/'; }

# old new -> "NEW|UPDATED|REMOVED<TAB>path<TAB>size<TAB>mtime", compared by PATH.
diff_snapshots() {
    awk -F'\t' '
        NR == FNR { old[$1] = $2 "\t" $3; next }
        { seen[$1] = 1
          if (!($1 in old))              print "NEW\t" $0
          else if (old[$1] != $2 "\t" $3) print "UPDATED\t" $0 }
        END { for (p in old) if (!(p in seen)) print "REMOVED\t" p "\t\t" }
    ' "$1" "$2" | LC_ALL=C sort
}

summarize() {  # changes on stdin -> notification body
    awk -F'\t' '{
        # name the JOB folder: our uploads live one level down, in <JOB>/claude/
        n = split($2, a, "/"); name = (n > 1 ? a[n-1] "/" a[n] : $2)
        if (n > 2 && a[n-1] == "claude") name = a[n-2] "/claude/" a[n]
        ours = ($2 ~ /\/claude\//) ? "  (ours, not the artist)" : ""
        printf "%s  %s%s\n", $1, name, ours
    }' | head -8
}

poll() {
    exec 9>"$STATE/lock"
    if ! flock -n 9; then log "previous poll still running -- skipped"; return 0; fi

    local raw="$STATE/raw.lsl" new="$STATE/snapshot.new" rc n changes total
    timeout -k 30 600 rclone lsl "$REMOTE" > "$raw" 2>>"$LOG"; rc=$?
    if [ "$rc" -ne 0 ]; then fail "rclone lsl \"$REMOTE\" exited $rc"; return 1; fi
    parse_lsl < "$raw" | LC_ALL=C sort > "$new"
    n=$(wc -l < "$new")
    if [ "$n" -lt "$MIN_FILES" ]; then
        fail "listing returned $n files (< $MIN_FILES) -- refusing to treat that as the Drive"
        return 1
    fi
    rm -f "$STATE/last_fail_notice"

    if [ ! -s "$SNAP" ]; then
        mv "$new" "$SNAP"; log "baseline recorded: $n files"; return 0
    fi
    changes=$(diff_snapshots "$SNAP" "$new")
    if [ -z "$changes" ]; then
        rm -f "$new"; log "no changes ($n files)"; return 0
    fi
    total=$(printf '%s\n' "$changes" | wc -l)
    log "CHANGES ($total):"; printf '%s\n' "$changes" >> "$LOG"
    # Advance the snapshot only once the news was delivered, so a failed notification
    # is retried next hour instead of being lost.
    if notify "Artist drop: $total file(s) changed on Drive" "$(printf '%s\n' "$changes" | summarize)
Ingest with the artist-drop-sync skill."; then
        mv "$new" "$SNAP"
    else
        log "notify-send failed -- snapshot NOT advanced; will retry"
        return 1
    fi
}

selftest() {  # fixtures only: no rclone, no notify-send, nothing outside a scratch dir
    local d bad=0
    d=$(mktemp -d -p "$STATE" selftest.XXXXXX) || return 1
    check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; printf '     want: %q\n     got:  %q\n' "$3" "$2"; bad=$((bad+1)); fi; }

    check "parse keeps a path with spaces and a DOUBLE space intact" \
        "$(printf '   151198 2026-09-18 20:28:10.602000000 a/Game graphics  - X/Bard Base.aseprite\n' | parse_lsl)" \
        "$(printf 'a/Game graphics  - X/Bard Base.aseprite\t151198\t2026-09-18 20:28:10.602000000')"

    printf 'A/keep.ase\t1\t2026-01-01 00:00:00\nA/touched.ase\t5\t2026-01-01 00:00:00\nA/gone.ase\t3\t2026-01-01 00:00:00\n' > "$d/old"
    printf 'A/keep.ase\t1\t2026-01-01 00:00:00\nA/touched.ase\t5\t2026-09-23 10:00:00\nMAGE/Mage Main design.aseprite\t9\t2026-09-24 09:00:00\n' > "$d/new"
    check "diff finds NEW, UPDATED (same size, new mtime) and REMOVED, and nothing else" \
        "$(diff_snapshots "$d/old" "$d/new" | cut -f1,2)" \
        "$(printf 'NEW\tMAGE/Mage Main design.aseprite\nREMOVED\tA/gone.ase\nUPDATED\tA/touched.ase')"
    check "identical snapshots produce NO changes" "$(diff_snapshots "$d/old" "$d/old")" ""
    # CONTROL: the diff must be able to come back non-empty, or the empty result above
    # would be the same output as a diff that never looks. The case above proves that.
    check "summary names the folder and file, and flags our own claude/ uploads" \
        "$(printf 'NEW\tx/MAGE/claude/m.aseprite\t1\td\n' | summarize)" \
        "NEW  MAGE/claude/m.aseprite  (ours, not the artist)"
    rm -rf "$d"
    echo; [ "$bad" -eq 0 ] && echo "selftest: all passed" || echo "selftest: $bad FAILED"
    return "$bad"
}

case "${1:-}" in
    --selftest)    selftest ;;
    --test-notify) notify "Artist drop watch: test" "If you can read this, cron notifications work." ;;
    --install)     install -D -m 755 "$0" "$HOME/.local/bin/cowir-artist-drop-watch" \
                       && echo "installed -> $HOME/.local/bin/cowir-artist-drop-watch" ;;
    "")            poll ;;
    *)             echo "unknown option: $1" >&2; exit 2 ;;
esac
