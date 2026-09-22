import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import test from 'node:test';
import { validateLocalizedHomes, validateLanguageLinks } from './localization-contract.mjs';

const en = await readFile(new URL('../dist/index.html', import.meta.url), 'utf8');
const es = await readFile(new URL('../dist/es.html', import.meta.url), 'utf8');

test('both generated homes satisfy the complete static localization contract', () => {
  validateLocalizedHomes(en, es);
});

test('English hero with a Spanish document language is rejected', () => {
  assert.throws(() => validateLocalizedHomes(en, es.replace('Pon tu código', 'Put your code')));
});

test('a secondary section falling back to English is rejected', () => {
  assert.throws(() => validateLocalizedHomes(en, es.replace('Un snippet. Todos los estilos.', 'One snippet. Every look.')));
});

test('an omitted or duplicated translation is rejected', () => {
  assert.throws(() => validateLocalizedHomes(en, es.replace('data-copy="bench.title"', 'data-missing="bench.title"')));
  assert.throws(() => validateLocalizedHomes(en, es + '<p data-copy="bench.title">Duplicated</p>'));
});

test('real language links preserve each page and current-language state', async () => {
  for (const [path, page, locale] of [
    ['index.html', 'home', 'en'], ['es.html', 'home', 'es'],
    ['cli.html', 'cli', 'en'], ['es/cli.html', 'cli', 'es'],
  ]) {
    validateLanguageLinks(await readFile(new URL(`../dist/${path}`, import.meta.url), 'utf8'), page, locale);
  }
});

test('JavaScript-only language buttons and wrong destinations are rejected', () => {
  assert.throws(() => validateLanguageLinks(es.replace('<a id="set-en"', '<button id="set-en"'), 'home', 'es'));
  assert.throws(() => validateLanguageLinks(es.replace('hreflang="en" lang="en" href="/"', 'hreflang="en" lang="en" href="/cli"'), 'home', 'es'));
});
