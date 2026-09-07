# /// script
# requires-python = ">=3.10"
# dependencies = ["patchright", "requests"]
# ///
"""Enumerate Suno create-page textareas: placeholders, IDs, sizes, visibility.

Goal: figure out which index is lyrics vs style in the current UI layout.
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from tools.suno_api import SunoBrowser, SUNO_CREATE_URL, PROJECT_ROOT

b = SunoBrowser(headless=True)
try:
    b.start()
    page = b._page
    print(f"URL: {page.url}")

    # Click Advanced if present so lyrics + style are revealed
    import re
    try:
        adv = page.locator("button").filter(has_text=re.compile(r"^Advanced$"))
        if adv.count() > 0:
            adv.first.click()
            page.wait_for_timeout(1500)
            print("Clicked Advanced")
    except Exception as e:
        print(f"Advanced click failed: {e}")

    ta_count = page.locator("textarea").count()
    print(f"\nTextarea count: {ta_count}")
    for i in range(ta_count):
        el = page.locator("textarea").nth(i)
        info = page.evaluate("""(idx) => {
            const el = document.querySelectorAll('textarea')[idx];
            if (!el) return null;
            const rect = el.getBoundingClientRect();
            return {
                placeholder: el.placeholder,
                name: el.name,
                id: el.id,
                ariaLabel: el.getAttribute('aria-label'),
                dataTestId: el.getAttribute('data-testid'),
                className: el.className.slice(0, 120),
                width: Math.round(rect.width),
                height: Math.round(rect.height),
                top: Math.round(rect.top),
                visible: rect.width > 0 && rect.height > 0,
                disabled: el.disabled,
                value: el.value.slice(0, 80),
            };
        }""", i)
        print(f"\n  [{i}] {info}")

    # Also inspect inputs
    inp_count = page.locator("input[type='text']").count()
    print(f"\nText input count: {inp_count}")
    for i in range(inp_count):
        info = page.evaluate("""(idx) => {
            const el = document.querySelectorAll("input[type='text']")[idx];
            if (!el) return null;
            return {placeholder: el.placeholder, name: el.name, id: el.id, ariaLabel: el.getAttribute('aria-label')};
        }""", i)
        print(f"  input [{i}] {info}")

    # Screenshot
    ss = PROJECT_ROOT / "tmp" / "diag_textareas.png"
    ss.parent.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(ss), full_page=True)
    print(f"\nScreenshot: {ss}")

finally:
    b.close()
