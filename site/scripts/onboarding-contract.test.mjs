import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import test from 'node:test';
import { messages } from './localization-contract.mjs';

const catalog = JSON.parse(
  await readFile(new URL('../../Vitrine/Resources/Localizable.xcstrings', import.meta.url), 'utf8'),
).strings;
const captureKey = 'New Capture from Clipboard';
const captureTitle = {
  en: captureKey,
  es: catalog[captureKey].localizations.es.stringUnit.value,
};

for (const [path, locale] of [['index.html', 'en'], ['es.html', 'es']]) {
  const html = await readFile(new URL(`../dist/${path}`, import.meta.url), 'utf8');
  const copy = messages(html);
  const spanish = locale === 'es';

  test(`${locale}: first capture uses the menu, not an assumed global shortcut`, () => {
    for (const key of ['hero.tag', 'loop.s2h', 'loop.s2p']) {
      assert.match(copy.get(key), spanish ? /men[uú]/i : /menu/i, key);
      assert.doesNotMatch(copy.get(key), /⇧⌘S/, key);
    }
    const instructions = copy.get('loop.s2p');
    assert.match(instructions, spanish ? /opcional/i : /optional/i);
    assert.match(instructions, spanish ? /Ajustes/ : /Settings/);
    assert.match(instructions, spanish ? /desactivar/ : /disable/);
    const loop = html.match(/<section id="loop"[\s\S]*?<\/section>/)?.[0];
    assert.ok(loop, 'capture loop must be rendered without JavaScript');
    assert.doesNotMatch(loop, /class="keycap">⇧/, 'no fixed capture-shortcut illustration');
    assert.doesNotMatch(loop, /<div class="keys">/, 'decorative keycaps are hidden from assistive technology');
  });

  test(`${locale}: the named capture command matches the app's menu title`, () => {
    for (const key of ['hero.tag', 'loop.s2p']) {
      assert.ok(copy.get(key).includes(`<b>${captureTitle[locale]}</b>`), key);
    }
  });

  test(`${locale}: automatic copying and channel network boundaries are explicit`, () => {
    assert.match(copy.get('loop.s3p'), spanish ? /autom[aá]tica.*predeterminad/i : /automatic.*default/i);
    const privacy = copy.get('more.c1p');
    assert.match(privacy, spanish ? /descarga directa/i : /Direct download/i);
    assert.match(privacy, spanish ? /actualizaciones/ : /updates/);
    assert.match(privacy, spanish ? /activaci[oó]n/ : /activation/);
    assert.match(privacy, /App Store/);
  });
}
