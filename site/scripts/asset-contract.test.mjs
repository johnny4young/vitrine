import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, stat } from 'node:fs/promises';
import { test } from 'node:test';
import sharp from 'sharp';
import { imageReferences } from './asset-contract.mjs';

const dist = new URL('../dist/', import.meta.url);
const manifest = JSON.parse(await readFile(new URL('../src/generated/images.json', import.meta.url)));
const home = await readFile(new URL('index.html', dist), 'utf8');

test('every page reserves image geometry and references existing responsive assets', async () => {
  for (const page of ['index.html', 'es.html', 'cli.html', 'es/cli.html', 'download.html', '404.html']) {
    const html = await readFile(new URL(page, dist), 'utf8');
    const { images, variants } = imageReferences(html);
    if (['index.html', 'es.html'].includes(page)) assert.equal(variants.length,
      Object.entries(manifest).filter(([src]) => !src.includes('workspace-recipe-cli'))
        .reduce((count, [src, image]) => count + image.candidates.length * (src.includes('icon') ? 2 : 1), 0));
    for (const src of images) await stat(new URL(src.slice(1), dist));
    for (const variant of variants) {
      const metadata = await sharp(new URL(variant.src.slice(1), dist).pathname).metadata();
      assert.equal(metadata.width, variant.width);
    }
  }
});

test('missing dimensions, sizes, candidates, and fallback are rejected', () => {
  for (const invalid of [home.replace(/width="\d+"/, ''), home.replace(/height="\d+"/, ''),
    home.replace(/sizes="[^"]+"/g, ''), home.replace(/srcset="[^"]+"/g, ''),
    home.replace('src="/vitrine-icon.png"', 'src="/missing.webp"')]) {
    assert.throws(() => imageReferences(invalid));
  }
});

test('responsive images are content-addressed lossless encodings of the resized originals', async () => {
  let originalBytes = 0;
  let fullSizeBytes = 0;
  for (const [src, image] of Object.entries(manifest)) {
    const input = await readFile(new URL(`../public${src}`, import.meta.url));
    const metadata = await sharp(input).metadata();
    assert.equal(image.width, metadata.width);
    assert.equal(image.height, metadata.height);
    originalBytes += input.length;
    fullSizeBytes += image.candidates.at(-1).bytes;
    for (const candidate of image.candidates) {
      const buffer = await readFile(new URL(candidate.src.slice(1), dist));
      assert.ok(candidate.src.includes(createHash('sha256').update(buffer).digest('hex').slice(0, 16)));
      assert.equal(buffer.length, candidate.bytes);
      const expected = await sharp(input).resize({ width: candidate.width }).ensureAlpha().raw().toBuffer();
      const actual = await sharp(buffer).ensureAlpha().raw().toBuffer();
      assert.equal(actual.length, expected.length);
      // RGB under a fully transparent pixel is not visible and may be canonicalized.
      for (let index = 0; index < actual.length; index += 4) {
        assert.equal(actual[index + 3], expected[index + 3]);
        if (actual[index + 3] !== 0) {
          for (let channel = 0; channel < 3; channel++) assert.equal(actual[index + channel], expected[index + channel]);
        }
      }
    }
  }
  assert.ok(fullSizeBytes < originalBytes * 0.7, 'Lossless assets should materially reduce bytes');
  console.log(`Original PNG bytes: ${originalBytes}; largest selected WebP bytes: ${fullSizeBytes}`);
});

test('immutable cache rules match generated asset routes, not mutable scripts or HTML', async () => {
  const headers = await readFile(new URL('_headers', dist), 'utf8');
  const rules = [...headers.matchAll(/^(\/\S*)\n((?:  [^\n]+\n?)+)/gm)];
  const immutable = rules.filter(([, , values]) => values.includes('immutable')).map(([, path]) => path).sort();
  assert.deepEqual(immutable, ['/responsive/*', '/static/*']);
  const styles = [...home.matchAll(/href="(\/[^" ]+\.css)"/g)].map(([, src]) => src);
  assert.ok(styles.length > 0);
  for (const src of styles) {
    assert.ok(src.startsWith('/static/'));
    await stat(new URL(src.slice(1), dist));
  }
});

test('README image URLs still resolve to the unchanged public PNG originals', async () => {
  const readme = await readFile(new URL('../../README.md', import.meta.url), 'utf8');
  const references = [...readme.matchAll(/src="site\/public\/([^" ]+\.png)"/g)];
  assert.ok(references.length > 0);
  for (const [, path] of references) {
    const original = await readFile(new URL(`../public/${path}`, import.meta.url));
    const published = await readFile(new URL(path, dist));
    assert.deepEqual(published, original);
  }
});
