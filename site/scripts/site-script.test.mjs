import assert from 'node:assert/strict';
import test from 'node:test';
import { loadSiteScript } from './site-script-harness.mjs';

function copyButton(clipboard) {
  const site = loadSiteScript({ clipboard });
  site.element('copy-brew').dataset = { copiedLabel: 'Copiado', errorLabel: 'No se pudo copiar' };
  return { ...site, copy: () => site.click('copy-brew'), feedback: site.element('install-feedback') };
}

test('install copy feedback clears so a repeated copy is announced again', async () => {
  const { copy, feedback, timers } = copyButton({ writeText: () => Promise.resolve() });
  copy();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(feedback.textContent, 'Copiado');
  timers.splice(0).forEach((callback) => callback());
  assert.equal(feedback.textContent, '');
});

test('install copy failure is reported without the clipboard API', () => {
  const { copy, feedback } = copyButton(undefined);
  copy();
  assert.equal(feedback.textContent, 'No se pudo copiar');
});
