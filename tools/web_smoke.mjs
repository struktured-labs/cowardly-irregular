// Web-boot smoke: executes the ACTUAL WASM build in headless chromium.
// PASS = the Godot engine banner appears in console within the budget and
// no page error / fatal console error fires. Screenshot always saved.
// Usage: node tools/web_smoke.mjs [url] (default http://127.0.0.1:8371)
// playwright is imported from an absolute path (PW_MODULE) so no project-local
// install is needed — ESM ignores NODE_PATH, so the runner passes a file:// URL.
const pwModule = process.env.PW_MODULE || 'playwright';
const { chromium } = await import(pwModule);
const { readFileSync } = await import('node:fs');

// Save's row index is DERIVED from OverworldMenu.gd, not hardcoded. It was 15,
// then the Lens screen (3a3e2d13, 2026-07-27) inserted a row at 7 and pushed Save
// to 16 — every deploy since was BLOCKED at stage 4, landing on World Map, and
// nobody saw it because nobody deployed. A literal row number is a coincidental
// value: it goes red on a correct change and teaches you to bump the number.
function saveRowIndex() {
  const src = readFileSync(new URL('../src/ui/OverworldMenu.gd', import.meta.url), 'utf8');
  const ids = [...src.matchAll(/\{"id":\s*"([a-z_0-9]+)",\s*"label":/g)].map((m) => m[1]);
  const i = ids.indexOf('save');
  if (ids.length < 10 || i < 0) {
    throw new Error(`web_smoke: could not derive the Save row from OverworldMenu.gd `
      + `(parsed ${ids.length} rows, save at ${i}) — the row-list shape changed; `
      + `fix this parse rather than reverting to a hardcoded index`);
  }
  return i;
}
const SAVE_ROW = saveRowIndex();

const url = process.argv[2] || 'http://127.0.0.1:8371';
const BOOT_BUDGET_MS = 45000;
// Resuming a save re-boots the engine AND loads game state, so it needs its own budget.
const LOAD_BUDGET_MS = Number(process.env.WEB_SMOKE_LOAD_BUDGET_MS || 45000);
const FATAL = /RuntimeError|abort\(|out of memory|failed to (load|instantiate|fetch)|wasm.*error|Unable to load/i;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
let booted = false;
let saved = false;
let loaded = false;
let menuOpened = false;
const errors = [];
// Non-fatal error budget: godot ERROR/SCRIPT ERROR lines that reach the JS
// console without matching FATAL. Not gating (variance), but the summary
// makes web-only error spam visible in every deploy log.
const softErrors = new Map();
page.on('console', (msg) => {
  const t = msg.text();
  if (t.includes('Godot Engine v')) booted = true;
  if (t.includes('Game saved to slot')) saved = true;
  if (t.includes('Game loaded from slot')) loaded = true;
  if (t.includes('[MENU] Overworld menu opened')) menuOpened = true;
  if (msg.type() === 'error' && FATAL.test(t)) errors.push('console: ' + t.slice(0, 300));
  else if (/ERROR|SCRIPT ERROR|WARNING/.test(t) && !/Godot Engine|Feature/.test(t)) {
    const key = t.slice(0, 120);
    softErrors.set(key, (softErrors.get(key) || 0) + 1);
  }
});
page.on('pageerror', (e) => errors.push('pageerror: ' + String(e).slice(0, 300)));

await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
const start = Date.now();
while (!booted && errors.length === 0 && Date.now() - start < BOOT_BUDGET_MS) {
  await page.waitForTimeout(500);
}
// settle a few seconds past boot so early-frame fatals surface
if (booted) await page.waitForTimeout(6000);
await page.screenshot({ path: 'tmp/web_smoke.png' });

// Stage 2: drive INTO the game — the web-only bug surface (IndexedDB saves,
// audio worklets, input pipeline) lives past the title screen. Fresh browser
// context has no saves, so Enter lands on NEW GAME; the prologue starts.
if (booted && errors.length === 0) {
  await page.keyboard.press('Enter');   // Press Start
  await page.waitForTimeout(2000);
  await page.keyboard.press('Enter');   // confirm first menu row (New Game)
  await page.waitForTimeout(12000);     // prologue cutscene / scene load
  await page.screenshot({ path: 'tmp/web_smoke_ingame.png' });
}

// Stage 3: open the overworld menu (Escape = ui_menu) — UI chrome is where
// theme fonts/symbols render, so this screenshot is the font-chain + menu
// layout regression surface. Escape (not Enter) so no NPC interaction fires.
// RETRY LOOP (v3.33.199 post-mortem): the fixed 12s prologue window busted as
// the pck grew — Escape landed mid-cutscene, did nothing, and stage 4's arrows
// walked the character into an encounter. Now we press Escape until the
// engine-side "[MENU] Overworld menu opened" line confirms, up to ~24s.
if (booted && errors.length === 0) {
  for (let tries = 0; tries < 12 && !menuOpened; tries++) {
    await page.keyboard.press('Escape');
    await page.waitForTimeout(2000);
  }
  await page.screenshot({ path: 'tmp/web_smoke_menu.png' });
  if (!menuOpened) errors.push('stage3: overworld menu never opened after 12 Escape retries — input locked, cutscene wedged, or menu print removed');
}

// Stage 4: save → reload → Continue. THE web-only stakes path: user:// on
// web is IndexedDB with async flush — if the flush never lands, players
// lose their saves on tab close and no desktop test can catch it.
// Menu is open from stage 3 with the cursor on row 0; Save's row is derived above.
if (booted && errors.length === 0) {
  console.log(`[WEB-SMOKE] Save is row ${SAVE_ROW} (derived from OverworldMenu.gd)`);
  for (let i = 0; i < SAVE_ROW; i++) {
    await page.keyboard.press('ArrowDown');
    await page.waitForTimeout(120);
  }
  await page.keyboard.press('Enter');        // open the save screen
  await page.waitForTimeout(1500);
  await page.keyboard.press('Enter');        // save to slot 1 (empty, no confirm)
  await page.waitForTimeout(4000);           // write + IndexedDB syncfs window
  await page.screenshot({ path: 'tmp/web_smoke_save.png' });
  if (!saved) errors.push(`stage4: no "Game saved to slot" console line after ${SAVE_ROW} ArrowDowns `
    + `(row derived from OverworldMenu.gd) — check tmp/web_smoke_save.png for which screen it landed on; `
    + `if that is not the save screen the row list and the cursor disagree, otherwise the save was refused`);
}
if (booted && errors.length === 0 && saved) {
  booted = false;
  await page.reload({ waitUntil: 'domcontentloaded' });
  const t0 = Date.now();
  while (!booted && errors.length === 0 && Date.now() - t0 < BOOT_BUDGET_MS) {
    await page.waitForTimeout(500);
  }
  if (booted) {
    // RETRY THE PRESSES, don't time them. These were two flat sleeps (5 s, then 2 s) and
    // the sequence is press-start THEN continue -- so if the title is not interactive at
    // 5 s, the first Enter is swallowed, the second one merely dismisses Press Start, and
    // Continue is never activated. Measured 2026-08-22: 3 failures in 5 runs at ~1.5
    // load/core, and tmp/web_smoke_resume.png showed the title screen with BOTH the menu
    // and the "PRESS START" overlay visible -- i.e. mid-transition, save intact,
    // "CONTINUE  Slot 1 - The Beginning - Overworld" rendered right there on screen.
    // The old failure text blamed "IndexedDB persistence is broken"; the screenshot
    // disproves that -- the save had persisted and been detected every time.
    // Pressing until the load actually happens is robust to however long boot takes.
    const tPress = Date.now();
    let presses = 0;
    while (!loaded && Date.now() - tPress < LOAD_BUDGET_MS) {
      await page.keyboard.press('Enter');
      presses++;
      await page.waitForTimeout(1500);
    }
    console.log('[WEB-SMOKE] resume took ' + presses + ' Enter press(es), '
      + (Date.now() - tPress) + 'ms');
    // POLL, don't sleep. This was a flat 9 s wait, which is a wall-clock guess about how
    // long a WASM load takes -- and on a loaded box it is wrong. Measured 2026-08-22 at
    // ~1.9 load/core (ffprobe + chrome-headless from other projects on this machine):
    // 3 FAILURES IN 5 RUNS, all of them this line, on a build whose save works fine.
    // The message asserted "IndexedDB persistence is broken", so the instrument's own
    // timeout budget was reported as a specific product defect -- and deploy_web.sh
    // retries only once, so a 60%-per-run failure rate blocks a legitimate deploy ~36%
    // of the time while naming the wrong cause.
    // The boot check 10 lines up already polls against BOOT_BUDGET_MS; this now matches it.
    const tLoad = Date.now();
    while (!loaded && Date.now() - tLoad < LOAD_BUDGET_MS) {
      await page.waitForTimeout(500);
    }
    const loadWaitMs = Date.now() - tLoad;
    await page.screenshot({ path: 'tmp/web_smoke_resume.png' });
    if (loaded) {
      console.log('[WEB-SMOKE] save resumed after ' + loadWaitMs + 'ms (budget ' + LOAD_BUDGET_MS + 'ms)');
    } else {
      errors.push('stage4: no "Game loaded from slot" after ' + presses + ' Enter press(es) over '
        + LOAD_BUDGET_MS + 'ms. Check tmp/web_smoke_resume.png: if it shows CONTINUE with a slot '
        + 'subtitle then the save DID persist and this is an input/transition problem, not '
        + 'IndexedDB.');
    }
  } else if (errors.length === 0) {
    errors.push('stage4: engine never re-booted after page reload');
  }
}
await browser.close();

if (errors.length) {
  console.log('[WEB-SMOKE] FAIL — ' + errors.length + ' fatal(s):');
  for (const e of errors) console.log('  ' + e);
  process.exit(1);
}
if (!booted) {
  console.log('[WEB-SMOKE] FAIL — engine banner never appeared within ' + BOOT_BUDGET_MS + 'ms');
  process.exit(2);
}
const softTotal = [...softErrors.values()].reduce((a, b) => a + b, 0);
if (softTotal > 0) {
  const top = [...softErrors.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3);
  console.log('[WEB-SMOKE] soft-error budget: ' + softTotal + ' non-fatal console error line(s), top offenders:');
  for (const [line, n] of top) console.log('[WEB-SMOKE]   ' + n + 'x ' + line);
} else {
  console.log('[WEB-SMOKE] soft-error budget: clean (0 non-fatal console errors)');
}
console.log('[WEB-SMOKE] PASS — boot + gameplay + menu + save/reload/continue, no fatals (tmp/web_smoke{,_ingame,_menu,_save,_resume}.png)');
