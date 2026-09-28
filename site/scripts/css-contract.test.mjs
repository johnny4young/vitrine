import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const css = await readFile(new URL('../src/styles/global.css', import.meta.url), 'utf8');
const marker = '@media (prefers-reduced-motion: reduce) {';
const start = css.indexOf(marker);
const reduced = css.slice(start + marker.length, css.indexOf('\n  }', start));
const rules = (text) => [...text.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
  .map(([, selector, body]) => ({ selector: selector.trim(), body }));

test('Reduce Motion neutralizes every hover and press transform', () => {
  assert.ok(start >= 0, 'Missing the Reduce Motion block');
  const motion = rules(css.slice(0, start))
    .filter(({ selector, body }) => /:(hover|active)\b/.test(selector) && /transform:\s*(?!none)/.test(body));
  assert.ok(motion.length > 0);
  for (const { selector } of motion) {
    assert.ok(rules(reduced).some((rule) => rule.selector.split(',').map((s) => s.trim()).includes(selector)
      && /transform:\s*none/.test(rule.body)), `${selector} still moves under Reduce Motion`);
  }
  assert.match(reduced, /html\s*\{\s*scroll-behavior:\s*auto;/);
});

test('CLI examples can shrink below their code width in narrow viewports', () => {
  assert.match(css, /\.cli-example\s*\{[^}]*\bmin-width:\s*0;/);
});
