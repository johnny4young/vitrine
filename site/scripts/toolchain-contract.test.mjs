import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
// Plain `>=x[.y[.z]]` ranges only; compound ranges never raise the floor on their own.
const floor = (range) => {
  const match = range?.replace(/\s/g, '').match(/^>=(\d+)(?:\.(\d+))?(?:\.(\d+))?$/);
  return match && match.slice(1).map((part) => Number(part ?? 0));
};
const compare = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];

test('the declared Node floor is on the .nvmrc LTS line and covers every locked package', async () => {
  const manifest = JSON.parse(await read('../package.json'));
  const lock = JSON.parse(await read('../package-lock.json'));
  const declared = floor(manifest.engines.node);
  assert.ok(declared, `engines.node must be a plain >= floor, got ${manifest.engines.node}`);
  assert.equal(lock.packages[''].engines.node, manifest.engines.node);
  assert.equal(String(declared[0]), (await read('../.nvmrc')).trim());
  const required = Object.entries(lock.packages)
    .filter(([path]) => path)
    .map(([path, entry]) => [path, floor(entry.engines?.node)])
    .filter(([, version]) => version)
    .sort(([, a], [, b]) => compare(b, a))[0];
  assert.ok(compare(declared, required[1]) >= 0, `${required[0]} requires Node ${required[1].join('.')}`);
});

test('setup guides point at engines.node instead of repeating the version', async () => {
  for (const guide of ['../README.md', '../../CONTRIBUTING.md']) {
    const text = await read(guide);
    assert.match(text, /engines\.node/, guide);
    assert.doesNotMatch(text, /Node\.js \d/, guide);
  }
});
