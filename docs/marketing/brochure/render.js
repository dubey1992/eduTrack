// Renders the brochure and the one-pager to A4 PDFs (docs/marketing/brochure).
//   NODE_PATH="$(npm root -g)" node render.js <output folder>
// Needs Playwright's Chromium; the pages load Poppins from Google Fonts.
const { chromium } = require('playwright');
const path = require('path');

const out = process.argv[2] || __dirname;
const CHROMIUM = 'C:/Users/abhis/AppData/Local/ms-playwright/chromium-1228/chrome-win64/chrome.exe';

(async () => {
  const browser = await chromium.launch({ executablePath: CHROMIUM });
  for (const [page, pdf] of [['brochure.html', 'School365ai-Brochure.pdf'], ['one-pager.html', 'School365ai-One-Pager.pdf']]) {
    const tab = await browser.newPage();
    await tab.goto('file:///' + path.join(__dirname, page).replace(/\\/g, '/'), { waitUntil: 'networkidle' });
    await tab.evaluate(() => document.fonts.ready);
    await tab.pdf({ path: path.join(out, pdf), preferCSSPageSize: true, printBackground: true });
    console.log('wrote', pdf);
    await tab.close();
  }
  await browser.close();
})();
