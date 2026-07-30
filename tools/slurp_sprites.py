#!/usr/bin/env python3
"""
Slurp artist sprites from Google Drive into the local project.

Syncs from the artist's Google Drive archive (cowir/assets/sprites/)
into assets/sprites/jobs/aseprite/ for Aseprite source files.

Prerequisites:
    rclone configured with 'gdrive' remote (rclone config)

Usage:
    uv run python tools/slurp_sprites.py                    # sync all
    uv run python tools/slurp_sprites.py --dry-run          # preview what would sync
    uv run python tools/slurp_sprites.py --job cleric       # sync specific job only
    uv run python tools/slurp_sprites.py --list             # list available files on Drive
"""

import argparse
import subprocess
import sys
from pathlib import Path

# Google Drive folder ID for cowir root
DRIVE_ROOT_ID = "1eErL_jxgk8r6nrNiqCxfXbhbrtaNhjU7"
DRIVE_SPRITES = "assets/sprites/Game graphics - Characters"

# Local destinations
REPO_ROOT = Path(__file__).resolve().parent.parent
GAME_REPO = Path("/home/struktured/projects/cowardly-irregular")
LOCAL_ASEPRITE = GAME_REPO / "assets" / "sprites" / "jobs" / "aseprite"
LOCAL_SPRITEGEN = REPO_ROOT / "assets" / "sprites" / "jobs" / "aseprite"

# Job name mapping (Drive folder name → local job ID)
DRIVE_TO_JOB = {
    "FIGHTER": "fighter",
    "CLERIC": "cleric",
    "MAGE": "mage",
    "ROGUE": "rogue",
    "BARD": "bard",
    "GUARDIAN": "guardian",
    "NINJA": "ninja",
    "SUMMONER": "summoner",
    "SPECULATOR": "speculator",
}


def rclone_cmd(*args) -> subprocess.CompletedProcess:
    """Run rclone with the Drive root folder ID."""
    cmd = ["rclone", *args, "--drive-root-folder-id", DRIVE_ROOT_ID]
    return subprocess.run(cmd, capture_output=True, text=True)


def list_drive_files():
    """List all sprite files on Drive."""
    result = rclone_cmd("ls", f"gdrive:{DRIVE_SPRITES}/")
    if result.returncode != 0:
        print(f"Error listing Drive: {result.stderr.strip()}")
        return
    print("Files on Google Drive (cowir/assets/sprites/):")
    for line in result.stdout.strip().split("\n"):
        if line.strip():
            print(f"  {line.strip()}")


def sync_job(drive_folder: str, job_id: str, dry_run: bool = False):
    """Sync a specific job folder from Drive to local."""
    src = f"gdrive:{DRIVE_SPRITES}/{drive_folder}/"

    # Sync to both game repo and sprite-gen repo
    for dest_name, dest_dir in [("game repo", LOCAL_ASEPRITE), ("sprite-gen", LOCAL_SPRITEGEN)]:
        dest_dir.mkdir(parents=True, exist_ok=True)

        args = ["copy", src, str(dest_dir), "--progress"]
        if dry_run:
            args.append("--dry-run")

        print(f"\n{'[DRY RUN] ' if dry_run else ''}Syncing {drive_folder} → {dest_dir}")
        result = rclone_cmd(*args)

        if result.stdout.strip():
            print(result.stdout.strip())
        if result.stderr.strip():
            # rclone prints progress to stderr
            for line in result.stderr.strip().split("\n"):
                if "ERROR" in line:
                    print(f"  ERROR: {line}")
                elif "Transferred" in line or "Copied" in line:
                    print(f"  {line.strip()}")


def sync_all(dry_run: bool = False):
    """Sync all available job folders from Drive."""
    # List available folders (lsf --dirs-only gives clean names with trailing /)
    result = rclone_cmd("lsf", "--dirs-only", f"gdrive:{DRIVE_SPRITES}/")
    if result.returncode != 0:
        print(f"Error: {result.stderr.strip()}")
        return

    folders = []
    for line in result.stdout.strip().split("\n"):
        name = line.strip().rstrip("/")
        if name:
            folders.append(name)

    print(f"Found {len(folders)} folders on Drive: {folders}")

    for folder in folders:
        job_id = DRIVE_TO_JOB.get(folder.upper(), folder.lower())
        # Skip non-job folders (like "Nazuna sample sprites")
        if job_id not in DRIVE_TO_JOB.values() and folder.upper() not in DRIVE_TO_JOB:
            print(f"\nSkipping '{folder}' (not a known job)")
            continue
        sync_job(folder, job_id, dry_run)

    print(f"\n{'[DRY RUN] ' if dry_run else ''}Sync complete!")
    if not dry_run:
        print("Run export_aseprite_sprites.py to convert to game-ready PNGs.")


def main():
    parser = argparse.ArgumentParser(description="Slurp artist sprites from Google Drive")
    parser.add_argument("--dry-run", action="store_true", help="Preview without downloading")
    parser.add_argument("--list", action="store_true", help="List files on Drive")
    parser.add_argument("--job", help="Sync specific job only (e.g., cleric, fighter)")
    args = parser.parse_args()

    # Verify rclone is configured
    result = subprocess.run(["rclone", "listremotes"], capture_output=True, text=True)
    if "gdrive:" not in result.stdout:
        print("Error: rclone 'gdrive' remote not configured. Run: rclone config")
        sys.exit(1)

    if args.list:
        list_drive_files()
        return

    if args.job:
        # Find the Drive folder name for this job
        drive_folder = None
        for df, jid in DRIVE_TO_JOB.items():
            if jid == args.job.lower():
                drive_folder = df
                break
        if not drive_folder:
            drive_folder = args.job.upper()
        sync_job(drive_folder, args.job.lower(), args.dry_run)
    else:
        sync_all(args.dry_run)


if __name__ == "__main__":
    main()
