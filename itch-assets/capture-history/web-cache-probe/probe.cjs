const { chromium } = require('playwright');
(async () => {
  const [port, profile, label] = process.argv.slice(2);
  const ctx = await chromium.launchPersistentContext(profile, {
    headless: true, args: ['--enable-unsafe-swiftshader','--use-gl=swiftshader','--no-sandbox'] });
  const url = `http://127.0.0.1:${port}/index.html`;
  const lines = [];
  for (const visit of [1, 2]) {
    const page = await ctx.newPage();
    let payload = null, controlled = null;
    page.on('console', (m) => { const t = m.text(); if (t.startsWith('[shell] payload')) payload = t; });
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 180000 });
    const t0 = Date.now();
    while (payload === null && Date.now() - t0 < 180000) await page.waitForTimeout(500);
    try { controlled = await page.evaluate(() => !!navigator.serviceWorker.controller); } catch (e) {}
    lines.push(`  ${label} visit${visit} controlled=${controlled} :: ${payload ? payload.replace('[shell] payload ','') : 'NO PAYLOAD LINE'}`);
    await page.close();
    await ctx.pages().length;
  }
  console.log(lines.join('\n'));
  await ctx.close();
})();
