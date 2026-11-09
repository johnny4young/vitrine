#!/usr/bin/env node
// Diagnostic automation timings only; never infer a controlled performance improvement.
import { readFileSync, realpathSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';

const STATES = ['en-light-minimum', 'en-dark-1280'];
const PHASES = ['launch', 'navigation', 'description', 'package-setup', 'panel', 'export', 'validation', 'termination'];
const marker = /(?<![^\p{White_Space}\u001c-\u001f])DOCUMENTATION_UI_SEGMENT(?=[\p{White_Space}\u001c-\u001f]|$)/u;
const pattern = /^DOCUMENTATION_UI_SEGMENT state=([^\p{White_Space}\u001c-\u001f]+) phase=([^\p{White_Space}\u001c-\u001f]+) seconds=([0-9]+(?:\.[0-9]+)?(?:e[-+]?[0-9]+)?)$/u;
const trim = text => text.replace(/^[\p{White_Space}\u001c-\u001f]+|[\p{White_Space}\u001c-\u001f]+$/gu, '');

export function summarize(text) {
  const states = Object.fromEntries(STATES.map(state => [state, {}]));
  for (const [index, line] of text.split('\n').entries()) {
    const start = marker.exec(line);
    if (!start) continue;
    const payload = trim(line.slice(start.index));
    const match = pattern.exec(payload);
    if (!match || match[0].length !== payload.length) {
      throw new Error('Malformed timing marker on line ' + (index + 1));
    }
    const [, state, phase, raw] = match;
    if (!STATES.includes(state) || !PHASES.includes(phase)) {
      throw new Error('Unknown state or phase: ' + state + '/' + phase);
    }
    if (Object.hasOwn(states[state], phase)) {
      throw new Error('Duplicate timing: ' + state + '/' + phase + '; provide one job attempt only');
    }
    const seconds = Number(raw);
    if (!Number.isFinite(seconds) || seconds < 0) throw new Error('Invalid duration: ' + raw);
    states[state][phase] = seconds;
  }
  for (const state of STATES) {
    const missing = PHASES.filter(phase => !Object.hasOwn(states[state], phase)).sort();
    if (missing.length) throw new Error('Incomplete state ' + state + ': missing ' + JSON.stringify(missing));
  }
  const totals = Object.fromEntries(PHASES.map(phase =>
    [phase, STATES.reduce((sum, state) => sum + states[state][phase], 0)]));
  const total = Object.values(totals).reduce((sum, seconds) => sum + seconds, 0);
  if (!Number.isFinite(total)) throw new Error('Nonfinite duration total');
  return {
    states: Object.fromEntries([...STATES].sort().map(state => [state, states[state]])),
    phase_seconds: totals,
    total_seconds: total,
    state_count: STATES.length,
    qualification: 'diagnostic timings only; no controlled performance improvement claim',
  };
}

export function checkSource(source) {
  const phases = [...source.matchAll(/recordSegment\("([^"]+)"\)/g)].map(match => match[1]);
  const states = [...source.matchAll(/\(state: "([^"]+)"/g)].map(match => match[1]);
  if (JSON.stringify([phases, states]) !== JSON.stringify([PHASES, STATES])) {
    throw new Error('Test marker labels ' + JSON.stringify([phases, states])
      + ' differ from summarizer labels ' + JSON.stringify([PHASES, STATES]));
  }
}

function main() {
  const usage = 'usage: summarize-documentation-ui.mjs LOG | --self-test';
  let args;
  try {
    args = parseArgs({
      options: { 'self-test': { type: 'boolean' }, help: { type: 'boolean', short: 'h' } },
      allowPositionals: true,
    });
  } catch (error) {
    console.error(usage + '\n' + error.message);
    return 2;
  }
  if (args.values.help) {
    console.log(usage);
    return 0;
  }
  if (args.positionals.length > 1) {
    console.error(usage);
    return 2;
  }
  if (args.values['self-test']) {
    const result = spawnSync(process.execPath, [
      '--test', '--test-concurrency=1',
      fileURLToPath(new URL('./summarize-documentation-ui.test.mjs', import.meta.url)),
    ], { stdio: 'inherit' });
    if (result.error) console.error(result.error.message);
    return result.status ?? 1;
  }
  if (args.positionals.length === 0) {
    console.error(usage);
    return 2;
  }
  try {
    // Malformed UTF-8 outside marker payloads is unrelated job-log text.
    // Preserve the previous file reader's universal-newline translation.
    const text = readFileSync(args.positionals[0], 'utf8').replace(/\r\n?/g, '\n');
    console.log(JSON.stringify(summarize(text), null, 2));
    return 0;
  } catch (error) {
    console.error('Invalid documentation UI timing evidence: ' + error.message);
    return 1;
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main();
}
