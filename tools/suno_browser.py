# /// script
# requires-python = ">=3.10"
# dependencies = ["playwright", "requests"]
# ///
"""
suno_browser.py — Generate music on suno.com via Playwright browser automation.

Drives the Suno web UI directly — no API needed. Uses a persistent browser
profile so you only need to log in once.

Usage:
    uv run tools/suno_browser.py \
        --prompt "Peaceful medieval JRPG overworld theme" \
        --style "16-bit SNES orchestral, harp, strings" \
        --title "The Realm Awakens" \
        --instrumental

    # With world template:
    uv run tools/suno_browser.py --world 1 --track-id overworld_medieval

    # Just open the browser for manual exploration:
    uv run tools/suno_browser.py --explore

First run:
    playwright install chromium
"""

from __future__ import annotations

import argparse
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


def load_world_template(world: int, track_id: str) -> dict:
    if not PROMPTS_PATH.exists():
        die(f"music_prompts.json not found at {PROMPTS_PATH}")
    with PROMPTS_PATH.open() as fh:
        prompts = json.load(fh)
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


def launch_browser(headless: bool = False) -> tuple:
    """Launch persistent Chromium context. Returns (playwright, context).

    For headless mode, always uses the full (headed) chromium binary — never
    the headless shell or --headless=new, since Suno's hCaptcha blocks
    anything that identifies as headless.  Combine with xvfb-run for a
    truly invisible window.
    """
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    pw = sync_playwright().start()
    ctx = pw.chromium.launch_persistent_context(
        str(PROFILE_DIR),
        headless=False,  # Always use full browser (hCaptcha blocks headless)
        viewport={"width": 1400, "height": 900},
        timeout=60000,
    )
    return pw, ctx


def save_session_cookies(ctx: BrowserContext) -> None:
    """Extract session cookies from browser and save to setenv.sh."""
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
                content,
                flags=re.MULTILINE,
            )
        else:
            content = content.rstrip() + f'\nexport SUNO_COOKIE="{cookie_str}"\n'
        setenv_path.write_text(content)
    print(f"Saved {len(relevant)} cookies to {setenv_path}")


def inject_cookies(ctx: BrowserContext) -> bool:
    """Inject SUNO_COOKIE from env into the browser context. Returns True if cookies were injected."""
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
            "name": name.strip(),
            "value": value.strip(),
            "domain": ".suno.com",
            "path": "/",
            "httpOnly": False,
            "secure": True,
            "sameSite": "Lax",
        })

    if cookies:
        ctx.add_cookies(cookies)
        print(f"Injected {len(cookies)} cookies from SUNO_COOKIE env var.")
        return True
    return False


def ensure_logged_in(page: Page, headless: bool = False) -> None:
    """Check if logged in, wait for login if not."""
    page.goto(SUNO_CREATE_URL, wait_until="domcontentloaded")
    # Give the SPA time to hydrate
    page.wait_for_timeout(4000)

    max_attempts = 12 if headless else 60  # 1 min headless, 5 min headed
    for attempt in range(max_attempts):
        url = page.url
        # If we're on the create page, check for the prompt input
        if "/create" in url:
            prompt_area = page.locator("textarea").first
            try:
                prompt_area.wait_for(timeout=3000)
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
        # Take a screenshot before dying so we can debug
        screenshot_path = PROJECT_ROOT / "tmp" / "suno_login_fail.png"
        screenshot_path.parent.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=str(screenshot_path))
        die(f"Login failed in headless mode. Refresh cookie with: uv run tools/suno_cookie.py\n"
            f"Screenshot: {screenshot_path}")
    else:
        die("Timed out waiting for login.")


def enable_advanced_mode(page: Page) -> None:
    """Switch to Advanced mode (was 'Custom' in old UI)."""
    adv_btn = page.locator("button").filter(has_text=re.compile(r"^Advanced$"))
    try:
        adv_btn.first.wait_for(timeout=5000)
        adv_btn.first.click()
        page.wait_for_timeout(500)
        print("Advanced mode enabled.")
    except PwTimeout:
        print("Warning: Could not find Advanced button — may already be in advanced mode.")


