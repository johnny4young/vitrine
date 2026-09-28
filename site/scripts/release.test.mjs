import assert from 'node:assert/strict';
import { test } from 'node:test';
import { publishedDownload } from '../public/scripts/release.js';

const release = {
  draft: false, prerelease: false, tag_name: 'v1.2.3',
  html_url: 'https://github.com/johnny4young/vitrine/releases/tag/v1.2.3',
  assets: [{ name: 'Vitrine-1.2.3.dmg', state: 'uploaded', size: 42,
    browser_download_url: 'https://github.com/johnny4young/vitrine/releases/download/v1.2.3/Vitrine-1.2.3.dmg' }],
};

test('uses a published stable release and its uploaded DMG, not the source version', () => {
  assert.deepEqual(publishedDownload(release), { version: 'v1.2.3', url: release.assets[0].browser_download_url });
});

test('rejects drafts, prereleases, malformed payloads and foreign release pages', () => {
  for (const input of [null, {}, { ...release, draft: true }, { ...release, prerelease: true },
    { ...release, tag_name: 'v1.2.4-beta' }, { ...release, html_url: 'javascript:alert(1)' },
    { ...release, html_url: release.html_url.replace('github.com', 'example.com') }]) {
    assert.equal(publishedDownload(input), null);
  }
});

test('missing, unfinished, empty or foreign assets fall back to the published release page', () => {
  const asset = release.assets[0];
  for (const assets of [null, [], [null], [{ ...asset, size: 0 }], [{ ...asset, state: 'new' }],
    [{ ...asset, name: 'Vitrine-9.9.9.dmg' }], [{ ...asset, browser_download_url: 'javascript:alert(1)' }],
    [{ ...asset, browser_download_url: asset.browser_download_url.replace('github.com', 'example.com') }]]) {
    assert.equal(publishedDownload({ ...release, assets }).url, release.html_url);
  }
});
