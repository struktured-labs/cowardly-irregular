# /// script
# requires-python = ">=3.10"
# dependencies = ["patchright", "requests"]
# ///
"""
suno_api.py — Automated Suno music generation pipeline.

Uses patchright (anti-detection Playwright) to drive the Suno web UI. The web UI
handles captcha internally — generation goes through even when captcha appears.
After submission, we poll the Suno REST API for completion and download.

Usage:
    # Single track:
    uv run tools/suno_api.py --world 2 --track-id overworld_suburban

    # Batch — all remaining tracks:
    uv run tools/suno_api.py --batch --world all --shared --skip-existing

    # Regenerate unpinned tracks with prompt tweaks:
    uv run tools/suno_api.py --batch --world all --shared --regenerate --weirdness 0

    # Pin tracks you're happy with:
    uv run tools/suno_api.py --pin overworld_medieval village_medieval

    # Unpin to allow regeneration:
    uv run tools/suno_api.py --unpin overworld_medieval

    # List all tracks with pin/generation status:
    uv run tools/suno_api.py --list

    # Edit prompts in $EDITOR:
    uv run tools/suno_api.py --edit-prompts

    # Login (first time only):
    uv run tools/suno_api.py --login

First run:
    uv run patchright install chromium
"""

from __future__ import annotations

import argparse
import base64
import fcntl
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import date
from pathlib import Path

import requests
from patchright.sync_api import sync_playwright, Page, BrowserContext

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "assets" / "audio" / "music"
MANIFEST_PATH = PROJECT_ROOT / "data" / "music_manifest.json"
PROMPTS_PATH = PROJECT_ROOT / "tools" / "music_prompts.json"
PROFILE_DIR = PROJECT_ROOT / "tmp" / "suno-browser-profile"

SUNO_API = "https://studio-api.prod.suno.com"
SUNO_CREATE_URL = "https://suno.com/create"

POLL_INTERVAL = 10
MAX_POLL_SEC = 300

# Human-like timing ranges (milliseconds)
HUMAN_THINK_MS = (1500, 3500)       # Pause before acting (reading the UI)
HUMAN_TYPE_CHAR_MS = (30, 90)       # Per-character typing speed (~80-120 WPM)
HUMAN_FIELD_GAP_MS = (800, 2000)    # Pause between form fields
HUMAN_PRE_CLICK_MS = (500, 1500)    # Pause before clicking a button
HUMAN_POST_CLICK_MS = (2000, 5000)  # Pause after clicking (watching result)
INTER_TRACK_MS = (15000, 30000)     # Gap between track generations


def _human_delay(range_ms: tuple[int, int]) -> None:
    """Sleep for a random duration within the given ms range."""
    ms = random.randint(range_ms[0], range_ms[1])
    time.sleep(ms / 1000.0)


def _jittered_poll_interval() -> float:
    """Return a jittered poll interval (8-14s instead of fixed 10s)."""
    return POLL_INTERVAL + random.uniform(-2, 4)

WORLD_SUFFIXES = {
    1: "medieval", 2: "suburban", 3: "steampunk",
    4: "industrial", 5: "digital", 6: "abstract",
}


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Manifest helpers
# ---------------------------------------------------------------------------

def load_manifest() -> dict:
    if MANIFEST_PATH.exists():
        with MANIFEST_PATH.open() as fh:
            return json.load(fh)
    return {"_comment": "Music manifest for Cowardly Irregular", "tracks": {},
            "tier_priority": ["T3", "T2", "T1"]}


def update_manifest_atomic(track_key: str, entry: dict) -> None:
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    lock_path = MANIFEST_PATH.with_suffix(".lock")
    with lock_path.open("w") as lock_fh:
        fcntl.flock(lock_fh, fcntl.LOCK_EX)
        try:
            manifest = load_manifest()
            if "tracks" not in manifest:
                manifest["tracks"] = {}
            manifest["tracks"][track_key] = entry
            with MANIFEST_PATH.open("w") as fh:
                json.dump(manifest, fh, indent=2)
        finally:
            fcntl.flock(lock_fh, fcntl.LOCK_UN)


# ---------------------------------------------------------------------------
# Pin management
# ---------------------------------------------------------------------------

def pin_tracks(track_ids: list[str]) -> None:
    manifest = load_manifest()
    tracks = manifest.get("tracks", {})
    for tid in track_ids:
        if tid not in tracks:
            print(f"  WARNING: '{tid}' not in manifest, skipping")
            continue
        tracks[tid]["pinned"] = True
        print(f"  Pinned: {tid}")
    with MANIFEST_PATH.open("w") as fh:
        json.dump(manifest, fh, indent=2)


def unpin_tracks(track_ids: list[str]) -> None:
    manifest = load_manifest()
    tracks = manifest.get("tracks", {})
    for tid in track_ids:
        if tid not in tracks:
            print(f"  WARNING: '{tid}' not in manifest, skipping")
            continue
        tracks[tid].pop("pinned", None)
        print(f"  Unpinned: {tid}")
    with MANIFEST_PATH.open("w") as fh:
        json.dump(manifest, fh, indent=2)


