import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../public/scripts/site.js', import.meta.url), 'utf8');

function stub(dataset = {}) {
  return {
    dataset, style: { setProperty() {} }, attributes: {}, listeners: {}, textContent: '',
    classList: { toggle() {} }, querySelectorAll: () => [],
    setAttribute(key, value) { this.attributes[key] = value; },
    addEventListener(type, listener) { this.listeners[type] = listener; },
  };
}

// Runs the shipped site.js against a narrow DOM double; it does not prove browser layout.
export function loadSiteScript({ clipboard } = {}) {
  const elements = new Map();
  const timers = [];
  const element = (id) => {
    if (!elements.has(id)) elements.set(id, stub());
    return elements.get(id);
  };
  const themes = ['one-dark', 'one-light', 'dracula'].map((theme) => stub({ theme }));
  const langs = ['swift', 'ts', 'py'].map((lang) => stub({ lang }));
  themes[0].attributes['aria-pressed'] = 'true';
  element('themes').querySelectorAll = () => themes;
  element('langs').querySelectorAll = () => langs;
  vm.runInNewContext(source, {
    document: {
      body: stub(), getElementById: element, querySelectorAll: () => [],
      querySelector: () => themes.find((chip) => chip.attributes['aria-pressed'] === 'true'),
    },
    navigator: { clipboard },
    localStorage: { getItem: () => null, setItem() {} },
    setTimeout: (callback) => timers.push(callback),
    clearTimeout() {},
  });
  const click = (id, target) => element(id).listeners.click.call(element(id), { target: { closest: () => target } });
  return { element, themes, langs, timers, click };
}
