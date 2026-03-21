# /// script
# requires-python = ">=3.10"
# dependencies = ["playwright"]
# ///
"""
suno_cookie.py — Extract Suno session cookie via browser login.

Opens a Chromium window to suno.com. Log in normally (Google, email, etc.)
Once logged in, the script automatically extracts the session cookie and
saves it to setenv.sh as SUNO_COOKIE.

Usage:
    uv run tools/suno_cookie.py

First run requires:
    playwright install chromium
"""

from __future__ import annotations

import re
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SETENV_PATH = PROJECT_ROOT / "setenv.sh"


def save_cookie(cookie_value: str) -> None:
    """Append or update SUNO_COOKIE in setenv.sh."""
    if SETENV_PATH.exists():
        content = SETENV_PATH.read_text()
    else:
        content = "#!/usr/bin/env bash\n# Project environment variables — NEVER committed to git\n\n"

    # Replace existing or append
    if "SUNO_COOKIE=" in content:
        content = re.sub(
            r'^export SUNO_COOKIE=.*$',
            f'export SUNO_COOKIE="{cookie_value}"',
            content,
            flags=re.MULTILINE,
        )
    else:
        content = content.rstrip() + f'\n\n# Suno session cookie (auto-extracted by suno_cookie.py)\nexport SUNO_COOKIE="{cookie_value}"\n'

    SETENV_PATH.write_text(content)
    print(f"\nCookie saved to {SETENV_PATH}")


def extract_cookie() -> None:
    with sync_playwright() as p:
        # Use persistent context so login state is cached between runs
        user_data_dir = PROJECT_ROOT / "tmp" / "suno-browser-profile"
        user_data_dir.mkdir(parents=True, exist_ok=True)

        browser = p.chromium.launch_persistent_context(
            str(user_data_dir),
            headless=False,
            viewport={"width": 1280, "height": 800},
        )
        page = browser.pages[0] if browser.pages else browser.new_page()
        page.goto("https://suno.com")

        print("=" * 60)
        print("  Log into Suno in the browser window that just opened.")
        print("  Once you're on the main Suno page (logged in),")
        print("  this script will auto-detect your session and save it.")
        print("=" * 60)

        # Poll for the session cookie
        max_wait = 300  # 5 minutes to log in
        start = time.monotonic()

        while time.monotonic() - start < max_wait:
            cookies = browser.cookies("https://suno.com")

            # Look for Clerk session token
            for c in cookies:
                if c["name"] == "__client":
                    cookie_str = f"__client={c['value']}"
                    print(f"\nSession cookie found!")
                    save_cookie(cookie_str)
                    browser.close()
                    print("Browser closed. You're all set.")
                    print(f"\nTest with:  source setenv.sh && echo $SUNO_COOKIE")
                    return

            # Also check for __session or __clerk_db_jwt
            for c in cookies:
                if c["name"] in ("__session", "__clerk_db_jwt"):
                    # Build a full cookie string from all relevant cookies
                    relevant = {c2["name"]: c2["value"] for c2 in cookies
                                if c2["name"].startswith("__")}
                    cookie_str = "; ".join(f"{k}={v}" for k, v in relevant.items())
                    print(f"\nSession cookies found! ({len(relevant)} cookies)")
                    save_cookie(cookie_str)
                    browser.close()
                    print("Browser closed. You're all set.")
                    print(f"\nTest with:  source setenv.sh && echo $SUNO_COOKIE")
                    return

            time.sleep(2)

        print("\nTimed out waiting for login. Try again.", file=sys.stderr)
        browser.close()
        sys.exit(1)


def main() -> None:
    # Check if playwright browsers are installed
    try:
        extract_cookie()
    except Exception as e:
        if "Executable doesn't exist" in str(e) or "browserType.launch" in str(e):
            print("Playwright browsers not installed. Installing Chromium...")
            import subprocess
            subprocess.run([sys.executable, "-m", "playwright", "install", "chromium"],
                           check=True)
            extract_cookie()
        else:
            raise


if __name__ == "__main__":
    main()