def is_pinned(track_id: str) -> bool:
    manifest = load_manifest()
    return manifest.get("tracks", {}).get(track_id, {}).get("pinned", False)


def list_tracks() -> None:
    manifest = load_manifest()
    tracks = manifest.get("tracks", {})
    prompts = load_prompts()
    all_world_tracks = set()
    for wk, wd in prompts.get("worlds", {}).items():
        suffix = WORLD_SUFFIXES.get(int(wk), wk)
        for tt in wd.get("tracks", {}):
            all_world_tracks.add(f"{tt}_{suffix}")
    for st in prompts.get("shared_tracks", {}):
        all_world_tracks.add(st)

    print(f"\n{'Track ID':<30s} {'Status':<12s} {'Pinned':<8s} {'Duration':<10s} {'Title'}")
    print("-" * 90)
    for tid in sorted(all_world_tracks):
        entry = tracks.get(tid, {})
        if entry:
            status = "generated"
            pinned = "YES" if entry.get("pinned") else ""
            dur = f"{entry.get('duration', 0):.0f}s"
            title = entry.get("title", "")
        else:
            status = "missing"
            pinned = ""
            dur = ""
            title = ""
        print(f"  {tid:<30s} {status:<12s} {pinned:<8s} {dur:<10s} {title}")
    pinned_count = sum(1 for e in tracks.values() if e.get("pinned"))
    print(f"\n{len(tracks)}/{len(all_world_tracks)} generated, {pinned_count} pinned")


# ---------------------------------------------------------------------------
# Weirdness / prompt variation
# ---------------------------------------------------------------------------

def apply_weirdness(title: str, style: str, prompt: str, weirdness: int,
                    take: int = 0) -> tuple[str, str, str]:
    """Mutate title/style/prompt based on weirdness level (0-5).

    0 = exact same prompt (reroll — Suno varies output naturally)
    1 = append take number to title (different seed, same vibe)
    2 = shuffle style tag order
    3 = drop one style tag, add a complementary one
    4 = rewrite prompt ending for variation
    5 = significant style mutation
    """
    if weirdness == 0:
        return title, style, prompt

    # Level 1+: title variation
    if take > 0:
        title = f"{title} (take {take + 1})"

    if weirdness >= 2:
        # Shuffle style tags
        tags = [t.strip() for t in style.split(",") if t.strip()]
        random.shuffle(tags)
        style = ", ".join(tags)

    if weirdness >= 3:
        # Drop one tag and add a variation
        tags = [t.strip() for t in style.split(",") if t.strip()]
        if len(tags) > 2:
            dropped = tags.pop(random.randint(0, len(tags) - 1))
            alternatives = {
                "harp": "lyre", "strings": "chamber strings", "brass": "horns",
                "piano": "keys", "synth": "analog synth", "drums": "percussion",
                "orchestral": "symphonic", "lo-fi": "lo-fi tape hiss",
                "chiptune": "8-bit", "ambient": "atmospheric", "guitar": "acoustic guitar",
                "flute": "pan flute", "organ": "church organ", "bass": "deep bass",
                "gentle": "soft", "aggressive": "intense", "mysterious": "enigmatic",
                "epic": "grandiose", "dark": "brooding", "bright": "luminous",
            }
            # Try to find a related alternative
            alt = alternatives.get(dropped.lower(), f"variation on {dropped}")
            tags.append(alt)
            style = ", ".join(tags)

    if weirdness >= 4:
        # Add a variation suffix to the prompt
        suffixes = [
            ", with a slightly different melodic approach",
            ", exploring an alternate arrangement",
            ", with emphasis on rhythmic variation",
            ", with a more dynamic range",
            ", leaning into the harmonic undertones",
        ]
        prompt = prompt.rstrip(".") + random.choice(suffixes)

    if weirdness >= 5:
        # Add a mood modifier to the style
        moods = ["ethereal", "raw", "cinematic", "intimate", "expansive",
                 "textured", "layered", "stripped-back"]
        style = style + ", " + random.choice(moods)

    return title, style, prompt


# ---------------------------------------------------------------------------
# Prompt editing
# ---------------------------------------------------------------------------

