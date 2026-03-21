# /// script
# requires-python = ">=3.10"
# dependencies = ["requests", "SunoAI"]
# ///
"""
suno_gen.py — Generate music tracks for Cowardly Irregular via Suno API providers.

Supports multiple API providers that wrap the same Suno V5 model:
  - aimlapi   : aimlapi.com  (env: AIMLAPI_KEY)
  - sunoapi_org: sunoapi.org (env: SUNO_API_KEY)

Usage:
    uv run tools/suno_gen.py --provider aimlapi --track-id overworld_medieval \\
        --title "The Usurper's Crown" \\
        --style "16-bit SNES orchestral, Nobuo Uematsu, harp, strings" \\
        --prompt "Peaceful medieval village morning, golden light through mist..." \\
        --instrumental --preview

    uv run tools/suno_gen.py --provider aimlapi --world 1 --track-id overworld_medieval --preview

Requires:
    - API key env var for chosen provider (set in setenv.sh)
    - ffmpeg on PATH (for MP3 -> OGG conversion)
    - mpv on PATH (for --preview playback)
"""

from __future__ import annotations

import abc
import argparse
import json
import os
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

import requests

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

POLL_INTERVAL_SEC = 10
MAX_POLL_SEC = 300  # 5 minutes

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "assets" / "audio" / "music"
MANIFEST_PATH = PROJECT_ROOT / "data" / "music_manifest.json"
PROMPTS_PATH = PROJECT_ROOT / "tools" / "music_prompts.json"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def load_manifest() -> dict:
    if MANIFEST_PATH.exists():
        with MANIFEST_PATH.open() as fh:
            return json.load(fh)
    return {"_comment": "Music manifest for Cowardly Irregular", "tracks": {}}


def save_manifest(manifest: dict) -> None:
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    with MANIFEST_PATH.open("w") as fh:
        json.dump(manifest, fh, indent=2)
    print(f"Manifest updated: {MANIFEST_PATH}")


def update_manifest_atomic(track_key: str, entry: dict) -> None:
    """Thread/process-safe manifest update using file locking.

    Prevents race conditions when multiple suno_gen.py processes run in parallel.
    """
    import fcntl
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    lock_path = MANIFEST_PATH.with_suffix(".lock")
    with lock_path.open("w") as lock_fh:
        fcntl.flock(lock_fh, fcntl.LOCK_EX)
        try:
            manifest = load_manifest()
            if "tracks" not in manifest:
                manifest["tracks"] = {}
            manifest["tracks"][track_key] = entry
            save_manifest(manifest)
        finally:
            fcntl.flock(lock_fh, fcntl.LOCK_UN)


def load_world_template(world: int, track_id: str) -> dict:
    """Load a world template and resolve the specific track within it.

    *track_id* is e.g. ``overworld_medieval``; we strip the world suffix to
    derive the track type (``overworld``), then also try ``shared_tracks``
    for world-agnostic entries like ``victory`` / ``title`` / ``game_over``.
    """
    if not PROMPTS_PATH.exists():
        die(
            f"music_prompts.json not found at {PROMPTS_PATH}.\n"
            "Create it with world templates before using --world."
        )
    with PROMPTS_PATH.open() as fh:
        prompts = json.load(fh)
    worlds = prompts.get("worlds", {})
    key = str(world)
    if key not in worlds:
        available = ", ".join(worlds.keys()) if worlds else "(none)"
        die(f"World {world} not found in music_prompts.json. Available: {available}")

    world_data = worlds[key]
    tracks = world_data.get("tracks", {})
    shared = prompts.get("shared_tracks", {})

    # Derive track type from track_id: strip common world suffixes
    track_type = track_id
    for suffix in ("_medieval", "_suburban", "_steampunk", "_industrial",
                   "_digital", "_abstract", "_cave", "_generic"):
        if track_type.endswith(suffix):
            track_type = track_type[: -len(suffix)]
            break

    # Look up: world-specific tracks first, then shared
    if track_type in tracks:
        entry = tracks[track_type]
    elif track_id in shared:
        entry = shared[track_id]
    elif track_type in shared:
        entry = shared[track_type]
    else:
        available_tracks = list(tracks.keys()) + list(shared.keys())
        die(
            f"Track type '{track_type}' (from --track-id '{track_id}') "
            f"not found in world {world} templates.\n"
            f"Available: {', '.join(available_tracks)}"
        )

    # Normalise key name: templates use "title_template", flatten to "title"
    result = dict(entry)
    if "title_template" in result and "title" not in result:
        result["title"] = result.pop("title_template")
    return result


