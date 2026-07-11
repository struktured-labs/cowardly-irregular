// Web-boot smoke: executes the ACTUAL WASM build in headless chromium.
// PASS = the Godot engine banner appears in console within the budget and
// no page error / fatal console error fires. Screenshot always saved.
// Usage: node tools/web_smoke.mjs [url] (default http://127.0.0.1:8371)
// playwright is imported from an absolute path (PW_MODULE) so no project-local
// install is needed — ESM ignores NODE_PATH, so the runner passes a file:// URL.
const pwModule = process.env.PW_MODULE || 'playwright';
const { chromium } = await import(pwModule);

const url = process.argv[2] || 'http://127.0.0.1:8371';
const BOOT_BUDGET_MS = 45000;
const FATAL = /RuntimeError|abort\(|out of memory|failed to (load|instantiate|fetch)|wasm.*error|Unable to load/i;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
let booted = false;
let saved = false;
let loaded = false;
const errors = [];
page.on('console', (msg) => {
  const t = msg.text();
  if (t.includes('Godot Engine v')) booted = true;
  if (t.includes('Game saved to slot')) saved = true;
  if (t.includes('Game loaded from slot')) loaded = true;
  if (msg.type() === 'error' && FATAL.test(t)) errors.push('console: ' + t.slice(0, 300));
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
if (booted && errors.length === 0) {
  await page.keyboard.press('Escape');
  await page.waitForTimeout(2500);
  await page.screenshot({ path: 'tmp/web_smoke_menu.png' });
}

// Stage 4: save → reload → Continue. THE web-only stakes path: user:// on
// web is IndexedDB with async flush — if the flush never lands, players
// lose their saves on tab close and no desktop test can catch it.
// Menu is open from stage 3 with the cursor on row 0; Save is row 15.
if (booted && errors.length === 0) {
  for (let i = 0; i < 15; i++) {
    await page.keyboard.press('ArrowDown');
    await page.waitForTimeout(120);
  }
  await page.keyboard.press('Enter');        // open the save screen
  await page.waitForTimeout(1500);
  await page.keyboard.press('Enter');        // save to slot 1 (empty, no confirm)
  await page.waitForTimeout(4000);           // write + IndexedDB syncfs window
  await page.screenshot({ path: 'tmp/web_smoke_save.png' });
  if (!saved) errors.push('stage4: no "Game saved to slot" console line — menu row order changed or save was refused');
}
if (booted && errors.length === 0 && saved) {
  booted = false;
  await page.reload({ waitUntil: 'domcontentloaded' });
  const t0 = Date.now();
  while (!booted && errors.length === 0 && Date.now() - t0 < BOOT_BUDGET_MS) {
    await page.waitForTimeout(500);
  }
  if (booted) {
    await page.waitForTimeout(5000);
    await page.keyboard.press('Enter');      // Press Start
    await page.waitForTimeout(2000);
    await page.keyboard.press('Enter');      // first row = Continue when a save exists
    await page.waitForTimeout(9000);
    await page.screenshot({ path: 'tmp/web_smoke_resume.png' });
    if (!loaded) errors.push('stage4: save did NOT survive the page reload (no "Game loaded from slot" after Continue) — IndexedDB persistence is broken');
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
console.log('[WEB-SMOKE] PASS — boot + gameplay + menu + save/reload/continue, no fatals (tmp/web_smoke{,_ingame,_menu,_save,_resume}.png)');