def edit_prompts() -> None:
    """Open music_prompts.json in $EDITOR for manual prompt tweaking."""
    editor = os.environ.get("EDITOR", os.environ.get("VISUAL", ""))
    if not editor:
        # Try to find a sensible default
        for candidate in ("nano", "vim", "vi"):
            if shutil.which(candidate):
                editor = candidate
                break
    if not editor:
        die("No $EDITOR set and no editor found. Set EDITOR env var.")

    # Make a backup
    backup = PROMPTS_PATH.with_suffix(".json.bak")
    shutil.copy2(PROMPTS_PATH, backup)

    # Open editor
    print(f"Opening {PROMPTS_PATH.name} in {editor}...")
    result = subprocess.run([editor, str(PROMPTS_PATH)])
    if result.returncode != 0:
        print("Editor exited with error, restoring backup.")
        shutil.copy2(backup, PROMPTS_PATH)
        return

    # Validate JSON
    try:
        with PROMPTS_PATH.open() as fh:
            data = json.load(fh)
        # Basic structure check
        assert "worlds" in data, "Missing 'worlds' key"
        assert "shared_tracks" in data, "Missing 'shared_tracks' key"
        print("Prompts updated and validated.")
    except (json.JSONDecodeError, AssertionError) as e:
        print(f"Invalid JSON after edit: {e}")
        print("Restoring backup.")
        shutil.copy2(backup, PROMPTS_PATH)
        return

    # Show diff
    diff = subprocess.run(
        ["diff", "--color=always", "-u", str(backup), str(PROMPTS_PATH)],
        capture_output=True, text=True,
    )
    if diff.stdout.strip():
        print("\nChanges:")
        print(diff.stdout)
    else:
        print("No changes made.")

    backup.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# World template helpers
# ---------------------------------------------------------------------------

def load_prompts() -> dict:
    if not PROMPTS_PATH.exists():
        die(f"music_prompts.json not found at {PROMPTS_PATH}")
    with PROMPTS_PATH.open() as fh:
        return json.load(fh)


def load_world_template(world: int, track_id: str) -> dict:
    prompts = load_prompts()
    worlds = prompts.get("worlds", {})
    key = str(world)
    if key not in worlds:
        die(f"World {world} not found.")
    world_data = worlds[key]
    tracks = world_data.get("tracks", {})
    shared = prompts.get("shared_tracks", {})
    track_type = track_id
    for suffix in ("_medieval", "_suburban", "_steampunk", "_industrial",
                   "_digital", "_abstract"):
        if track_type.endswith(suffix):
            track_type = track_type[: -len(suffix)]
            break
    if track_type in tracks:
        entry = tracks[track_type]
    elif track_id in shared:
        entry = shared[track_id]
    elif track_type in shared:
        entry = shared[track_type]
    else:
        die(f"Track type '{track_type}' not found in world {world}.")
    result = dict(entry)
    if "title_template" in result:
        result["title"] = result.pop("title_template")
    return result


def build_batch_queue(world_arg: str | int | None, shared: bool) -> list[dict]:
    prompts = load_prompts()
    queue = []
    if world_arg == "all":
        worlds = list(range(1, 7))
    elif world_arg is not None:
        worlds = [int(world_arg)]
    else:
        worlds = []
    for w in worlds:
        suffix = WORLD_SUFFIXES[w]
        world_data = prompts["worlds"][str(w)]
        for track_type, template in world_data.get("tracks", {}).items():
            t = dict(template)
            if "title_template" in t:
                t["title"] = t.pop("title_template")
            queue.append({
                "track_id": f"{track_type}_{suffix}",
                "title": t.get("title", ""),
                "style": t.get("style", ""),
                "prompt": t.get("prompt", ""),
            })
    if shared:
        for track_id, template in prompts.get("shared_tracks", {}).items():
            t = dict(template)
            if "title_template" in t:
                t["title"] = t.pop("title_template")
            queue.append({
                "track_id": track_id,
                "title": t.get("title", ""),
                "style": t.get("style", ""),
                "prompt": t.get("prompt", ""),
            })
    return queue


# ---------------------------------------------------------------------------
# Audio helpers
# ---------------------------------------------------------------------------

def convert_to_ogg(src: Path, dest: Path) -> None:
    print(f"  Converting to OGG: {dest.name}")
    result = subprocess.run(
        ["ffmpeg", "-y", "-i", str(src), "-c:a", "libvorbis", "-q:a", "6", str(dest)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        die(f"ffmpeg failed: {result.stderr[-300:]}")
    print(f"  OGG: {dest} ({dest.stat().st_size // 1024} KB)")


def probe_duration(path: Path) -> float:
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(path)],
            capture_output=True, text=True, timeout=15,
        )
        for s in json.loads(result.stdout).get("streams", []):
            if s.get("duration"):
                return float(s["duration"])
    except Exception:
        pass
    return 0.0


# ---------------------------------------------------------------------------
# JWT auth via Clerk
# ---------------------------------------------------------------------------

def _jwt_from_cookie_env() -> str | None:
    """Extract valid JWT from SUNO_COOKIE env var."""
    cookie = os.environ.get("SUNO_COOKIE", "")
    for part in cookie.split(";"):
        part = part.strip()
        if part.startswith("__session=") and not part.startswith("__session_"):
            jwt = part[len("__session="):]
            try:
                payload = jwt.split(".")[1]
                payload += "=" * (4 - len(payload) % 4)
                data = json.loads(base64.b64decode(payload))
                if data.get("exp", 0) > time.time() + 60:
                    return jwt
            except Exception:
                pass
    return None


