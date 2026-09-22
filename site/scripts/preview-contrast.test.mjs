import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const source = await readFile(new URL('../public/scripts/site.js', import.meta.url), 'utf8');

// Execute the shipped script's actual theme/language handlers. This is a narrow
// DOM double, not a substitute for the browser's computed-style/reflow checks.
function preview() {
  const elements = new Map();
  function element(id) {
    if (!elements.has(id)) elements.set(id, {
      style: { setProperty() {} }, dataset: {}, attributes: {}, listeners: {},
      classList: { toggle() {} }, querySelectorAll() { return []; },
      setAttribute(key, value) { this.attributes[key] = value; },
      addEventListener(event, handler) { this.listeners[event] = handler; },
    });
    return elements.get(id);
  }
  const themes = ['one-dark', 'one-light', 'dracula'].map(theme => ({
    ...element(theme), dataset: { theme },
  }));
  const langs = ['swift', 'ts', 'py'].map(lang => ({
    ...element(lang), dataset: { lang },
  }));
  themes[0].attributes['aria-pressed'] = 'true';
  element('themes').querySelectorAll = () => themes;
  element('langs').querySelectorAll = () => langs;
  vm.runInNewContext(source, {
    localStorage: { getItem() { return null; }, setItem() {} },
    document: {
      body: element('body'), getElementById: element,
      querySelector: () => themes.find(e => e.attributes['aria-pressed'] === 'true'),
    },
  });
  function click(group, target) {
    element(group).listeners.click.call(element(group), { target: { closest: () => target } });
  }
  return { element, themes, langs, click };
}

function luminance(hex) {
  assert.match(hex, /^#[\da-f]{6}$/i, 'the title must receive an explicit opaque theme color');
  const rgb = hex.slice(1).match(/../g).map(value => parseInt(value, 16) / 255)
    .map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
  return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
}

for (const theme of ['one-dark', 'one-light', 'dracula']) {
  test(`preview filename keeps readable contrast after theme and snippet changes: ${theme}`, () => {
    const bench = preview();
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
