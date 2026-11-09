import assert from 'node:assert/strict';
import { test, after } from 'node:test';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { summarize, checkSource } from './summarize-documentation-ui.mjs';

const states = ['en-light-minimum', 'en-dark-1280'];
const phases = ['launch', 'navigation', 'description', 'package-setup', 'panel', 'export', 'validation', 'termination'];
const valid = [...states].sort().flatMap(state => phases.map(phase =>
  'DOCUMENTATION_UI_SEGMENT state=' + state + ' phase=' + phase + ' seconds=1.25')).join('\n');
const prefixed = valid.split('\n').map(line => '2026-10-13T12:00:00Z ' + line).join('\n');
const source = readFileSync(new URL('../UITests/DocumentationExportUITests.swift', import.meta.url), 'utf8');
const guard = fileURLToPath(new URL('./summarize-documentation-ui.mjs', import.meta.url));
const directory = mkdtempSync(join(tmpdir(), 'vitrine-doc-timings-'));
after(() => rmSync(directory, { recursive: true }));

test('current emitter labels match the parser', () => checkSource(source));
test('complete evidence has the expected schema and totals', () => {
  assert.deepEqual(summarize(valid), {
    states: {
      'en-dark-1280': Object.fromEntries(phases.map(phase => [phase, 1.25])),
      'en-light-minimum': Object.fromEntries(phases.map(phase => [phase, 1.25])),
    },
    phase_seconds: { launch: 2.5, navigation: 2.5, description: 2.5, 'package-setup': 2.5, panel: 2.5, export: 2.5, validation: 2.5, termination: 2.5 },
    total_seconds: 20, state_count: 2,
    qualification: 'diagnostic timings only; no controlled performance improvement claim',
  });
});
test('timestamp prefixes and quoted emitter source are not extra evidence', () => {
  const unrelated = 'NOT_DOCUMENTATION_UI_SEGMENT state=unknown phase=unknown seconds=0\n'
    + 'source: "DOCUMENTATION_UI_SEGMENT state=\\(state) phase=\\(phase) seconds=\\(duration)"\n';
  assert.equal(summarize(unrelated + prefixed).total_seconds, 20);
});
test('Swift exponent durations remain valid', () => {
  const text = valid.replace('seconds=1.25', 'seconds=5e-05').replace('seconds=1.25', 'seconds=1e+1');
  assert.ok(Math.abs(summarize(text).total_seconds - 27.50005) < 1e-9);
});
test('form feed does not change the diagnostic line number', () => {
  assert.throws(() => summarize('progress\fdone\nDOCUMENTATION_UI_SEGMENT state=en-dark-1280'), /line 2/);
});

const invalid = [
  ['empty evidence', ''],
  ['missing phase', valid.slice(valid.indexOf('\n') + 1)],
  ['duplicate phase', valid + '\n' + valid.split('\n')[0]],
  ['NaN', valid.replace('seconds=1.25', 'seconds=nan')],
  ['negative duration', valid.replace('seconds=1.25', 'seconds=-1')],
  ['non-numeric duration', valid.replace('seconds=1.25', 'seconds=soon')],
  ['unknown state', valid + '\nDOCUMENTATION_UI_SEGMENT state=unknown phase=launch seconds=1.25'],
  ['unknown phase', valid + '\nDOCUMENTATION_UI_SEGMENT state=en-dark-1280 phase=unknown seconds=1.25'],
  ['truncated duration', valid + '\nDOCUMENTATION_UI_SEGMENT state=en-dark-1280 phase=launch'],
  ['empty duration', valid + '\nDOCUMENTATION_UI_SEGMENT state=unknown phase=launch seconds='],
  ['bare marker', valid + '\nDOCUMENTATION_UI_SEGMENT'],
  ['trailing payload', valid.replace('seconds=1.25', 'seconds=1.25 extra')],
  ['underscore in duration', valid.replace('seconds=1.25', 'seconds=1_25')],
  ['leading plus', valid.replace('seconds=1.25', 'seconds=+1.25')],
  ['infinity', valid.replace('seconds=1.25', 'seconds=infinity')],
  ['truncated prefixed marker', prefixed + '\n2026-10-13T12:00:00Z DOCUMENTATION_UI_SEGMENT state=en-dark-1280'],
  ['overflow in a phase total', valid.replaceAll('seconds=1.25', 'seconds=1e308')],
  ['overflow in the final total', valid.replaceAll('seconds=1.25', 'seconds=2e307')],
  ['overflow in an individual duration', valid.replace('seconds=1.25', 'seconds=1e9999')],
  ['prototype-shaped state', valid + '\nDOCUMENTATION_UI_SEGMENT state=__proto__ phase=launch seconds=1'],
  ['BOM is not stripped as whitespace', valid + '\ufeff'],
];
for (const [label, text] of invalid) test(label + ' is rejected', () => assert.throws(() => summarize(text)));