def refresh_jwt_clerk() -> str | None:
    """Refresh JWT via Clerk REST API."""
    clerk_client = os.environ.get("CLERK_CLIENT", "").strip()
    session_id = os.environ.get("CLERK_SESSION_ID", "").strip()
    if not clerk_client or not session_id:
        return None
    try:
        resp = requests.post(
            f"https://auth.suno.com/v1/client/sessions/{session_id}/tokens",
            headers={"Cookie": f"__client={clerk_client}"},
            timeout=15,
        )
        if resp.status_code == 200:
            return resp.json().get("jwt", "")
    except Exception:
        pass
    return None


def get_fresh_jwt() -> str:
    """Get JWT — try cookie env, then Clerk refresh."""
    jwt = _jwt_from_cookie_env()
    if jwt:
        return jwt
    jwt = refresh_jwt_clerk()
    if jwt:
        return jwt
    die("Could not get JWT. Run: uv run tools/suno_api.py --login")
    return ""


def suno_headers(jwt: str) -> dict:
    return {"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"}


def check_credits(jwt: str) -> int:
    resp = requests.get(f"{SUNO_API}/api/billing/info/", headers=suno_headers(jwt), timeout=15)
    if resp.status_code != 200:
        die(f"Billing check failed: HTTP {resp.status_code}")
    return resp.json().get("total_credits_left", 0)


# ---------------------------------------------------------------------------
# Browser-driven generation
# ---------------------------------------------------------------------------