def fill_form(page: Page, title: str, style: str, prompt: str, instrumental: bool = True) -> None:
    """Fill in the Advanced mode creation form.

    Suno Advanced mode (as of 2026-03) has:
      - textarea[0]: lyrics (placeholder ~'Write some lyrics or a prompt')
      - textarea[1]: style tags (placeholder varies with examples)
      - input 'Song Title (Optional)': title
    For instrumental, leave lyrics blank.
    """
    page.wait_for_timeout(500)

    # Lyrics / prompt textarea — first textarea with the lyrics placeholder
    lyrics_ta = page.locator("textarea").filter(
        has=page.locator(":scope")  # match all
    ).first
    if instrumental:
        # Leave blank for instrumental
        lyrics_ta.fill("")
        print("Lyrics left blank (instrumental).")
    else:
        lyrics_ta.fill(prompt)
        print(f"Filled lyrics textarea.")

    # Style textarea — second textarea (index 1)
    style_ta = page.locator("textarea").nth(1)
    try:
        style_ta.wait_for(timeout=3000)
        style_ta.fill(style)
        print(f"Filled style textarea: {style[:60]}...")
    except PwTimeout:
        print("Warning: Could not find style textarea.")

    # Title input — try multiple selectors since Suno's placeholder text varies
    title_filled = False
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
            title_filled = True
            break
        except Exception:
            continue
    if not title_filled:
        print("Warning: Could not find title input — title skipped.")

    page.wait_for_timeout(500)


def click_create(page: Page) -> None:
    """Click the big orange Create button at the bottom of the form."""
    # Multiple elements contain "Create" text (sidebar nav, form button).
    # The form submit button is the LAST visible one and is a large styled button.
    create_btn = page.locator("button").filter(has_text=re.compile(r"Create"))
    visible_creates = []
    for i in range(create_btn.count()):
        btn = create_btn.nth(i)
        if btn.is_visible():
            visible_creates.append(btn)

    if not visible_creates:
        # Take screenshot for debug
        ss = PROJECT_ROOT / "tmp" / "suno_no_create_btn.png"
        ss.parent.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=str(ss))
        die(f"Could not find Create button. Screenshot: {ss}")

    # Click the LAST visible Create button (the form submit at the bottom)
    target = visible_creates[-1]
    target.scroll_into_view_if_needed()
    page.wait_for_timeout(300)
    target.click()
    print(f"Clicked Create button (matched {len(visible_creates)} visible, picked last).")


def wait_for_song(page: Page, timeout_sec: int = 300) -> str | None:
    """Wait for a generated song to appear and return its audio URL."""
    print(f"Waiting for generation (up to {timeout_sec}s)...")
    deadline = time.monotonic() + timeout_sec

    # Watch for new audio elements or download links appearing
    initial_audio_count = page.locator("audio source, audio[src]").count()

    while time.monotonic() < deadline:
        page.wait_for_timeout(5000)
        elapsed = int(time.monotonic() - (deadline - timeout_sec))
        print(f"  Waiting ({elapsed}s)...")

        # Check for new audio elements
        current_audio = page.locator("audio source, audio[src]")
        if current_audio.count() > initial_audio_count:
            # New audio appeared — get the URL
            for i in range(current_audio.count() - 1, -1, -1):
                src = current_audio.nth(i).get_attribute("src")
                if src and src.startswith("http"):
                    print(f"  Audio URL found!")
                    return src

        # Also check for download buttons/links on newly generated songs
        # Suno shows songs in a list — look for the most recent one
        download_links = page.locator("a[href*='.mp3'], a[href*='cdn'], a[download]")
        if download_links.count() > 0:
            href = download_links.last.get_attribute("href")
            if href:
                print(f"  Download link found!")
                return href

        # Check network requests for audio URLs
        # (handled via page.on("response") if needed)

    print("  Timed out waiting for song generation.")
    return None


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