# ---------------------------------------------------------------------------
# Provider abstraction
# ---------------------------------------------------------------------------

class Provider(abc.ABC):
    """Base class for music generation API providers."""

    name: str
    env_var: str
    # audio_format: what the provider returns (wav, mp3, etc.)
    audio_format: str = "mp3"

    def get_api_key(self) -> str:
        key = os.environ.get(self.env_var, "").strip()
        if not key:
            setenv = PROJECT_ROOT / "setenv.sh"
            hint = f"\n  Or:  source {setenv}" if setenv.exists() else ""
            die(
                f"{self.env_var} environment variable is not set.\n"
                f"  Run: export {self.env_var}=your_key_here{hint}"
            )
        return key

    @abc.abstractmethod
    def generate(self, api_key: str, title: str, style: str,
                 prompt: str, instrumental: bool) -> str:
        """Submit generation request, return a task/generation identifier."""

    @abc.abstractmethod
    def poll(self, api_key: str, task_id: str) -> list[dict]:
        """Poll until done. Return list of dicts with keys: audio_url, title, duration."""


# ---------------------------------------------------------------------------
# AIMLAPI provider  (aimlapi.com — stable-audio model)
# ---------------------------------------------------------------------------

class AimlApiProvider(Provider):
    """Uses AIMLAPI's /v2/generate/audio endpoint with stable-audio model.

    Suno was deprecated on AIMLAPI; stable-audio (Stability AI) is the
    recommended replacement.  Returns WAV, ~30s clips, text-to-music.
    """
    name = "aimlapi"
    env_var = "AIMLAPI_KEY"
    audio_format = "wav"

    ENDPOINT = "https://api.aimlapi.com/v2/generate/audio"
    MODEL = "stable-audio"

    def _headers(self, api_key: str) -> dict:
        return {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

    def generate(self, api_key: str, title: str, style: str,
                 prompt: str, instrumental: bool) -> str:
        # Combine style + prompt into a single description for stable-audio
        full_prompt = f"{style}. {prompt}"
        if instrumental:
            full_prompt += ". Instrumental, no vocals."
        body = {
            "model": self.MODEL,
            "prompt": full_prompt,
        }
        print(f"[aimlapi/{self.MODEL}] Submitting generation: {title!r}")
        print(f"  Style : {style}")
        print(f"  Prompt: {prompt[:120]}{'...' if len(prompt) > 120 else ''}")

        resp = requests.post(self.ENDPOINT, headers=self._headers(api_key),
                             json=body, timeout=30)
        if resp.status_code != 200:
            die(f"[aimlapi] Generate returned HTTP {resp.status_code}.\n"
                f"  Body: {resp.text[:400]}")
        data = resp.json()
        gen_id = data.get("id")
        if not gen_id:
            die(f"[aimlapi] No id in response:\n  {json.dumps(data, indent=2)[:600]}")
        status = data.get("status", "?")
        print(f"[aimlapi] Generation ID: {gen_id} (status: {status})")
        return gen_id

    def poll(self, api_key: str, task_id: str) -> list[dict]:
        deadline = time.monotonic() + MAX_POLL_SEC
        attempt = 0

        while time.monotonic() < deadline:
            attempt += 1
            time.sleep(POLL_INTERVAL_SEC)
            elapsed = int(POLL_INTERVAL_SEC * attempt)
            print(f"  Polling ({elapsed}s elapsed)...")

            resp = requests.get(self.ENDPOINT,
                                headers=self._headers(api_key),
                                params={"generation_id": task_id},
                                timeout=30)
            if resp.status_code != 200:
                print(f"  Poll HTTP {resp.status_code} — retrying...")
                continue

            data = resp.json()
            status = (data.get("status") or "").lower()

            if status == "completed":
                audio_file = data.get("audio_file", {})
                audio_url = audio_file.get("url", "")
                if not audio_url:
                    die(f"[aimlapi] Completed but no audio_file.url:\n"
                        f"  {json.dumps(data, indent=2)[:600]}")
                print(f"  Completed.")
                return [{
                    "audio_url": audio_url,
                    "title": "",
                    "duration": 0.0,  # will be probed via ffprobe
                }]

            if status in ("error", "failed"):
                die(f"[aimlapi] Generation failed.\n"
                    f"  Response: {json.dumps(data, indent=2)[:600]}")

            print(f"  Status: {status}")

        die(f"[aimlapi] Timed out after {MAX_POLL_SEC}s for generation {task_id}.")
        return []  # unreachable


# ---------------------------------------------------------------------------
# sunoapi.org provider (original)
# ---------------------------------------------------------------------------

class SunoApiOrgProvider(Provider):
    name = "sunoapi_org"
    env_var = "SUNO_API_KEY"

    BASE = "https://api.sunoapi.org/api/v1"
    GENERATE_URL = f"{BASE}/generate"
    RECORD_URL = f"{BASE}/record-info"

    def _headers(self, api_key: str) -> dict:
        return {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

    def generate(self, api_key: str, title: str, style: str,
                 prompt: str, instrumental: bool) -> str:
        body = {
            "customMode": True,
            "style": style,
            "title": title,
            "prompt": prompt,
            "instrumental": instrumental,
            "model": "V5",
        }
        print(f"[sunoapi.org] Submitting generation: {title!r}")
        print(f"  Style : {style}")
        print(f"  Prompt: {prompt[:120]}{'...' if len(prompt) > 120 else ''}")

        resp = requests.post(self.GENERATE_URL, headers=self._headers(api_key),
                             json=body, timeout=30)
        if resp.status_code != 200:
            die(f"[sunoapi.org] Generate returned HTTP {resp.status_code}.\n"
                f"  Body: {resp.text[:400]}")
        data = resp.json()
        task_id = (data.get("taskId") or data.get("task_id")
                   or data.get("data", {}).get("taskId"))
        if not task_id:
            die(f"[sunoapi.org] No taskId in response:\n  {json.dumps(data, indent=2)[:600]}")
        print(f"[sunoapi.org] Task ID: {task_id}")
        return task_id

    def poll(self, api_key: str, task_id: str) -> list[dict]:
        deadline = time.monotonic() + MAX_POLL_SEC
        attempt = 0

        while time.monotonic() < deadline:
            attempt += 1
            time.sleep(POLL_INTERVAL_SEC)
            elapsed = int(POLL_INTERVAL_SEC * attempt)
            print(f"  Polling ({elapsed}s elapsed)...")

            resp = requests.get(self.RECORD_URL, headers=self._headers(api_key),
                                params={"taskId": task_id}, timeout=30)
            if resp.status_code != 200:
                print(f"  Poll HTTP {resp.status_code} — retrying...")
                continue

            data = resp.json()
            status = (
                data.get("status")
                or data.get("data", {}).get("status")
                or ""
            ).upper()

            if status == "SUCCESS":
                suno_data = (
                    data.get("response", {}).get("sunoData")
                    or data.get("data", {}).get("sunoData")
                    or data.get("sunoData")
                    or []
                )
                if not suno_data:
                    die(f"[sunoapi.org] SUCCESS but no sunoData:\n"
                        f"  {json.dumps(data, indent=2)[:600]}")
                results = []
                for item in suno_data:
                    results.append({
                        "audio_url": item.get("audioUrl") or item.get("audio_url", ""),
                        "title": item.get("title", ""),
                        "duration": float(item.get("duration") or 0.0),
                    })
                print(f"  SUCCESS — {len(results)} track(s).")
                return results

            if status in ("FAILED", "ERROR"):
                die(f"[sunoapi.org] Generation failed.\n"
                    f"  Response: {json.dumps(data, indent=2)[:600]}")

            print(f"  Status: {status or 'pending'}")

        die(f"[sunoapi.org] Timed out after {MAX_POLL_SEC}s for task {task_id}.")
        return []  # unreachable


# ---------------------------------------------------------------------------
# Suno direct provider  (SunoAI Python library — cookie-based)
# ---------------------------------------------------------------------------

class SunoDirectProvider(Provider):
    """Uses the SunoAI Python library to call Suno directly via session cookie.

    Requires SUNO_COOKIE env var (extracted by tools/suno_cookie.py).
    Supports the actual Suno models including V3.5 and newer.
    The library handles automatic token refresh.
    """
    name = "suno"
    env_var = "SUNO_COOKIE"
    audio_format = "mp3"
    MODEL = "chirp-v3-5"

    def generate(self, api_key: str, title: str, style: str,
                 prompt: str, instrumental: bool) -> str:
        from suno import Suno

        print(f"[suno] Connecting with session cookie...")
        client = Suno(cookie=api_key, model_version=self.MODEL)

        credits_info = client.get_credits()
        print(f"[suno] Credits remaining: {credits_info}")

        print(f"[suno] Generating: {title!r}")
        print(f"  Tags  : {style}")
        print(f"  Prompt: {prompt[:120]}{'...' if len(prompt) > 120 else ''}")

        clips = client.generate(
            prompt=prompt,
            is_custom=True,
            tags=style,
            title=title,
            make_instrumental=instrumental,
            wait_audio=True,
        )

        if not clips:
            die("[suno] Generation returned no clips.")

        # Store clip data as JSON in the task_id field for later retrieval
        results = []
        for clip in clips:
            results.append({
                "audio_url": clip.audio_url or "",
                "title": clip.title or title,
                "duration": 0.0,  # Will probe with ffprobe
                "id": clip.id or "",
            })

        # Stash results for poll() — but since wait_audio=True, we have them now
        self._last_results = results
        return ",".join(r["id"] for r in results)

    def poll(self, api_key: str, task_id: str) -> list[dict]:
        # wait_audio=True means generate() already waited — results are ready
        if hasattr(self, "_last_results") and self._last_results:
            results = self._last_results
            self._last_results = None
            complete = [r for r in results if r["audio_url"]]
            if complete:
                print(f"  {len(complete)} track(s) ready.")
                return complete

        # Fallback: poll by clip ID
        from suno import Suno
        print(f"[suno] Polling clips: {task_id}")
        client = Suno(cookie=api_key, model_version=self.MODEL)
        clip_ids = task_id.split(",")
        deadline = time.monotonic() + MAX_POLL_SEC
        attempt = 0

        while time.monotonic() < deadline:
            attempt += 1
            time.sleep(POLL_INTERVAL_SEC)
            print(f"  Polling ({POLL_INTERVAL_SEC * attempt}s elapsed)...")

            results = []
            all_ready = True
            for cid in clip_ids:
                clip = client.get_song(cid)
                if clip and clip.audio_url:
                    results.append({
                        "audio_url": clip.audio_url,
                        "title": clip.title or "",
                        "duration": 0.0,
                        "id": clip.id or cid,
                    })
                else:
                    all_ready = False

            if all_ready and results:
                print(f"  {len(results)} track(s) ready.")
                return results

        die(f"[suno] Timed out after {MAX_POLL_SEC}s for clips: {task_id}")
        return []


# ---------------------------------------------------------------------------
# Provider registry
# ---------------------------------------------------------------------------

PROVIDERS: dict[str, Provider] = {
    "suno": SunoDirectProvider(),
    "aimlapi": AimlApiProvider(),
    "sunoapi_org": SunoApiOrgProvider(),
}

DEFAULT_PROVIDER = "suno"


# ---------------------------------------------------------------------------
# Download + convert
# ---------------------------------------------------------------------------

def download_audio(audio_url: str, dest: Path) -> None:
    """Download audio file from URL to dest path."""
    print(f"Downloading: {audio_url}")
    resp = requests.get(audio_url, timeout=120, stream=True)
    if resp.status_code != 200:
        die(f"Failed to download audio (HTTP {resp.status_code}): {audio_url}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("wb") as fh:
        for chunk in resp.iter_content(chunk_size=65536):
            fh.write(chunk)
    print(f"Saved: {dest} ({dest.stat().st_size // 1024} KB)")


def convert_to_ogg(src_path: Path, ogg_path: Path) -> None:
    """Convert any ffmpeg-supported audio format to OGG Vorbis."""
    print(f"Converting to OGG: {ogg_path.name}")
    result = subprocess.run(
        [
            "ffmpeg", "-y",
            "-i", str(src_path),
            "-c:a", "libvorbis",
            "-q:a", "6",
            str(ogg_path),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr[-800:], file=sys.stderr)
        die(f"ffmpeg conversion failed (exit {result.returncode}).")
    print(f"OGG written: {ogg_path} ({ogg_path.stat().st_size // 1024} KB)")


def probe_duration(ogg_path: Path) -> float:
    """Return duration in seconds via ffprobe, or 0.0 on failure."""
    try:
        result = subprocess.run(
            [
                "ffprobe", "-v", "quiet",
                "-print_format", "json",
                "-show_streams",
                str(ogg_path),
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )
        info = json.loads(result.stdout)
        for stream in info.get("streams", []):
            dur = stream.get("duration")
            if dur:
                return float(dur)
    except Exception:
        pass
    return 0.0


def preview_track(ogg_path: Path) -> None:
    print(f"Playing preview with mpv: {ogg_path.name}")
    subprocess.run(["mpv", "--no-video", str(ogg_path)])


# ---------------------------------------------------------------------------
# Track selection
# ---------------------------------------------------------------------------

def pick_tracks(track_data: list[dict], pick: str) -> list[tuple[int, dict]]:
    """Return list of (1-based index, track_dict) to keep based on --pick."""
    pick = pick.strip().lower()
    if pick == "both":
        return list(enumerate(track_data, start=1))
    try:
        idx = int(pick)
    except ValueError:
        die(f"--pick must be 1, 2, or 'both'. Got: {pick!r}")
    if idx < 1 or idx > len(track_data):
        die(f"--pick {idx} out of range — only {len(track_data)} track(s) returned.")
    return [(idx, track_data[idx - 1])]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    provider_names = list(PROVIDERS.keys())
    parser = argparse.ArgumentParser(
        description="Generate Cowardly Irregular music via Suno API providers",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    # Provider
    parser.add_argument("--provider", choices=provider_names, default=DEFAULT_PROVIDER,
                        help=f"API provider (default: {DEFAULT_PROVIDER})")

    # Core identity
    parser.add_argument("--track-id", required=True, metavar="ID",
                        help="Unique track ID for music_manifest.json (e.g. overworld_medieval)")
    parser.add_argument("--title", default="", help="Song title sent to Suno")
    parser.add_argument("--style", default="",
                        help="Style/genre tags (e.g. '16-bit SNES orchestral, harp, strings')")
    parser.add_argument("--prompt", default="",
                        help="Descriptive prompt for the composition")
    parser.add_argument("--instrumental", action="store_true", default=True,
                        help="Generate instrumental track (default: true)")
    parser.add_argument("--no-instrumental", dest="instrumental", action="store_false",
                        help="Allow vocals in generated track")

    # World template shortcut
    parser.add_argument("--world", type=int, metavar="N",
                        help="Load style/prompt template from tools/music_prompts.json (1-6)")

    # Output control
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR,
                        metavar="DIR", help=f"Output directory (default: {DEFAULT_OUTPUT_DIR})")
    parser.add_argument("--pick", default="1", metavar="N|both",
                        help="Which of the 2 generated tracks to keep: 1, 2, or 'both' (default: 1)")
    parser.add_argument("--keep-mp3", action="store_true",
                        help="Keep the intermediate audio file (MP3/WAV) after OGG conversion")

    # Extras
    parser.add_argument("--preview", action="store_true",
                        help="Play the downloaded track with mpv after generation")

    args = parser.parse_args()

    # ------------------------------------------------------------------
    # Select provider
    # ------------------------------------------------------------------
    provider = PROVIDERS[args.provider]
    print(f"Using provider: {provider.name}")

    # ------------------------------------------------------------------
    # Resolve title/style/prompt: CLI args override world template
    # ------------------------------------------------------------------
    title = args.title
    style = args.style
    prompt = args.prompt

    if args.world is not None:
        template = load_world_template(args.world, args.track_id)
        if not title:
            title = template.get("title", "")
        if not style:
            style = template.get("style", "")
        if not prompt:
            prompt = template.get("prompt", "")

    if not title:
        die("--title is required (or supply --world with a template that includes 'title')")
    if not style:
        die("--style is required (or supply --world with a template that includes 'style')")
    if not prompt:
        die("--prompt is required (or supply --world with a template that includes 'prompt')")

    # ------------------------------------------------------------------
    # Load API key
    # ------------------------------------------------------------------
    api_key = provider.get_api_key()

    # ------------------------------------------------------------------
    # Generate
    # ------------------------------------------------------------------
    task_id = provider.generate(api_key, title, style, prompt, args.instrumental)

    # ------------------------------------------------------------------
    # Poll
    # ------------------------------------------------------------------
    print(f"\nPolling for completion (up to {MAX_POLL_SEC}s)...")
    track_data = provider.poll(api_key, task_id)

    # ------------------------------------------------------------------
    # Pick which track(s) to download
    # ------------------------------------------------------------------
    selections = pick_tracks(track_data, args.pick)

    for pick_idx, track_info in selections:
        audio_url = track_info.get("audio_url", "")
        if not audio_url:
            die(f"Track {pick_idx} has no audio_url.\n"
                f"  Data: {json.dumps(track_info, indent=2)[:400]}")

        returned_title = track_info.get("title") or title
        duration = float(track_info.get("duration") or 0.0)

        # Build file names — suffix _2 if keeping both and this is the second
        suffix = f"_{pick_idx}" if args.pick.strip().lower() == "both" else ""
        track_key = f"{args.track_id}{suffix}"
        raw_ext = provider.audio_format  # wav, mp3, etc.
        raw_path = args.output_dir / f"{track_key}.{raw_ext}"
        ogg_path = args.output_dir / f"{track_key}.ogg"

        # Download
        download_audio(audio_url, raw_path)

        # Convert to OGG
        convert_to_ogg(raw_path, ogg_path)

        # Probe duration if not provided by API
        if not duration:
            duration = probe_duration(ogg_path)

        # Cleanup raw download
        if not args.keep_mp3:
            raw_path.unlink(missing_ok=True)
            print(f"Removed intermediate file: {raw_path.name}")

        # Relative path for manifest (relative to project root)
        rel_path = ogg_path.relative_to(PROJECT_ROOT)

        # Update manifest atomically (safe for parallel runs)
        entry = {
            "file": str(rel_path),
            "tier": "T1",
            "provider": provider.name,
            "task_id": task_id,
            "title": returned_title,
            "prompt": prompt,
            "style": style,
            "model": getattr(provider, "MODEL", "V5"),
            "duration": round(duration, 2),
            "loop": True,
            "generated_at": date.today().isoformat(),
        }
        update_manifest_atomic(track_key, entry)

        print(f"\nTrack {pick_idx} ready: {ogg_path}")

        # Preview
        if args.preview:
            preview_track(ogg_path)

    print("\nDone.")


if __name__ == "__main__":
    main()