class SunoBrowser:
    """Manages patchright browser for Suno web UI automation."""

    def __init__(self, headless: bool = True):
        self._pw = None
        self._ctx: BrowserContext | None = None
        self._page: Page | None = None
        self._audio_urls: list[str] = []
        self._generation_responses: list[dict] = []
        self._headless = headless

    def start(self) -> None:
        PROFILE_DIR.mkdir(parents=True, exist_ok=True)
        self._pw = sync_playwright().start()
        self._ctx = self._pw.chromium.launch_persistent_context(
            str(PROFILE_DIR),
            headless=self._headless,
            viewport={"width": 1400, "height": 900},
            timeout=60000,
        )
        self._page = self._ctx.pages[0] if self._ctx.pages else self._ctx.new_page()

        # Inject cookies
        self._inject_cookies()

        # Network interceptor
        self._page.on("response", self._on_response)

        # Navigate
        print("  Navigating to suno.com/create...")
        self._page.goto(SUNO_CREATE_URL, wait_until="domcontentloaded")
        self._page.wait_for_timeout(5000)

        ta_count = self._page.locator("textarea").count()
        if ta_count == 0:
            die("Not logged in. Run: uv run tools/suno_api.py --login")
        print(f"  Logged in (textareas: {ta_count})")

    def _inject_cookies(self) -> None:
        cookie_str = os.environ.get("SUNO_COOKIE", "")
        if cookie_str:
            cookies = []
            for pair in cookie_str.split(";"):
                pair = pair.strip()
                if "=" not in pair:
                    continue
                name, value = pair.split("=", 1)
                cookies.append({
                    "name": name.strip(), "value": value.strip(),
                    "domain": ".suno.com", "path": "/",
                    "httpOnly": False, "secure": True, "sameSite": "Lax",
                })
            if cookies:
                self._ctx.add_cookies(cookies)

        clerk_client = os.environ.get("CLERK_CLIENT", "").strip()
        if clerk_client:
            self._ctx.add_cookies([{
                "name": "__client", "value": clerk_client,
                "domain": "auth.suno.com", "path": "/",
                "httpOnly": True, "secure": True, "sameSite": "None",
            }])

    def _on_response(self, response) -> None:
        url = response.url
        ct = response.headers.get("content-type", "")

        # Skip non-JSON, non-audio
        if any(url.endswith(ext) for ext in (".png", ".jpg", ".css", ".js", ".svg", ".ico")):
            return

        # Capture audio URLs
        is_audio = any(ext in url for ext in (".mp3", ".wav", ".m4a", ".ogg")) or "audio" in ct
        if is_audio and response.status == 200 and "sil-" not in url:
            if url not in self._audio_urls:
                self._audio_urls.append(url)

        # Capture generate API responses (clip IDs and audio URLs)
        if "application/json" in ct and response.status == 200:
            try:
                body = response.text()
                # Capture generation responses with clips
                if '"clips"' in body and '"submitted"' in body:
                    data = json.loads(body)
                    if "clips" in data:
                        self._generation_responses.append(data)
                # Capture audio URLs from JSON
                for m in re.finditer(r'"audio_url"\s*:\s*"(https://[^"]+\.mp3[^"]*)"', body):
                    found = m.group(1)
                    if found not in self._audio_urls and "sil-" not in found:
                        self._audio_urls.append(found)
            except Exception:
                pass

    def _simulate_mouse_to(self, selector: str, index: int = 0) -> None:
        """Move mouse to an element with human-like trajectory."""
        page = self._page
        try:
            el = page.locator(selector).nth(index)
            if el.is_visible():
                box = el.bounding_box()
                if box:
                    # Random offset within the element (don't always hit center)
                    target_x = box["x"] + box["width"] * random.uniform(0.2, 0.8)
                    target_y = box["y"] + box["height"] * random.uniform(0.3, 0.7)
                    # Move with intermediate steps for natural trajectory
                    steps = random.randint(3, 8)
                    page.mouse.move(target_x, target_y, steps=steps)
                    _human_delay((100, 300))
        except Exception:
            pass

    def _type_human(self, page, selector: str, value: str, index: int = 0) -> bool:
        """Type text character-by-character with human-like timing."""
        try:
            el = page.locator(selector).nth(index)
            if not el.is_visible():
                return False
            self._simulate_mouse_to(selector, index)
            el.click()
            _human_delay((200, 500))
            # Select all and delete first
            el.press("Control+a")
            _human_delay((100, 200))
            el.press("Backspace")
            _human_delay((200, 400))
            # Type with per-character jitter
            for char in value:
                el.type(char, delay=random.randint(HUMAN_TYPE_CHAR_MS[0], HUMAN_TYPE_CHAR_MS[1]))
            return True
        except Exception:
            return False

    def _react_fill(self, selector: str, value: str, index: int = 0) -> bool:
        """Fill a React controlled input/textarea — tries human typing first, falls back to JS."""
        page = self._page
        # Try human-like typing first (more natural for hCaptcha)
        if self._type_human(page, selector, value, index):
            return True
        # Fallback: JS injection for React controlled inputs
        return page.evaluate(f"""(value) => {{
            const els = document.querySelectorAll('{selector}');
            if (els.length <= {index}) return false;
            const el = els[{index}];
            const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
                window.HTMLTextAreaElement.prototype, 'value'
            )?.set || Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'value'
            )?.set;
            if (nativeInputValueSetter) {{
                nativeInputValueSetter.call(el, value);
            }} else {{
                el.value = value;
            }}
            el.dispatchEvent(new Event('input', {{ bubbles: true }}));
            el.dispatchEvent(new Event('change', {{ bubbles: true }}));
            return true;
        }}""", value)

    def _fill_form(self, title: str, style: str, instrumental: bool = True) -> None:
        """Fill the create form with human-like timing and interaction."""
        page = self._page

        # Simulate "looking at the page" before interacting
        _human_delay(HUMAN_THINK_MS)

        # Enable Advanced mode
        adv_btn = page.locator("button").filter(has_text=re.compile(r"^Advanced$"))
        try:
            adv_btn.first.wait_for(timeout=3000)
            self._simulate_mouse_to("button:has-text('Advanced')")
            _human_delay(HUMAN_PRE_CLICK_MS)
            adv_btn.first.click()
            _human_delay(HUMAN_FIELD_GAP_MS)
        except Exception:
            pass  # Already in advanced mode

        _human_delay(HUMAN_FIELD_GAP_MS)

        # Clear lyrics (blank for instrumental) and fill style
        # NOTE: Suno added "Ask me anything" chat textarea at index 0 (2026-04).
        # Use placeholder-based selectors instead of fragile indices.
        lyrics_filled = False
        for sel in ("textarea[placeholder*='lyrics']", "textarea[placeholder*='instrumental']",
                    "textarea[placeholder*='Leave blank']"):
            if self._react_fill(sel, "", index=0):
                lyrics_filled = True
                break
        if not lyrics_filled:
            # Fallback: skip index 0 (chat prompt), use index 1
            self._react_fill("textarea", "", index=1)
        _human_delay(HUMAN_FIELD_GAP_MS)

        style_filled = False
        for sel in ("textarea[placeholder*='pop']", "textarea[placeholder*='house']",
                    "textarea[placeholder*='style']", "textarea[placeholder*='genre']"):
            if self._react_fill(sel, style, index=0):
                style_filled = True
                print(f"  Style: {style[:60]}...")
                break
        if not style_filled:
            # Fallback: skip index 0 (chat prompt), use index 2
            if self._react_fill("textarea", style, index=2):
                print(f"  Style: {style[:60]}...")
            else:
                print("  Warning: could not fill style textarea")

        _human_delay(HUMAN_FIELD_GAP_MS)

        # Title — try human typing first, fall back to JS
        title_filled = False
        for sel in ("input[placeholder*='itle']", "input[placeholder*='ong']",
                    "input[placeholder*='ame']"):
            if self._type_human(page, sel, title, index=0):
                print(f"  Title: {title}")
                title_filled = True
                break
        # Fallback: JS injection
        if not title_filled:
            for sel in ("input[placeholder*='itle']", "input[placeholder*='ong']",
                        "input[placeholder*='ame']"):
                result = page.evaluate(f"""(value) => {{
                    const el = document.querySelector("{sel}");
                    if (!el) return false;
                    const setter = Object.getOwnPropertyDescriptor(
                        window.HTMLInputElement.prototype, 'value'
                    )?.set;
                    if (setter) setter.call(el, value);
                    else el.value = value;
                    el.dispatchEvent(new Event('input', {{ bubbles: true }}));
                    el.dispatchEvent(new Event('change', {{ bubbles: true }}));
                    return true;
                }}""", title)
                if result:
                    print(f"  Title: {title}")
                    title_filled = True
                    break
        if not title_filled:
            print("  Warning: title input not found")

        _human_delay(HUMAN_FIELD_GAP_MS)

    def _click_create(self) -> None:
        """Click the Create button with human-like pre-click behavior."""
        page = self._page
        # Human-like pause before clicking (reviewing form)
        _human_delay(HUMAN_PRE_CLICK_MS)
        # Wait for the Create button to become enabled (form validation)
        for wait in range(20):
            create_btn = page.locator("button").filter(has_text=re.compile(r"Create"))
            visible = []
            for i in range(create_btn.count()):
                btn = create_btn.nth(i)
                if btn.is_visible() and btn.is_enabled():
                    visible.append(btn)
            if visible:
                visible[-1].scroll_into_view_if_needed()
                # Move mouse to button naturally
                try:
                    box = visible[-1].bounding_box()
                    if box:
                        x = box["x"] + box["width"] * random.uniform(0.3, 0.7)
                        y = box["y"] + box["height"] * random.uniform(0.3, 0.7)
                        page.mouse.move(x, y, steps=random.randint(4, 10))
                except Exception:
                    pass
                _human_delay((300, 800))
                visible[-1].click()
                _human_delay(HUMAN_POST_CLICK_MS)
                return
            page.wait_for_timeout(1000)
        # Last resort: click even if disabled
        create_btn = page.locator("button").filter(has_text=re.compile(r"Create"))
        for i in range(create_btn.count()):
            if create_btn.nth(i).is_visible():
                create_btn.nth(i).click(force=True)
                return
        die("No Create button found")

    def generate_track(self, track_id: str, title: str, style: str,
                       prompt: str, instrumental: bool = True) -> dict | None:
        """Generate one track via web UI. Returns clip info or None on failure."""
        page = self._page

        # Snapshot pre-generation state: track all known clip IDs to detect new ones
        known_clip_ids = set()
        for resp in self._generation_responses:
            for c in resp.get("clips", []):
                known_clip_ids.add(c.get("id", ""))

        # Navigate if needed (stay on create page for session persistence)
        if "/create" not in page.url:
            page.goto(SUNO_CREATE_URL, wait_until="domcontentloaded")
            page.wait_for_timeout(4000)

        # Fill form and submit
        self._fill_form(title, style, instrumental)
        self._click_create()
        print(f"  Create clicked, waiting for generation...")

        # Wait for generation API response — extract only NEW clip IDs
        clip_ids = []
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            page.wait_for_timeout(2000)
            # Check all responses for NEW clip IDs we haven't seen before
            for resp in self._generation_responses:
                for c in resp.get("clips", []):
                    cid = c.get("id", "")
                    if cid and cid not in known_clip_ids and cid not in clip_ids:
                        clip_ids.append(cid)
            if clip_ids:
                # Suno creates 2 clips per generation — take the first 2 new ones
                clip_ids = clip_ids[:2]
                print(f"  New clips: {clip_ids}")
                break

        if not clip_ids:
            print("  WARNING: No new clip IDs detected. Retrying with page reload...")
            page.reload(wait_until="domcontentloaded")
            page.wait_for_timeout(5000)
            return None

        # Poll for completion via REST API using ONLY our clip IDs
        jwt = get_fresh_jwt()
        headers = suno_headers(jwt)
        poll_deadline = time.monotonic() + MAX_POLL_SEC
        attempt = 0

        while time.monotonic() < poll_deadline:
            attempt += 1
            interval = _jittered_poll_interval()
            time.sleep(interval)
            elapsed = int(time.monotonic() - (poll_deadline - MAX_POLL_SEC))

            # Refresh JWT if needed
            fresh = get_fresh_jwt()
            if fresh:
                headers = suno_headers(fresh)

            try:
                poll_resp = requests.get(
                    f"{SUNO_API}/api/feed/",
                    headers=headers,
                    params={"ids": ",".join(clip_ids)},
                    timeout=15,
                )
                if poll_resp.status_code == 200:
                    feed = poll_resp.json()
                    if not isinstance(feed, list):
                        feed = feed.get("clips", feed.get("data", []))
                    for clip in feed:
                        cid = clip.get("id", "")
                        if cid not in clip_ids:
                            continue  # Skip clips not from this generation
                        if clip.get("status") == "complete" and clip.get("audio_url"):
                            print(f"  Complete! ({elapsed}s) clip={cid[:12]}")
                            return {
                                "audio_url": clip["audio_url"],
                                "title": clip.get("title", title),
                                "duration": float(clip.get("duration") or 0),
                                "id": cid,
                            }
                        elif clip.get("status") in ("error", "failed"):
                            print(f"  Clip {cid[:12]} failed: {clip.get('error_message', '?')}")
                            return None
            except Exception as e:
                print(f"  Poll error: {e}")

            print(f"  Polling ({elapsed}s)...")

        print(f"  TIMEOUT after {MAX_POLL_SEC}s")
        page.screenshot(path=str(PROJECT_ROOT / "tmp" / f"timeout_{track_id}.png"))
        return None

    def login_flow(self) -> None:
        """Interactive login — user logs in, we save cookies."""
        page = self._page
        page.goto(SUNO_CREATE_URL, wait_until="domcontentloaded")
        print("Complete login in the browser window...")
        for _ in range(120):  # 10 minutes
            page.wait_for_timeout(5000)
            if page.locator("textarea").count() > 0:
                print("Login successful!")
                # Save cookies back to setenv.sh
                cookies = self._ctx.cookies("https://suno.com")
                relevant = {c["name"]: c["value"] for c in cookies if c["name"].startswith("__")}
                if relevant:
                    cookie_str = "; ".join(f"{k}={v}" for k, v in relevant.items())
                    setenv = PROJECT_ROOT / "setenv.sh"
                    if setenv.exists():
                        content = setenv.read_text()
                        if "SUNO_COOKIE=" in content:
                            content = re.sub(
                                r'^export SUNO_COOKIE=.*$',
                                f'export SUNO_COOKIE="{cookie_str}"',
                                content, flags=re.MULTILINE,
                            )
                        else:
                            content += f'\nexport SUNO_COOKIE="{cookie_str}"\n'
                        setenv.write_text(content)
                    print(f"Saved {len(relevant)} cookies.")
                return
        die("Login timed out after 10 minutes.")

    def close(self) -> None:
        try:
            if self._ctx:
                self._ctx.close()
        except Exception:
            pass
        try:
            if self._pw:
                self._pw.stop()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Cowardly Irregular music via Suno (fully automated)",
    )

    # Generation args
    gen = parser.add_argument_group("generation")
    gen.add_argument("--track-id", metavar="ID", help="Track ID")
    gen.add_argument("--title", default="")
    gen.add_argument("--style", default="")
    gen.add_argument("--prompt", default="")
    gen.add_argument("--instrumental", action="store_true", default=True)
    gen.add_argument("--no-instrumental", dest="instrumental", action="store_false")
    gen.add_argument("--world", metavar="N", help="World 1-6 or 'all'")
    gen.add_argument("--batch", action="store_true")
    gen.add_argument("--shared", action="store_true")
    gen.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    gen.add_argument("--preview", action="store_true")
    gen.add_argument("--skip-existing", action="store_true",
                     help="Skip tracks already in manifest (always skips pinned)")
    gen.add_argument("--regenerate", action="store_true",
                     help="Regenerate existing unpinned tracks (opposite of --skip-existing)")
    gen.add_argument("--weirdness", type=int, default=0, metavar="N",
                     help="Prompt variation level 0-5 (0=exact reroll, 5=significant mutation)")

    # Pin management
    pin = parser.add_argument_group("pin management")
    pin.add_argument("--pin", nargs="+", metavar="ID",
                     help="Pin tracks (protect from regeneration)")
    pin.add_argument("--unpin", nargs="+", metavar="ID",
                     help="Unpin tracks (allow regeneration)")
    pin.add_argument("--pin-all", action="store_true",
                     help="Pin all existing tracks")

    # Info / editing
    info = parser.add_argument_group("info & editing")
    info.add_argument("--list", action="store_true", dest="list_tracks",
                      help="List all tracks with pin/generation status")
    info.add_argument("--edit-prompts", action="store_true",
                      help="Open music_prompts.json in $EDITOR")

    # Browser
    browser_grp = parser.add_argument_group("browser")
    browser_grp.add_argument("--login", action="store_true",
                             help="Interactive login flow (headed)")
    browser_grp.add_argument("--headed", action="store_true",
                             help="Run browser with visible window (default: headless)")

    args = parser.parse_args()

    # --- Non-generation commands (no browser needed) ---

    if args.pin:
        pin_tracks(args.pin)
        return

    if args.unpin:
        unpin_tracks(args.unpin)
        return

    if args.pin_all:
        manifest = load_manifest()
        all_ids = list(manifest.get("tracks", {}).keys())
        if all_ids:
            pin_tracks(all_ids)
        else:
            print("No tracks to pin.")
        return

    if args.list_tracks:
        list_tracks()
        return

    if args.edit_prompts:
        edit_prompts()
        return

    if not args.login and not args.batch and not args.shared and not args.track_id:
        die("--track-id required (or use --batch/--shared/--login/--list/--pin/--edit-prompts)")

    # Check credits
    if not args.login:
        jwt = get_fresh_jwt()
        credits_left = check_credits(jwt)
        print(f"Credits: {credits_left}")

    # Build queue
    if args.batch or args.shared:
        queue = build_batch_queue(args.world if args.batch else None, args.shared)

        # Filter: always skip pinned tracks
        manifest = load_manifest()
        existing = manifest.get("tracks", {})
        before = len(queue)
        pinned_skipped = 0
        filtered = []
        for t in queue:
            tid = t["track_id"]
            entry = existing.get(tid, {})
            if entry.get("pinned"):
                pinned_skipped += 1
                continue
            if args.skip_existing and tid in existing:
                continue
            if not args.regenerate and tid in existing:
                continue
            filtered.append(t)
        queue = filtered
        if pinned_skipped:
            print(f"Skipping {pinned_skipped} pinned track(s).")
        skipped = before - len(queue) - pinned_skipped
        if skipped > 0:
            print(f"Skipping {skipped} existing track(s).")
    elif args.login:
        queue = []
    else:
        world = int(args.world) if args.world else None
        title, style, prompt = args.title, args.style, args.prompt
        if world:
            template = load_world_template(world, args.track_id)
            title = title or template.get("title", "")
            style = style or template.get("style", "")
            prompt = prompt or template.get("prompt", "")
        # Single track: check if pinned
        if is_pinned(args.track_id):
            die(f"Track '{args.track_id}' is pinned. Use --unpin first.")
        queue = [{"track_id": args.track_id, "title": title, "style": style, "prompt": prompt}]

    if not args.login and not queue:
        print("Nothing to generate.")
        return

    if queue:
        print(f"\nQueue: {len(queue)} track(s)")
        for i, t in enumerate(queue, 1):
            w_tag = f" [W{args.weirdness}]" if args.weirdness > 0 else ""
            print(f"  {i:2d}. {t['track_id']:30s} {t['title']}{w_tag}")
        credits_needed = len(queue) * 10
        print(f"Credits needed: ~{credits_needed}")

    # Launch browser — headless by default, headed for --login or --headed
    headless = not (args.login or args.headed)
    print(f"\nStarting browser ({'headless' if headless else 'headed'})...")
    browser = SunoBrowser(headless=headless)
    browser.start()

    if args.login:
        browser.login_flow()
        browser.close()
        return

    succeeded, failed = 0, []
    try:
        for i, track in enumerate(queue, 1):
            # Inter-track delay (skip for first track)
            if i > 1:
                delay_s = random.randint(INTER_TRACK_MS[0], INTER_TRACK_MS[1]) / 1000
                print(f"\n  Waiting {delay_s:.0f}s before next track...")
                time.sleep(delay_s)

            print(f"\n{'=' * 60}")
            print(f"[{i}/{len(queue)}] {track['track_id']} — {track['title']}")
            print(f"{'=' * 60}")

            # Apply weirdness to prompts
            gen_title, gen_style, gen_prompt = apply_weirdness(
                track["title"], track["style"], track["prompt"],
                args.weirdness, take=i - 1,
            )
            if args.weirdness > 0:
                print(f"  Weirdness {args.weirdness}: title='{gen_title}', style='{gen_style[:60]}...'")

            result = browser.generate_track(
                track_id=track["track_id"],
                title=gen_title,
                style=gen_style,
                prompt=gen_prompt,
                instrumental=args.instrumental,
            )

            if not result:
                failed.append(track["track_id"])
                continue

            # Download and convert
            audio_url = result["audio_url"]
            track_key = track["track_id"]
            raw_path = args.output_dir / f"{track_key}.mp3"
            ogg_path = args.output_dir / f"{track_key}.ogg"

            print(f"  Downloading: {audio_url[:80]}...")
            resp = requests.get(audio_url, timeout=120, stream=True)
            raw_path.parent.mkdir(parents=True, exist_ok=True)
            with raw_path.open("wb") as fh:
                for chunk in resp.iter_content(65536):
                    fh.write(chunk)
            print(f"  Saved: {raw_path} ({raw_path.stat().st_size // 1024} KB)")

            convert_to_ogg(raw_path, ogg_path)
            duration = result.get("duration") or probe_duration(ogg_path)
            raw_path.unlink(missing_ok=True)

            # Preserve pinned status if track was already in manifest
            existing_entry = load_manifest().get("tracks", {}).get(track_key, {})
            entry = {
                "file": str(ogg_path.relative_to(PROJECT_ROOT)),
                "tier": "T1",
                "provider": "suno",
                "title": result.get("title", track["title"]),
                "prompt": track["prompt"],
                "style": track["style"],
                "model": "suno-v4",
                "duration": round(duration, 2),
                "loop": True,
                "generated_at": date.today().isoformat(),
            }
            if existing_entry.get("pinned"):
                entry["pinned"] = True
            update_manifest_atomic(track_key, entry)
            print(f"  Track ready: {ogg_path}")

            if args.preview:
                subprocess.run(["mpv", "--no-video", str(ogg_path)])

            succeeded += 1

    finally:
        browser.close()

    print(f"\n{'=' * 60}")
    print(f"DONE: {succeeded}/{len(queue)} succeeded")
    if failed:
        print(f"Failed: {', '.join(failed)}")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    main()
