import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const floor = (range) => range.match(/^>=(\d+\.\d+\.\d+)$/)?.[1];

test('the declared Node floor matches the pinned Astro release and the setup guides', async () => {
  const manifest = JSON.parse(await read('../package.json'));
  const lock = JSON.parse(await read('../package-lock.json'));
  const declared = floor(manifest.engines.node);
  assert.ok(declared, `engines.node must be a plain >= floor, got ${manifest.engines.node}`);
  assert.equal(lock.packages[''].engines.node, manifest.engines.node);
  assert.equal(declared, floor(lock.packages['node_modules/astro'].engines.node));
  for (const guide of ['../README.md', '../../CONTRIBUTING.md']) {
    assert.match(await read(guide), new RegExp(`Node\\.js ${declared.replaceAll('.', '\\.')}\\b`), guide);
  }
});
