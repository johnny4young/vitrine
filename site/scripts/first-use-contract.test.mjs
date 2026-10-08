import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import test from 'node:test';

const guide = await readFile(new URL('../../docs/FIRST-CAPTURE.md', import.meta.url), 'utf8');
const cli = await readFile(new URL('../src/components/CLIDocsPage.astro', import.meta.url), 'utf8');

test('first-capture CLI handoff distinguishes published v1.2.3 from current source', () => {
  const optional = guide.split('## Optional next steps')[1];
  assert.match(optional, /v1\.2\.3[\s\S]*?PRO[\s\S]*?--edit/);
  assert.match(optional, /Open Editor[\s\S]*?paste/);
  assert.match(optional, /current source/);
});

test('CLI first success is free, self-contained and does not assume a project file', () => {
  const start = cli.split('<section id="start"')[1].split('</section>')[0];
  assert.match(start, /vgrab --no-context printf/);
  assert.match(start, /vitrine shell-init zsh/);
  assert.doesNotMatch(start, /Sources\/App\.swift/);
  assert.ok(start.indexOf('vgrab --no-context') < start.indexOf('vitrine render'));
  assert.match(start, /text\.proFirstRun/);
  assert.match(start, /text\.releaseHandoff/);
});

test('both CLI locales explain clipboard success, PRO output and release handoff limits', () => {
  assert.match(cli, /firstRun: 'Your first image, free'/);
  assert.match(cli, /firstRun: 'Tu primera imagen, gratis'/);
  assert.match(cli, /proFirstRun: 'Automated image output \(PRO\)'/);
  assert.match(cli, /proFirstRun: 'Imagen automatizada \(PRO\)'/);
  assert.match(cli, /releaseHandoff: '[^']*v1\.2\.3[^']*PRO[^']*--edit/);
  assert.match(cli, /Paste the image/);
  assert.match(cli, /Pega la imagen/);
});

for (const [page, title] of [['cli.html', 'Your first image, free'], ['es/cli.html', 'Tu primera imagen, gratis']]) {
  test(`${page}: the static first-use page renders usable shell examples and version guidance`, async () => {
    const html = await readFile(new URL(`../dist/${page}`, import.meta.url), 'utf8');
    const start = html.split('<section id="start"')[1].split('</section>')[0];
    assert.ok(start.includes(title));
    assert.match(start, /vgrab --no-context printf (?:&#39;|')Hello from Vitrine\\n(?:&#39;|')/);
    assert.match(start, /v1\.2\.3/);
    assert.match(start, /--stdin --stdin-name example\.swift/);
    assert.match(start, /--no-overwrite/);
    assert.doesNotMatch(start, /Sources\/App\.swift/);
  });
}
