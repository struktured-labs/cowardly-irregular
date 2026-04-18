# /// script
# requires-python = ">=3.10"
# dependencies = ["patchright", "requests"]
# ///
"""Verify updated _fill_form logic selects correct visible textareas.

Does NOT click Create — safe to run during captcha cooldown.
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from tools.suno_api import SunoBrowser, PROJECT_ROOT

b = SunoBrowser(headless=True)
try:
    b.start()
    page = b._page
    print(f"URL: {page.url}")

    b._fill_form("Verify Test", "DIAG SENTINEL test style keyword", instrumental=True)

    # Inspect textareas post-fill
    print("\n--- Post-fill textarea values ---")
    for i in range(page.locator("textarea").count()):
        info = page.evaluate("""(idx) => {
            const el = document.querySelectorAll('textarea')[idx];
            if (!el) return null;
            const r = el.getBoundingClientRect();
            return {
                placeholder: el.placeholder,
                value: el.value.slice(0, 100),
                visible: r.width > 0 && r.height > 0,
                top: Math.round(r.top),
            };
        }""", i)
        print(f"  [{i}] visible={info['visible']}, top={info['top']}, ph='{info['placeholder'][:50]}', value='{info['value'][:50]}'")

    ss = PROJECT_ROOT / "tmp" / "verify_fill.png"
    page.screenshot(path=str(ss))
    print(f"\nScreenshot: {ss}")
finally:
    b.close()
