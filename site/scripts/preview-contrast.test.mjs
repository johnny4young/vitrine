import assert from 'node:assert/strict';
import test from 'node:test';
import { loadSiteScript } from './site-script-harness.mjs';

function luminance(hex) {
  assert.match(hex, /^#[\da-f]{6}$/i, 'the title must receive an explicit opaque theme color');
  const rgb = hex.slice(1).match(/../g).map(value => parseInt(value, 16) / 255)
    .map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
  return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
}

for (const theme of ['one-dark', 'one-light', 'dracula']) {
  test(`preview filename keeps readable contrast after theme and snippet changes: ${theme}`, () => {
    const bench = loadSiteScript();
    bench.click('themes', bench.themes.find(e => e.dataset.theme === theme));
    for (const [index, name] of ['Counter.swift', 'api.ts', 'main.py'].entries()) {
      bench.click('langs', bench.langs[index]);
      assert.equal(bench.element('benchName').textContent, name);
      const fg = luminance(bench.element('benchName').style.color);
      const bg = luminance(bench.element('benchCard').style.background);
      assert.ok((Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05) >= 4.5);
      assert.equal(bench.element('benchName').style.color, bench.element('benchCode').style.color);
    }
  });
}
