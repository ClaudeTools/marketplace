#!/usr/bin/env node
/**
 * Responsive screenshot engine — puppeteer-core based.
 * Handles: full-page scroll, sticky navs, animations, lazy images, cookie banners.
 *
 * Called by responsive-screenshots.sh wrapper (handles dependency install + Chrome detection).
 *
 * Env vars (set by wrapper):
 *   CHROME_PATH — path to Chrome/Chromium executable
 *   OUTPUT_DIR  — where to save screenshots
 *   DELAY       — seconds to wait before capture
 *   FULL_PAGE   — "true" for full page scroll capture
 *   URL         — the page to capture
 */

import puppeteer from 'puppeteer-core';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

const URL = process.env.URL;
const CHROME_PATH = process.env.CHROME_PATH;
const OUTPUT_DIR = process.env.OUTPUT_DIR || './screenshots';
const DELAY = parseInt(process.env.DELAY || '2', 10);
const FULL_PAGE = process.env.FULL_PAGE !== 'false';

const BREAKPOINTS = [
  { name: 'mobile', width: 390, height: 844, deviceScaleFactor: 3, isMobile: true, hasTouch: true },
  { name: 'tablet', width: 768, height: 1024, deviceScaleFactor: 2, isMobile: true, hasTouch: true },
  { name: 'desktop', width: 1440, height: 900, deviceScaleFactor: 1, isMobile: false, hasTouch: false },
  { name: 'wide', width: 1920, height: 1080, deviceScaleFactor: 1, isMobile: false, hasTouch: false },
];

async function preparePageForCapture(page) {
  // 1. Disable all animations and transitions
  await page.emulateMediaFeatures([
    { name: 'prefers-reduced-motion', value: 'reduce' },
  ]);

  await page.evaluate(() => {
    // Inject style to kill all motion
    const style = document.createElement('style');
    style.id = 'screenshot-freeze';
    style.textContent = `
      *, *::before, *::after {
        animation-duration: 0s !important;
        animation-delay: 0s !important;
        transition-duration: 0s !important;
        transition-delay: 0s !important;
        animation-iteration-count: 1 !important;
        scroll-behavior: auto !important;
      }
    `;
    document.head.appendChild(style);
  });

  // 2. Scroll through entire page to trigger lazy loading
  await page.evaluate(async () => {
    await new Promise((resolve) => {
      let totalHeight = 0;
      const distance = 400;
      const maxScroll = 50000; // Safety limit
      const timer = setInterval(() => {
        window.scrollBy(0, distance);
        totalHeight += distance;
        if (totalHeight >= document.body.scrollHeight || totalHeight >= maxScroll) {
          clearInterval(timer);
          // Scroll back to top
          window.scrollTo(0, 0);
          resolve();
        }
      }, 50);
    });
  });

  // 3. Wait for network to settle (lazy images loading)
  try {
    await page.waitForNetworkIdle({ idleTime: 500, timeout: 5000 });
  } catch {
    // Network didn't fully settle — continue anyway
  }

  // 4. Try to dismiss common cookie banners
  await page.evaluate(() => {
    const selectors = [
      // Common cookie consent selectors
      '[class*="cookie"] button[class*="accept"]',
      '[class*="cookie"] button[class*="agree"]',
      '[class*="consent"] button[class*="accept"]',
      '[id*="cookie"] button',
      '.cc-dismiss', '.cc-allow',
      '[data-testid="cookie-accept"]',
      'button[aria-label*="Accept"]',
      'button[aria-label*="accept"]',
    ];
    for (const sel of selectors) {
      const btn = document.querySelector(sel);
      if (btn && btn.offsetParent !== null) {
        btn.click();
        break;
      }
    }
    // Hide any remaining overlays that look like banners
    document.querySelectorAll('[class*="cookie-banner"], [class*="cookie-consent"], [class*="gdpr"]').forEach(el => {
      el.style.display = 'none';
    });
  });

  // 5. Wait a moment for banner dismissal to take effect
  await new Promise(r => setTimeout(r, 300));
}

async function handleStickyElements(page, mode) {
  await page.evaluate((mode) => {
    if (mode === 'disable') {
      // Store original positions and change sticky/fixed to relative
      document.querySelectorAll('*').forEach(el => {
        const computed = getComputedStyle(el);
        if (computed.position === 'sticky' || computed.position === 'fixed') {
          const tag = el.tagName.toUpperCase();
          if (tag === 'HTML' || tag === 'BODY') return;

          // Don't change fullscreen overlays (modals, etc.)
          const rect = el.getBoundingClientRect();
          const isFullscreen = rect.width >= window.innerWidth * 0.9 && rect.height >= window.innerHeight * 0.9;
          if (isFullscreen) return;

          el.dataset.originalPosition = computed.position;
          el.style.position = 'relative';
        }
      });
    } else if (mode === 'restore') {
      // Restore original positions
      document.querySelectorAll('[data-original-position]').forEach(el => {
        el.style.position = el.dataset.originalPosition;
        delete el.dataset.originalPosition;
      });
    }
  }, mode);
}

