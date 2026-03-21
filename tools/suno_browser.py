# /// script
# requires-python = ">=3.10"
# dependencies = ["playwright", "requests"]
# ///
"""
suno_browser.py — Generate music on suno.com via Playwright browser automation.

Drives the Suno web UI directly — no API needed. Uses a persistent browser
profile so you only need to log in once. Captcha requires manual solving.

Usage:
    # Single track:
    uv run tools/suno_browser.py --world 1 --track-id overworld_medieval

    # Batch — all tracks for a world:
    uv run tools/suno_browser.py --batch --world 1

    # Batch — ALL worlds (all 24+ tracks):
    uv run tools/suno_browser.py --batch --world all

    # Shared tracks (victory, game_over, title):
    uv run tools/suno_browser.py --batch --shared

    # Login only (save session):
    uv run tools/suno_browser.py --login

    # Explore DOM:
    uv run tools/suno_browser.py --explore

First run:
    playwright install chromium
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import subprocess
import sys
import time
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright, Page, BrowserContext, TimeoutError as PwTimeout

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "assets" / "audio" / "music"
MANIFEST_PATH = PROJECT_ROOT / "data" / "music_manifest.json"
PROMPTS_PATH = PROJECT_ROOT / "tools" / "music_prompts.json"
PROFILE_DIR = PROJECT_ROOT / "tmp" / "suno-browser-profile"

SUNO_CREATE_URL = "https://suno.com/create"

WORLD_SUFFIXES = {
    1: "medieval", 2: "suburban", 3: "steampunk",
    4: "industrial", 5: "digital", 6: "abstract",
}


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
    """Thread/process-safe manifest update using file locking."""
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
        die(f"World {world} not found. Available: {', '.join(worlds.keys())}")
    world_data = worlds[key]
    tracks = world_data.get("tracks", {})
    shared = prompts.get("shared_tracks", {})
    track_type = track_id
    for suffix in ("_medieval", "_suburban", "_steampunk", "_industrial",
                   "_digital", "_abstract", "_cave", "_generic"):
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
        die(f"Track type '{track_type}' not found in world {world} templates.")
    result = dict(entry)
    if "title_template" in result and "title" not in result:
        result["title"] = result.pop("title_template")
    return result


def build_batch_queue(world_arg: str | int | None, shared: bool) -> list[dict]:
    """Build a list of {track_id, title, style, prompt} dicts for batch generation."""
    prompts = load_prompts()
    queue = []

    if world_arg == "all":
        worlds_to_gen = list(range(1, 7))
    elif world_arg is not None:
        worlds_to_gen = [int(world_arg)]
    else:
        worlds_to_gen = []

    for w in worlds_to_gen:
        suffix = WORLD_SUFFIXES[w]
        world_data = prompts["worlds"][str(w)]
        for track_type, template in world_data.get("tracks", {}).items():
            track_id = f"{track_type}_{suffix}"
            t = dict(template)
            if "title_template" in t:
                t["title"] = t.pop("title_template")
            queue.append({
                "track_id": track_id,
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


def convert_to_ogg(src: Path, dest: Path) -> None:
    print(f"Converting to OGG: {dest.name}")
    result = subprocess.run(
        ["ffmpeg", "-y", "-i", str(src), "-c:a", "libvorbis", "-q:a", "6", str(dest)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(result.stderr[-500:], file=sys.stderr)
        die("ffmpeg conversion failed.")
    print(f"OGG: {dest} ({dest.stat().st_size // 1024} KB)")


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
# Browser helpers
# ---------------------------------------------------------------------------

def launch_browser(headless: bool = False) -> tuple:
    """Launch persistent Chromium context. Returns (playwright, context)."""
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    pw = sync_playwright().start()
    ctx = pw.chromium.launch_persistent_context(
        str(PROFILE_DIR),
        headless=False,  # Always headed — hCaptcha blocks headless
        viewport={"width": 1400, "height": 900},
        timeout=60000,
    )
    return pw, ctx


def save_session_cookies(ctx: BrowserContext) -> None:
    """Extract session cookies and save to setenv.sh."""
    cookies = ctx.cookies("https://suno.com")
    relevant = {c["name"]: c["value"] for c in cookies if c["name"].startswith("__")}
    if not relevant:
        print("Warning: No session cookies found to save.")
        return
    cookie_str = "; ".join(f"{k}={v}" for k, v in relevant.items())
    setenv_path = PROJECT_ROOT / "setenv.sh"
    if setenv_path.exists():
        content = setenv_path.read_text()
        if "SUNO_COOKIE=" in content:
            content = re.sub(
                r'^export SUNO_COOKIE=.*$',
                f'export SUNO_COOKIE="{cookie_str}"',
                content, flags=re.MULTILINE,
            )
        else:
            content = content.rstrip() + f'\nexport SUNO_COOKIE="{cookie_str}"\n'
        setenv_path.write_text(content)
    print(f"Saved {len(relevant)} cookies to {setenv_path}")


def inject_cookies(ctx: BrowserContext) -> bool:
    """Inject SUNO_COOKIE from env into browser context."""
    cookie_str = os.environ.get("SUNO_COOKIE", "").strip()
    if not cookie_str:
        return False
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
        ctx.add_cookies(cookies)
        print(f"Injected {len(cookies)} cookies from SUNO_COOKIE env var.")
        return True
    return False


def ensure_logged_in(page: Page, headless: bool = False) -> None:
    """Check if logged in, wait for login if not."""
    page.goto(SUNO_CREATE_URL, wait_until="domcontentloaded")
    page.wait_for_timeout(4000)

    max_attempts = 12 if headless else 60
    for attempt in range(max_attempts):
        if "/create" in page.url:
            try:
                page.locator("textarea").first.wait_for(timeout=3000)
                print("Logged in and on create page.")
                return
            except PwTimeout:
                pass
        if attempt == 0:
            if headless:
                print("Checking login status (headless)...")
            else:
                print("Waiting for login... Complete it in the browser window.")
        time.sleep(5)

    if headless:
        ss = PROJECT_ROOT / "tmp" / "suno_login_fail.png"
        ss.parent.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=str(ss))
        die(f"Login failed in headless mode. Screenshot: {ss}")
    else:
        die("Timed out waiting for login.")


def enable_advanced_mode(page: Page) -> None:
    """Switch to Advanced mode."""
    adv_btn = page.locator("button").filter(has_text=re.compile(r"^Advanced$"))
    try:
        adv_btn.first.wait_for(timeout=5000)
        adv_btn.first.click()
        page.wait_for_timeout(500)
        print("Advanced mode enabled.")
    except PwTimeout:
        print("Warning: Could not find Advanced button — may already be in advanced mode.")


def fill_form(page: Page, title: str, style: str, prompt: str, instrumental: bool = True) -> None:
    """Fill Advanced mode form. textarea[0]=lyrics, textarea[1]=style."""
    page.wait_for_timeout(500)

    # Lyrics textarea
    lyrics_ta = page.locator("textarea").first
    if instrumental:
        lyrics_ta.fill("")
        print("Lyrics left blank (instrumental).")
    else:
        lyrics_ta.fill(prompt)
        print("Filled lyrics textarea.")

    # Style textarea (index 1)
    style_ta = page.locator("textarea").nth(1)
    try:
        style_ta.wait_for(timeout=3000)
        style_ta.fill(style)
        print(f"Filled style: {style[:60]}...")
    except PwTimeout:
        print("Warning: Could not find style textarea.")

    # Title input
    for selector in (
        "input[placeholder*='Title']",
        "input[placeholder*='title']",
        "input[placeholder*='Song']",
        "input[placeholder*='name']",
    ):
        title_input = page.locator(selector).first
        try:
            if title_input.count() == 0:
                continue
            title_input.wait_for(state="visible", timeout=2000)
            title_input.scroll_into_view_if_needed(timeout=2000)
            title_input.fill(title)
            print(f"Filled title: {title}")
            break
        except Exception:
            continue
    else:
        print("Warning: Could not find title input — title skipped.")

    page.wait_for_timeout(500)


def click_create(page: Page) -> None:
    """Click the Create button (form submit, not sidebar nav)."""
    create_btn = page.locator("button").filter(has_text=re.compile(r"Create"))
    visible_creates = []
    for i in range(create_btn.count()):
        btn = create_btn.nth(i)
        if btn.is_visible():
            visible_creates.append(btn)

    if not visible_creates:
        ss = PROJECT_ROOT / "tmp" / "suno_no_create_btn.png"
        ss.parent.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=str(ss))
        die(f"Could not find Create button. Screenshot: {ss}")

    target = visible_creates[-1]
    target.scroll_into_view_if_needed()
    page.wait_for_timeout(300)
    target.click()
    print(f"Clicked Create button ({len(visible_creates)} visible, picked last).")


def download_from_url(url: str, dest: Path) -> None:
    """Download audio file."""
    import requests
    print(f"Downloading: {url[:100]}...")
    resp = requests.get(url, timeout=120, stream=True)
    if resp.status_code != 200:
        die(f"Download failed (HTTP {resp.status_code})")
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("wb") as fh:
        for chunk in resp.iter_content(65536):
            fh.write(chunk)
    print(f"Saved: {dest} ({dest.stat().st_size // 1024} KB)")


# ---------------------------------------------------------------------------
# Core generation flow (one track)
# ---------------------------------------------------------------------------

def generate_one_track(
    page: Page,
    audio_urls: list[str],
    track_id: str,
    title: str,
    style: str,
    prompt: str,
    instrumental: bool,
    output_dir: Path,
    timeout_sec: int,
    preview: bool,
) -> bool:
    """Generate a single track via the Suno web UI.

    Returns True if successful, False if timed out.
    The browser stays open — caller manages lifecycle.
    """
    print(f"\n{'=' * 60}")
    print(f"  GENERATING: {track_id}")
    print(f"  Title: {title}")
    print(f"  Style: {style[:60]}...")
    print(f"{'=' * 60}\n")

    # Only navigate if not already on create page (preserves captcha session)
    if "/create" not in page.url:
        page.goto(SUNO_CREATE_URL, wait_until="domcontentloaded")
        page.wait_for_timeout(3000)

    enable_advanced_mode(page)

    # Clear form fields before filling (reuse same page)
    for i in range(page.locator("textarea").count()):
        try:
            page.locator("textarea").nth(i).fill("", timeout=2000)
        except Exception:
            pass
    for selector in ("input[placeholder*='Title']", "input[placeholder*='title']",
                     "input[placeholder*='Song']", "input[placeholder*='name']"):
        inp = page.locator(selector).first
        try:
            if inp.count() > 0:
                inp.fill("", timeout=2000)
        except Exception:
            pass

    fill_form(page, title, style, prompt, instrumental=instrumental)

    # Snapshot pre-create state
    pre_create_urls = set(audio_urls)
    pre_dom_srcs = set()
    for el in [page.locator("audio source"), page.locator("audio[src]")]:
        for i in range(el.count()):
            src = el.nth(i).get_attribute("src")
            if src:
                pre_dom_srcs.add(src)

    click_create(page)
    captcha_prompted = False

    # Wait for audio to appear
    print(f"\nWaiting for generation (up to {timeout_sec}s)...")
    print("If captcha appears, solve it in the browser window.\n")
    deadline = time.monotonic() + timeout_sec
    audio_url = None

    while time.monotonic() < deadline:
        page.wait_for_timeout(5000)
        elapsed = int(time.monotonic() - (deadline - timeout_sec))

        # Check for hCaptcha
        captcha_frame = page.locator("iframe[title*='hCaptcha'], iframe[src*='hcaptcha']")
        if captcha_frame.count() > 0 and not captcha_prompted:
            captcha_prompted = True
            print("\n" + "=" * 60)
            print("  hCAPTCHA DETECTED — please solve it in the browser window")
            print("=" * 60 + "\n")
        elif captcha_prompted and captcha_frame.count() == 0:
            print("  Captcha solved! Resuming wait...")
            captcha_prompted = False

        # Check network-intercepted URLs
        new_urls = [u for u in audio_urls if u not in pre_create_urls]
        if new_urls:
            audio_url = new_urls[-1]
            print(f"  Audio captured from network! ({elapsed}s)")
            break

        # Check DOM for new audio elements
        audio_els = page.locator("audio source, audio[src]")
        for i in range(audio_els.count()):
            src = audio_els.nth(i).get_attribute("src")
            if (src and src.startswith("http")
                    and src not in pre_dom_srcs
                    and "sil-" not in src):
                audio_url = src
                print(f"  New audio in DOM! ({elapsed}s)")
                break
        if audio_url:
            break

        print(f"  Waiting... ({elapsed}s)")

    if not audio_url:
        ss = PROJECT_ROOT / "tmp" / f"suno_timeout_{track_id}.png"
        ss.parent.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=str(ss))
        print(f"  TIMEOUT: No audio after {timeout_sec}s. Screenshot: {ss}")
        return False

    # Download and convert
    ext = Path(urlparse(audio_url).path).suffix or ".mp3"
    raw_path = output_dir / f"{track_id}{ext}"
    ogg_path = output_dir / f"{track_id}.ogg"

    download_from_url(audio_url, raw_path)
    convert_to_ogg(raw_path, ogg_path)
    duration = probe_duration(ogg_path)
    raw_path.unlink(missing_ok=True)

    # Update manifest atomically
    rel_path = ogg_path.relative_to(PROJECT_ROOT)
    update_manifest_atomic(track_id, {
        "file": str(rel_path),
        "tier": "T1",
        "provider": "suno",
        "title": title,
        "prompt": prompt,
        "style": style,
        "model": "suno-v4",
        "duration": round(duration, 2),
        "loop": True,
        "generated_at": date.today().isoformat(),
    })

    print(f"\nTrack ready: {ogg_path}")

    if preview:
        subprocess.run(["mpv", "--no-video", str(ogg_path)])

    return True


# ---------------------------------------------------------------------------
# Explore mode
# ---------------------------------------------------------------------------

def explore_mode(page: Page, headless: bool = False) -> None:
    """Print DOM element info from the create page."""
    ensure_logged_in(page, headless=headless)
    print("\n" + "=" * 60)
    print("  EXPLORE MODE — scanning DOM")
    print("=" * 60 + "\n")
    page.wait_for_timeout(2000)

    print("--- Textareas ---")
    for i in range(page.locator("textarea").count()):
        ta = page.locator("textarea").nth(i)
        print(f"  [{i}] placeholder={ta.get_attribute('placeholder')!r}")

    print("\n--- Text Inputs ---")
    for i in range(page.locator("input[type='text'], input:not([type])").count()):
        inp = page.locator("input[type='text'], input:not([type])").nth(i)
        print(f"  [{i}] placeholder={inp.get_attribute('placeholder')!r}")

    print("\n--- Buttons ---")
    for i in range(min(page.locator("button").count(), 20)):
        btn = page.locator("button").nth(i)
        text = btn.inner_text()[:50] if btn.is_visible() else "(hidden)"
        print(f"  [{i}] text={text!r}")

    print("\nDone.")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Cowardly Irregular music via Suno web UI (Playwright)",
    )
    parser.add_argument("--track-id", metavar="ID",
                        help="Track ID for music_manifest.json")
    parser.add_argument("--title", default="", help="Song title")
    parser.add_argument("--style", default="", help="Style/genre tags")
    parser.add_argument("--prompt", default="", help="Song description/lyrics")
    parser.add_argument("--instrumental", action="store_true", default=True)
    parser.add_argument("--no-instrumental", dest="instrumental", action="store_false")
    parser.add_argument("--world", metavar="N",
                        help="World number (1-6) or 'all'")
    parser.add_argument("--batch", action="store_true",
                        help="Generate all tracks for the given --world in one session")
    parser.add_argument("--shared", action="store_true",
                        help="Include shared tracks (victory, game_over, title)")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--explore", action="store_true",
                        help="Open browser for DOM exploration")
    parser.add_argument("--login", action="store_true",
                        help="Open browser for login, save session, exit")
    parser.add_argument("--headless", action="store_true",
                        help="Run headless (only works if no captcha)")
    parser.add_argument("--preview", action="store_true",
                        help="Play each result with mpv")
    parser.add_argument("--timeout", type=int, default=300,
                        help="Max seconds to wait per track (default: 300)")
    parser.add_argument("--skip-existing", action="store_true",
                        help="Skip tracks already in manifest")

    args = parser.parse_args()

    # Validate args
    if not args.explore and not args.login and not args.batch and not args.shared:
        if not args.track_id:
            die("--track-id is required (or use --batch/--explore/--login)")

    # Launch browser
    print(f"Launching browser {'(headless)' if args.headless else ''}...")
    pw, ctx = launch_browser(headless=args.headless)
    page = ctx.pages[0] if ctx.pages else ctx.new_page()

    # Network interceptor for audio URLs
    audio_urls: list[str] = []

    def on_response(response):
        url = response.url
        ct = response.headers.get("content-type", "")
        if any(url.endswith(ext) for ext in (".png", ".jpg", ".jpeg", ".webp", ".svg", ".gif", ".ico", ".css", ".js")):
            return
        if "image/" in ct:
            return
        is_audio = any(ext in url for ext in (".mp3", ".wav", ".m4a", ".ogg")) or "audio" in ct
        if is_audio and response.status == 200 and url not in audio_urls and "sil-" not in url:
            audio_urls.append(url)
            print(f"  [network] Audio: {url[:80]}...")
        if "application/json" in ct and response.status == 200:
            try:
                body = response.text()
                for pattern in (r'"audio_url"\s*:\s*"(https://[^"]+\.mp3[^"]*)"',
                                r'"song_path"\s*:\s*"(https://[^"]+)"',
                                r'"audio"\s*:\s*"(https://[^"]+\.mp3[^"]*)"',
                                r'"(https://cdn[^"]*suno[^"]*\.mp3[^"]*)"'):
                    for match in re.finditer(pattern, body):
                        found = match.group(1)
                        if found not in audio_urls and "sil-" not in found:
                            audio_urls.append(found)
                            print(f"  [api] Audio URL: {found[:80]}...")
            except Exception:
                pass

    page.on("response", on_response)

    try:
        # Always inject cookies from env (restores session without login)
        inject_cookies(ctx)
        # Also inject Clerk __client cookie for auth.suno.com
        clerk_client = os.environ.get("CLERK_CLIENT", "").strip()
        if clerk_client:
            ctx.add_cookies([{
                "name": "__client", "value": clerk_client,
                "domain": "auth.suno.com", "path": "/",
                "httpOnly": True, "secure": True, "sameSite": "None",
            }])
            print("Injected Clerk __client cookie.")

        if args.headless:
            pass  # cookies already injected above

        if args.login:
            ensure_logged_in(page, headless=False)
            save_session_cookies(ctx)
            print("Login complete. Session cached.")
            return

        if args.explore:
            explore_mode(page, headless=args.headless)
            return

        ensure_logged_in(page, headless=args.headless)

        # Build track queue
        if args.batch or args.shared:
            world_arg = args.world if args.batch else None
            queue = build_batch_queue(world_arg, args.shared)

            if args.skip_existing:
                manifest = load_manifest()
                existing = set(manifest.get("tracks", {}).keys())
                before = len(queue)
                queue = [t for t in queue if t["track_id"] not in existing]
                skipped = before - len(queue)
                if skipped:
                    print(f"Skipping {skipped} existing tracks.")

            if not queue:
                print("No tracks to generate.")
                return

            print(f"\nBatch queue: {len(queue)} tracks")
            for i, t in enumerate(queue, 1):
                print(f"  {i:2d}. {t['track_id']:30s} {t['title']}")
            print()

            succeeded = 0
            failed = []
            for i, track in enumerate(queue, 1):
                print(f"\n[{i}/{len(queue)}] Starting {track['track_id']}...")
                ok = generate_one_track(
                    page, audio_urls,
                    track_id=track["track_id"],
                    title=track["title"],
                    style=track["style"],
                    prompt=track["prompt"],
                    instrumental=args.instrumental,
                    output_dir=args.output_dir,
                    timeout_sec=args.timeout,
                    preview=args.preview,
                )
                if ok:
                    succeeded += 1
                else:
                    failed.append(track["track_id"])

            print(f"\n{'=' * 60}")
            print(f"  BATCH COMPLETE: {succeeded}/{len(queue)} succeeded")
            if failed:
                print(f"  Failed: {', '.join(failed)}")
            print(f"{'=' * 60}")

        else:
            # Single track mode
            world = int(args.world) if args.world else None
            title = args.title
            style = args.style
            prompt = args.prompt

            if world is not None:
                template = load_world_template(world, args.track_id)
                if not title:
                    title = template.get("title", "")
                if not style:
                    style = template.get("style", "")
                if not prompt:
                    prompt = template.get("prompt", "")

            if not prompt:
                die("--prompt is required (or use --world)")

            generate_one_track(
                page, audio_urls,
                track_id=args.track_id,
                title=title,
                style=style,
                prompt=prompt,
                instrumental=args.instrumental,
                output_dir=args.output_dir,
                timeout_sec=args.timeout,
                preview=args.preview,
            )

    finally:
        try:
            ctx.close()
        except Exception:
            pass
        try:
            pw.stop()
        except Exception:
            pass

    print("Done.")


if __name__ == "__main__":
    main()
