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
import re
import subprocess
import sys
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

    def __init__(self):
        self._pw = None
        self._ctx: BrowserContext | None = None
        self._page: Page | None = None
        self._audio_urls: list[str] = []
        self._generation_responses: list[dict] = []

    def start(self) -> None:
        PROFILE_DIR.mkdir(parents=True, exist_ok=True)
        self._pw = sync_playwright().start()
        self._ctx = self._pw.chromium.launch_persistent_context(
            str(PROFILE_DIR),
            headless=False,
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

    def _react_fill(self, selector: str, value: str, index: int = 0) -> bool:
        """Fill a React controlled input/textarea by setting native value + dispatching events."""
        page = self._page
        return page.evaluate(f"""(value) => {{
            const els = document.querySelectorAll('{selector}');
            if (els.length <= {index}) return false;
            const el = els[{index}];
            // React uses internal fiber to track state — need to set via native setter
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
        """Fill the create form with React-compatible event dispatching."""
        page = self._page

        # Enable Advanced mode
        adv_btn = page.locator("button").filter(has_text=re.compile(r"^Advanced$"))
        try:
            adv_btn.first.wait_for(timeout=3000)
            adv_btn.first.click()
            page.wait_for_timeout(500)
        except Exception:
            pass  # Already in advanced mode

        page.wait_for_timeout(500)

        # Clear lyrics (blank for instrumental) and fill style
        self._react_fill("textarea", "", index=0)  # Lyrics
        if self._react_fill("textarea", style, index=1):
            print(f"  Style: {style[:60]}...")
        else:
            print("  Warning: could not fill style textarea")

        # Title — try various input selectors
        title_filled = False
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

        page.wait_for_timeout(500)

    def _click_create(self) -> None:
        """Click the Create button (wait for it to be enabled)."""
        page = self._page
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
                page.wait_for_timeout(300)
                visible[-1].click()
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
            time.sleep(POLL_INTERVAL)
            elapsed = attempt * POLL_INTERVAL

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
    parser.add_argument("--track-id", metavar="ID", help="Track ID")
    parser.add_argument("--title", default="")
    parser.add_argument("--style", default="")
    parser.add_argument("--prompt", default="")
    parser.add_argument("--instrumental", action="store_true", default=True)
    parser.add_argument("--no-instrumental", dest="instrumental", action="store_false")
    parser.add_argument("--world", metavar="N", help="World 1-6 or 'all'")
    parser.add_argument("--batch", action="store_true")
    parser.add_argument("--shared", action="store_true")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--skip-existing", action="store_true")
    parser.add_argument("--login", action="store_true", help="Interactive login flow")

    args = parser.parse_args()

    if not args.login and not args.batch and not args.shared and not args.track_id:
        die("--track-id required (or use --batch/--shared/--login)")

    # Check credits
    if not args.login:
        jwt = get_fresh_jwt()
        credits = check_credits(jwt)
        print(f"Credits: {credits}")

    # Build queue
    if args.batch or args.shared:
        queue = build_batch_queue(args.world if args.batch else None, args.shared)
        if args.skip_existing:
            existing = set(load_manifest().get("tracks", {}).keys())
            before = len(queue)
            queue = [t for t in queue if t["track_id"] not in existing]
            skipped = before - len(queue)
            if skipped:
                print(f"Skipping {skipped} existing tracks.")
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
        queue = [{"track_id": args.track_id, "title": title, "style": style, "prompt": prompt}]

    if not args.login and not queue:
        print("Nothing to generate.")
        return

    if queue:
        print(f"\nQueue: {len(queue)} track(s)")
        for i, t in enumerate(queue, 1):
            print(f"  {i:2d}. {t['track_id']:30s} {t['title']}")
        credits_needed = len(queue) * 10
        print(f"Credits needed: ~{credits_needed}")

    # Launch browser
    print("\nStarting browser...")
    browser = SunoBrowser()
    browser.start()

    if args.login:
        browser.login_flow()
        browser.close()
        return

    succeeded, failed = 0, []
    try:
        for i, track in enumerate(queue, 1):
            print(f"\n{'=' * 60}")
            print(f"[{i}/{len(queue)}] {track['track_id']} — {track['title']}")
            print(f"{'=' * 60}")

            result = browser.generate_track(
                track_id=track["track_id"],
                title=track["title"],
                style=track["style"],
                prompt=track["prompt"],
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

            update_manifest_atomic(track_key, {
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
            })
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