def explore_mode(page: Page, headless: bool = False) -> None:
    """Print DOM element info from the create page to help build selectors."""
    ensure_logged_in(page, headless=headless)
    print("\n" + "=" * 60)
    print("  EXPLORE MODE — scanning DOM for form elements")
    print("=" * 60 + "\n")

    # Print what we can see
    page.wait_for_timeout(2000)
    print("--- Textareas ---")
    for i in range(page.locator("textarea").count()):
        ta = page.locator("textarea").nth(i)
        print(f"  [{i}] placeholder={ta.get_attribute('placeholder')!r} "
              f"name={ta.get_attribute('name')!r} "
              f"id={ta.get_attribute('id')!r}")

    print("\n--- Text Inputs ---")
    for i in range(page.locator("input[type='text'], input:not([type])").count()):
        inp = page.locator("input[type='text'], input:not([type])").nth(i)
        print(f"  [{i}] placeholder={inp.get_attribute('placeholder')!r} "
              f"name={inp.get_attribute('name')!r} "
              f"id={inp.get_attribute('id')!r}")

    print("\n--- Buttons ---")
    for i in range(min(page.locator("button").count(), 20)):
        btn = page.locator("button").nth(i)
        text = btn.inner_text()[:50] if btn.is_visible() else "(hidden)"
        print(f"  [{i}] text={text!r} "
              f"aria-label={btn.get_attribute('aria-label')!r}")

    print("\n--- Switches/Toggles ---")
    for i in range(page.locator("[role='switch']").count()):
        sw = page.locator("[role='switch']").nth(i)
        print(f"  [{i}] checked={sw.get_attribute('aria-checked')!r} "
              f"text={sw.inner_text()[:30]!r}")

    print("\nDone. DOM snapshot printed above.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Cowardly Irregular music via Suno web UI automation",
    )
    parser.add_argument("--track-id", metavar="ID",
                        help="Track ID for music_manifest.json")
    parser.add_argument("--title", default="", help="Song title")
    parser.add_argument("--style", default="", help="Style/genre tags")
    parser.add_argument("--prompt", default="", help="Song description/lyrics")
    parser.add_argument("--instrumental", action="store_true", default=True)
    parser.add_argument("--no-instrumental", dest="instrumental", action="store_false")
    parser.add_argument("--world", type=int, metavar="N",
                        help="Load template from music_prompts.json (1-6)")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--explore", action="store_true",
                        help="Open browser for manual exploration (prints DOM info)")
    parser.add_argument("--login", action="store_true",
                        help="Open headed browser for login, save session, then exit")
    parser.add_argument("--headless", action="store_true",
                        help="Run browser in headless mode (no visible window)")
    parser.add_argument("--preview", action="store_true",
                        help="Play result with mpv")
    parser.add_argument("--timeout", type=int, default=300,
                        help="Max seconds to wait for generation (default: 300)")

    args = parser.parse_args()

    # Resolve template
    title = args.title
    style = args.style
    prompt = args.prompt

    if args.world is not None:
        track_id = args.track_id or f"world{args.world}_track"
        template = load_world_template(args.world, track_id)
        if not title:
            title = template.get("title", "")
        if not style:
            style = template.get("style", "")
        if not prompt:
            prompt = template.get("prompt", "")

    if not args.explore and not args.login:
        if not args.track_id:
            die("--track-id is required (or use --explore)")
        if not prompt:
            die("--prompt is required (or use --world)")

    # Launch browser
    print(f"Launching browser {'(headless)' if args.headless else ''}...")
    pw, ctx = launch_browser(headless=args.headless)
    page = ctx.pages[0] if ctx.pages else ctx.new_page()

    # Capture audio URLs from network traffic (both direct audio + JSON API responses)
    audio_urls: list[str] = []

    def on_response(response):
        url = response.url
        ct = response.headers.get("content-type", "")

        # Skip images and static assets
        if any(url.endswith(ext) for ext in (".png", ".jpg", ".jpeg", ".webp", ".svg", ".gif", ".ico", ".css", ".js")):
            return
        if "image/" in ct:
            return

        # Catch direct audio file downloads
        is_audio_url = any(ext in url for ext in (".mp3", ".wav", ".m4a", ".ogg"))
        is_audio_ct = "audio" in ct
        if (is_audio_url or is_audio_ct) and response.status == 200:
            if url not in audio_urls and "sil-" not in url:
                audio_urls.append(url)
                print(f"  [network] Audio file: {url[:80]}...")

        # Intercept JSON API responses that contain audio_url fields
        if "application/json" in ct and response.status == 200:
            try:
                body = response.text()
                # Look for audio URL patterns in JSON responses
                for pattern in (r'"audio_url"\s*:\s*"(https://[^"]+\.mp3[^"]*)"',
                                r'"song_path"\s*:\s*"(https://[^"]+)"',
                                r'"audio"\s*:\s*"(https://[^"]+\.mp3[^"]*)"',
                                r'"(https://cdn[^"]*suno[^"]*\.mp3[^"]*)"'):
                    for match in re.finditer(pattern, body):
                        found_url = match.group(1)
                        if found_url not in audio_urls and "sil-" not in found_url:
                            audio_urls.append(found_url)
                            print(f"  [api] Audio URL from JSON: {found_url[:80]}...")
            except Exception:
                pass  # Some responses may not be readable

    page.on("response", on_response)

    try:
        # In headless mode, inject cookies from env for auth
        if args.headless:
            if not inject_cookies(ctx):
                print("Warning: No SUNO_COOKIE env var. Run: source setenv.sh")

        if args.login:
            # Headed login only — save session to persistent profile + setenv.sh
            ensure_logged_in(page, headless=False)
            save_session_cookies(ctx)
            print("Login complete. Session cached in browser profile.")
            print("You can now use --headless for automated generation.")
            return

        if args.explore:
            explore_mode(page, headless=args.headless)
            return

        ensure_logged_in(page, headless=args.headless)
        enable_advanced_mode(page)
        fill_form(page, title, style, prompt, instrumental=args.instrumental)

        # Snapshot ALL audio element sources before clicking create
        pre_create_urls = set(audio_urls)
        pre_dom_srcs = set()
        for el in [page.locator("audio source"), page.locator("audio[src]")]:
            for i in range(el.count()):
                src = el.nth(i).get_attribute("src")
                if src:
                    pre_dom_srcs.add(src)
        print(f"Pre-create: {len(pre_dom_srcs)} existing audio sources in DOM")

        click_create(page)
        captcha_prompted = False

        # Wait for audio to appear (network interception or DOM)
        print(f"\nWaiting for generation (up to {args.timeout}s)...")
        deadline = time.monotonic() + args.timeout
        audio_url = None

        while time.monotonic() < deadline:
            page.wait_for_timeout(5000)
            elapsed = int(time.monotonic() - (deadline - args.timeout))

            # Check for hCaptcha challenge iframe
            captcha_frame = page.locator("iframe[title*='hCaptcha'], iframe[src*='hcaptcha']")
            if captcha_frame.count() > 0 and not captcha_prompted:
                captcha_prompted = True
                print("\n" + "=" * 60)
                print("  hCAPTCHA DETECTED — please solve it in the browser window")
                print("=" * 60 + "\n")
            elif captcha_prompted and captcha_frame.count() == 0:
                # Captcha was solved (iframe gone)
                print("  Captcha solved! Resuming wait for generation...")
                captcha_prompted = False  # Reset in case another appears

            # Check network-intercepted audio URLs
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

        # If no audio via interception, try navigating to library
        if not audio_url:
            print("  No audio from create page. Checking library...")
            page.goto("https://suno.com/me", wait_until="domcontentloaded")
            page.wait_for_timeout(5000)

            # Reset filters and look for songs
            reset_btn = page.locator("button:has-text('Reset filters')")
            if reset_btn.count() > 0:
                try:
                    reset_btn.first.click(timeout=3000)
                    page.wait_for_timeout(2000)
                except PwTimeout:
                    pass

            # Try clicking a play button to trigger audio load
            play_btns = page.locator("button[aria-label*='Play'], button[aria-label*='play']")
            if play_btns.count() > 0:
                play_btns.first.click()
                page.wait_for_timeout(5000)

            new_urls = [u for u in audio_urls if u not in pre_create_urls]
            if new_urls:
                audio_url = new_urls[-1]
                print(f"  Audio from library!")

        if not audio_url:
            # Last resort — screenshot and let user see what happened
            screenshot_path = PROJECT_ROOT / "tmp" / "suno_timeout.png"
            screenshot_path.parent.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(screenshot_path))
            die(f"No audio URL found after {args.timeout}s. Screenshot: {screenshot_path}")

        # Download and convert
        track_key = args.track_id
        ext = Path(urlparse(audio_url).path).suffix or ".mp3"
        raw_path = args.output_dir / f"{track_key}{ext}"
        ogg_path = args.output_dir / f"{track_key}.ogg"

        download_from_url(audio_url, raw_path)
        convert_to_ogg(raw_path, ogg_path)

        duration = probe_duration(ogg_path)
        raw_path.unlink(missing_ok=True)

        # Update manifest
        manifest = load_manifest()
        if "tracks" not in manifest:
            manifest["tracks"] = {}
        rel_path = ogg_path.relative_to(PROJECT_ROOT)
        manifest["tracks"][track_key] = {
            "file": str(rel_path),
            "tier": "T1",
            "provider": "suno_browser",
            "title": title,
            "prompt": prompt,
            "style": style,
            "model": "suno-web",
            "duration": round(duration, 2),
            "loop": True,
            "generated_at": date.today().isoformat(),
        }
        save_manifest(manifest)

        print(f"\nTrack ready: {ogg_path}")

        if args.preview:
            subprocess.run(["mpv", "--no-video", str(ogg_path)])

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
