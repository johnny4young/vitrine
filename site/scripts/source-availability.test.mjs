import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import test from 'node:test';
import { messages } from './localization-contract.mjs';

for (const [path, locale] of [['index.html', 'en'], ['es.html', 'es']]) {
  const html = await readFile(new URL(`../dist/${path}`, import.meta.url), 'utf8');
  const copy = messages(html);
  test(`${locale}: release boundary is visible without JavaScript`, () => {
    const notice = html.match(/<section class="availability"[\s\S]*?<\/section>/)?.[0];
    assert.ok(notice);
    assert.match(copy.get('availability.body'), /v1\.2\.3/);
    assert.match(copy.get('availability.shortcuts'), /v1\.2\.3.*⇧⌘S/);
    assert.match(copy.get('availability.privacy'), /v1\.2\.3/);
    assert.match(copy.get('availability.automation'), /render --edit/);
    assert.match(copy.get('availability.automation'), /PRO/);
    assert.match(notice, /CHANGELOG\.md#unreleased/);
    assert.doesNotMatch(notice, /<script|data-version|data-download/);
    assert.match(html, /href="\/download"/);
  });
}
