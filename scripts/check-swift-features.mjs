#!/usr/bin/env node
// Check compiler log text without evaluating commands or invoking a compiler.
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';

const modules = ['Vitrine', 'VitrineCLICore', 'VitrineDomain', 'VitrineMenuBarHelper', 'VitrineRendering', 'vitrine_cli'];
const owned = new Set(modules);
const feature = 'MemberImportVisibility';
// Preserve the previous Unicode whitespace semantics, including information separators.
// JavaScript \s also includes BOM, which the previous guard did not treat as whitespace.
const moduleName = /(?:^|[\p{White_Space}\u001c-\u001f])-module-name[\p{White_Space}\u001c-\u001f]+([^\p{White_Space}\u001c-\u001f]+)/u;
const lineBreaks = /\r\n|[\n\r\v\f\u001c-\u001e\u0085\u2028\u2029]/u;
const usage = 'usage: check-swift-features.mjs LOG\n       check-swift-features.mjs --self-test';

function main() {
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
    const test = fileURLToPath(new URL('./test-swift-features.sh', import.meta.url));
    const result = spawnSync('/bin/bash', [test], { stdio: 'inherit' });
    if (result.error) console.error(result.error.message);
    return result.status ?? 1;
  }
  if (args.positionals.length === 0) {
    console.error(usage);
    return 2;
  }
  let log;
  try {
    // Node's UTF-8 decoder replaces malformed bytes, as the previous reader did.
    log = readFileSync(args.positionals[0], 'utf8');
  } catch (error) {
    console.error(error.message);
    return 1;
  }

  const seen = new Set();
  const missing = new Set();
  for (const line of log.split(lineBreaks)) {
    if (!line.includes('swiftc') && !line.includes('swift-frontend')) continue;
    const match = moduleName.exec(line);
    if (!match || !owned.has(match[1])) continue;
    seen.add(match[1]);
    if (!line.includes('-enable-upcoming-feature ' + feature)) missing.add(match[1]);
  }
  if (missing.size) {
    console.error(feature + ' is off for: ' + [...missing].sort().join(', '));
    return 1;
  }
  const absent = modules.filter(module => !seen.has(module));
  if (absent.length) {
    console.error('the log compiles no Swift for: ' + absent.join(', ') + '; build clean so every module is checked');
    return 1;
  }
  console.log(feature + ' is on for every app-owned module: ' + modules.join(', '));
  return 0;
}

process.exitCode = main();