test('phase label drift fails closed', () => {
  assert.throws(() => checkSource(source.replaceAll('recordSegment("panel")', 'recordSegment("dialog")')));
});
test('state label drift fails closed', () => {
  assert.throws(() => checkSource(source.replaceAll('state: "en-dark-1280"', 'state: "en-dark-large"')));
});
test('Unicode prefix and trailing whitespace retain the original boundary semantics', () => {
  const text = valid.split('\n').map(line => '\u2003' + line + '\u001f').join('\n');
  assert.equal(summarize(text).total_seconds, 20);
});

test('CLI writes JSON for an owned log path containing spaces', () => {
  const file = join(directory, 'job log.txt');
  writeFileSync(file, valid);
  const result = spawnSync(process.execPath, [guard, file], { encoding: 'utf8' });
  assert.equal(result.status, 0);
  assert.equal(result.stderr, '');
  assert.equal(JSON.parse(result.stdout).total_seconds, 20);
});
for (const [label, separator] of [['CRLF', '\r\n'], ['CR', '\r']]) {
  test('CLI preserves universal-newline reading for ' + label + ' logs', () => {
    const file = join(directory, label + '.log');
    writeFileSync(file, valid.replaceAll('\n', separator));
    const result = spawnSync(process.execPath, [guard, file], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, '');
    assert.deepEqual(JSON.parse(result.stdout), summarize(valid));
  });
}
test('CLI counts mixed CR, CRLF and LF lines in malformed-marker diagnostics', () => {
  const file = join(directory, 'mixed-newlines.log');
  writeFileSync(file, 'first\rsecond\r\nthird\nDOCUMENTATION_UI_SEGMENT');
  const result = spawnSync(process.execPath, [guard, file], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /Malformed timing marker on line 4/);
});
test('CLI rejects a malformed log without success output', () => {
  const file = join(directory, 'malformed.log');
  writeFileSync(file, valid + '\nDOCUMENTATION_UI_SEGMENT');
  const result = spawnSync(process.execPath, [guard, file], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /Invalid documentation UI timing evidence:/);
});
test('CLI tolerates invalid UTF-8 only outside marker payloads', () => {
  const file = join(directory, 'bytes.log');
  writeFileSync(file, Buffer.concat([Buffer.from([255, 10]), Buffer.from(valid)]));
  const result = spawnSync(process.execPath, [guard, file], { encoding: 'utf8' });
  assert.equal(result.status, 0);
  assert.equal(JSON.parse(result.stdout).total_seconds, 20);
});
test('CLI missing log is usage error', () => {
  const result = spawnSync(process.execPath, [guard], { encoding: 'utf8' });
  assert.equal(result.status, 2);
  assert.equal(result.stdout, '');
});
test('CLI unknown option is usage error', () => {
  const result = spawnSync(process.execPath, [guard, '--unknown'], { encoding: 'utf8' });
  assert.equal(result.status, 2);
  assert.equal(result.stdout, '');
});
test('CLI unreadable file is an evidence error', () => {
  const result = spawnSync(process.execPath, [guard, join(directory, 'absent.log')], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
});
