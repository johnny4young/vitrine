import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';

const source = await readFile(new URL('../public/scripts/site.js', import.meta.url), 'utf8');

function element() {
  return {
    dataset: { theme: 'one-dark', copiedLabel: 'Copiado', errorLabel: 'No se pudo copiar' },
    style: { setProperty() {} },
    classList: { toggle() {} },
    listeners: {},
    textContent: '',
    setAttribute() {},
    querySelectorAll: () => [],
    addEventListener(type, listener) { this.listeners[type] = listener; },
  };
}

function load(clipboard) {
  const elements = new Map();
  const timers = [];
  const document = {
    body: element(),
    getElementById(id) {
      if (!elements.has(id)) elements.set(id, element());
      return elements.get(id);
    },
    querySelector: () => element(),
    querySelectorAll: () => [],
  };
  vm.runInNewContext(source, {
    document,
    navigator: { clipboard },
    setTimeout: (callback) => timers.push(callback),
    clearTimeout() {},
  });
  const button = elements.get('copy-brew');
  const click = () => button.listeners.click.call(button);
  return { click, feedback: document.getElementById('install-feedback'), timers };
}

test('install copy feedback clears so a repeated copy is announced again', async () => {
  const { click, feedback, timers } = load({ writeText: () => Promise.resolve() });
  click();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(feedback.textContent, 'Copiado');
  timers.splice(0).forEach((callback) => callback());
  assert.equal(feedback.textContent, '');
});

test('install copy failure is reported without the clipboard API', () => {
  const { click, feedback } = load(undefined);
  click();
  assert.equal(feedback.textContent, 'No se pudo copiar');
});
