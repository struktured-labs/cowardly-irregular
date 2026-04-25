#!/usr/bin/env bash
#
# Hourly check for new/updated artist sprites on Google Drive.
# - Pulls latest from gdrive: cowir/assets/sprites/Game graphics - Characters
# - If any aseprite/png files changed, re-runs the embed and pushes to feature branch
# - Idempotent: no-op when nothing changed
#
# Run via cron:  0 * * * * /home/struktured/projects/cowardly-irregular-sprite-gen/tools/check_for_new_artist_sprites.sh

set -euo pipefail

REPO="/home/struktured/projects/cowardly-irregular-sprite-gen"
GAME_WORKTREE="/home/struktured/projects/cowardly-irregular-artist-ship"
DRIVE_LOCAL="$REPO/assets/sprites/drive_archive/Game graphics - Characters"
DRIVE_REMOTE="gdrive: cowir/assets/sprites/Game graphics - Characters"
LOG_DIR="$REPO/tmp/sprite_check_logs"
LOG_FILE="$LOG_DIR/check.log"
STAMP_FILE="$LOG_DIR/last_known.tsv"

mkdir -p "$LOG_DIR"

ts() { date +'%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" >> "$LOG_FILE"; }

cd "$REPO"

log "=== check start ==="

# Capture pre-state: name + size + mtime of every artist file
before_state() {
    find "$DRIVE_LOCAL" -type f \( -name '*.aseprite' -o -name '*.png' \) \
        -printf '%P\t%s\t%T@\n' 2>/dev/null | sort
}
PREV=$(before_state)

# Pull latest. Don't use --update because we want artist's version to win.
if ! rclone copy --max-age 7d "$DRIVE_REMOTE" "$DRIVE_LOCAL" 2>>"$LOG_FILE"; then
    log "rclone failed — aborting"
    exit 0  # don't fail loud, this is a poll
fi

POST=$(before_state)

if [[ "$PREV" == "$POST" ]]; then
    log "no changes"
    exit 0
fi

log "changes detected:"
diff <(echo "$PREV") <(echo "$POST") | grep -E '^[<>]' >> "$LOG_FILE" || true

# Run the embed script — writes into the feature-branch worktree
if ! GAME_REPO="$GAME_WORKTREE" /home/struktured/.local/bin/uv run --project "$REPO" \
        python "$REPO/tools/embed_artist_idle_attack.py" >>"$LOG_FILE" 2>&1; then
    log "embed script failed — aborting"
    exit 1
fi

# Commit + push if the worktree has changes
cd "$GAME_WORKTREE"
if git diff --quiet --exit-code; then
    log "embed produced no diff (artist edited a file the script doesn't consume)"
    exit 0
fi

git add -A assets/sprites/jobs/
COMMIT_MSG=$'sprites: auto-embed from artist drive update '"$(date +%Y-%m-%d)"$'\n\nDetected new/updated artist files; re-ran embed_artist_idle_attack.py.\nSee tmp/sprite_check_logs/check.log in sprite-gen for diff.\n\nCo-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>'
git commit -m "$COMMIT_MSG" >>"$LOG_FILE" 2>&1
git push 2>>"$LOG_FILE"
log "committed + pushed to feature/artist-idle-attack-ship"
# drive_archive itself is gitignored — local cache only, gdrive is canonical
log "=== check end ==="