async function captureBreakpoint(browser, url, breakpoint, outputDir, fullPage, delay) {
  const page = await browser.newPage();

  // Set viewport and device emulation
  await page.setViewport({
    width: breakpoint.width,
    height: breakpoint.height,
    deviceScaleFactor: breakpoint.deviceScaleFactor,
    isMobile: breakpoint.isMobile,
    hasTouch: breakpoint.hasTouch,
  });

  if (breakpoint.isMobile) {
    await page.setUserAgent(
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
    );
  }

  // Navigate with timeout
  try {
    await page.goto(url, {
      waitUntil: 'networkidle2',
      timeout: 15000,
    });
  } catch {
    // Page may not fully settle — continue
    console.error(`  Warning: ${breakpoint.name} — page didn't fully load within 15s`);
  }

  // Custom delay for JS rendering
  if (delay > 0) {
    await new Promise(r => setTimeout(r, delay * 1000));
  }

  // Prepare page (kill animations, scroll for lazy load, dismiss cookies)
  await preparePageForCapture(page);

  // Get page metrics before capture
  const metrics = await page.evaluate(() => ({
    scrollHeight: document.body.scrollHeight,
    scrollWidth: document.body.scrollWidth,
    title: document.title,
    fonts: [...new Set([...document.fonts].map(f => f.family))],
  }));

  let filename;

  if (fullPage && metrics.scrollHeight > breakpoint.height) {
    // Full page capture — disable sticky elements first
    await handleStickyElements(page, 'disable');

    // Small wait for reflow
    await new Promise(r => setTimeout(r, 200));

    filename = `${breakpoint.name}-${breakpoint.width}x${metrics.scrollHeight}-full.png`;
    await page.screenshot({
      path: join(outputDir, filename),
      fullPage: true,
    });

    // Restore sticky elements
    await handleStickyElements(page, 'restore');

    // Also capture viewport-only version (useful for comparison)
    const viewportFilename = `${breakpoint.name}-${breakpoint.width}x${breakpoint.height}.png`;
    await page.screenshot({
      path: join(outputDir, viewportFilename),
      fullPage: false,
    });

    console.log(`  ${breakpoint.name}: ${filename} (${metrics.scrollHeight}px full) + viewport`);
  } else {
    filename = `${breakpoint.name}-${breakpoint.width}x${breakpoint.height}.png`;
    await page.screenshot({
      path: join(outputDir, filename),
      fullPage: false,
    });
    console.log(`  ${breakpoint.name}: ${filename}`);
  }

  // Save metadata
  const meta = {
    breakpoint: breakpoint.name,
    viewport: { width: breakpoint.width, height: breakpoint.height },
    pageHeight: metrics.scrollHeight,
    pageWidth: metrics.scrollWidth,
    fullPage: fullPage && metrics.scrollHeight > breakpoint.height,
    title: metrics.title,
    fonts: metrics.fonts,
    url,
    timestamp: new Date().toISOString(),
    file: filename,
  };

  await page.close();
  return meta;
}

async function main() {
  if (!URL) {
    console.error('No URL provided');
    process.exit(1);
  }

  mkdirSync(OUTPUT_DIR, { recursive: true });

  console.log('Responsive Screenshots (Puppeteer Engine)');
  console.log('==========================================');
  console.log(`  URL: ${URL}`);
  console.log(`  Output: ${OUTPUT_DIR}/`);
  console.log(`  Full page: ${FULL_PAGE}`);
  console.log(`  Delay: ${DELAY}s`);
  console.log(`  Breakpoints: ${BREAKPOINTS.map(b => b.name).join(', ')}`);
  console.log('');

  const browser = await puppeteer.launch({
    executablePath: CHROME_PATH,
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--disable-web-security',
      '--font-render-hinting=none', // Consistent font rendering
    ],
  });

  const allMeta = [];

  for (const bp of BREAKPOINTS) {
    try {
      const meta = await captureBreakpoint(browser, URL, bp, OUTPUT_DIR, FULL_PAGE, DELAY);
      allMeta.push(meta);
    } catch (err) {
      console.error(`  ${bp.name}: FAILED — ${err.message}`);
      allMeta.push({ breakpoint: bp.name, error: err.message });
    }
  }

  await browser.close();

  // Save metadata
  const metaPath = join(OUTPUT_DIR, 'metadata.json');
  writeFileSync(metaPath, JSON.stringify(allMeta, null, 2));
  console.log(`\n  Metadata: ${metaPath}`);

  // Summary
  const success = allMeta.filter(m => !m.error).length;
  console.log(`\n  ${success}/${BREAKPOINTS.length} breakpoints captured`);
}

main().catch(err => {
  console.error('Fatal:', err.message);
  process.exit(1);
});
