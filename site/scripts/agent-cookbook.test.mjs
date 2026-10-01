import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, existsSync, readFileSync, mkdirSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const script = fileURLToPath(new URL('../../scripts/agent-cookbook.py', import.meta.url));
const fakeSource = `#!/usr/bin/env python3
import json, pathlib, struct, sys, zlib
args = sys.argv[1:]
mode = pathlib.Path(__file__).with_suffix('.mode').read_text().strip()
with pathlib.Path(__file__).with_suffix('.calls').open('a') as stream: stream.write(json.dumps(args) + '\\n')
if mode == 'denied': sys.exit(3)
if mode == 'bad-json': print('{'); sys.exit(0)
if args[0] == 'list':
    data = {name: [{'id': 'synthetic'}] for name in ['themes','languages','formats','profiles','presets']}
elif args[0] == 'recipe':
    data = {'valid': True, 'format': 'vitrine.workspace-recipe', 'schemaVersion': 1, 'name': 'Synthetic'} if args[1] == 'validate' else {'format': 'vitrine.workspace-recipe', 'schemaVersion': 1, 'recipe': {'name': 'Synthetic'}}
elif '--edit' in args:
    data = {'command':'render','status':'opened_editor','copied':False,'sidecars':[]}
else:
    out = pathlib.Path(args[args.index('--out')+1])
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    png = b'\\x89PNG\\r\\n\\x1a\\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 100, 80, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\\0' + b'\\0'*300)*80)) + chunk(b'IEND', b'')
    if mode == 'truncated-png': png = png[:-8]
    if mode == 'bad-checksum': png = png[:-1] + bytes([png[-1] ^ 1])
    out.write_bytes(png)
    sidecars = [str(out.with_suffix(ext)) for ext in ['.md','.html','.txt']]
    for path in sidecars: pathlib.Path(path).write_text('Safe synthetic output')
    data = {'command':'render','status':'rendered','format':'png','output':str(out),'width':100,'height':80,'copied':False,'sidecars':sidecars}
    if mode == 'missing': out.with_suffix('.html').unlink()
    if mode == 'symlink': out.with_suffix('.txt').unlink(); out.with_suffix('.txt').symlink_to(pathlib.Path(__file__).with_suffix('.input'))
    if mode == 'wrong-output': data['output'] = '/outside/foreign.png'
    if mode == 'empty': out.with_suffix('.md').write_text('')
if mode == 'incomplete': data = {}
if mode == 'invalid-schema': data['schemaVersion'] = True
if mode == 'invalid-name': data['name'] = 42
print(json.dumps(data))
`;

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), 'vitrine-cookbook-'));
  const cli = join(dir, 'fake-cli.py');
  writeFileSync(cli, fakeSource, { mode: 0o700 });
  writeFileSync(join(dir, 'fake-cli.mode'), 'success');
  const input = join(dir, 'fake-cli.input');
  writeFileSync(input, 'Synthetic source');
  const recipe = join(dir, 'recipe.json');
  writeFileSync(recipe, '{}');
  return { dir, cli, input, recipe };
}
function run(f, workflow = 'render', name = 'run', mode = 'success') {
  writeFileSync(join(f.dir, 'fake-cli.mode'), mode);
  return spawnSync('python3', [script, workflow, '--cli', f.cli, '--parent', f.dir, '--name', name,
    '--input', f.input, '--recipe', f.recipe, '--alt-text', 'Authored synthetic description'], { encoding: 'utf8' });
}

for (const mode of ['discover', 'recipe', 'edit', 'render', 'terminal']) {
  test(`cookbook ${mode} requires complete JSON and produces a completion receipt`, () => {
    const f = fixture();
    try {
      const result = run(f, mode);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(JSON.parse(result.stdout).status, 'complete');
      assert.equal(readFileSync(join(f.dir, 'run/COMPLETE'), 'utf8'), `${mode}\n`);
    } finally { rmSync(f.dir, { recursive: true }); }
  });
}
for (const mode of ['denied', 'bad-json', 'incomplete', 'missing', 'wrong-output', 'symlink', 'empty', 'truncated-png', 'bad-checksum']) {
  test(`cookbook stops on ${mode}, preserves incomplete work, and never reports success`, () => {
    const f = fixture();
    try {
      const result = run(f, 'render', 'run', mode);
      assert.notEqual(result.status, 0);
      assert.equal(result.stdout, '');
      assert.equal(existsSync(join(f.dir, 'run/COMPLETE')), false);
      assert.match(result.stderr, /Workflow stopped/);
      assert.equal(readFileSync(f.input, 'utf8'), 'Synthetic source');
    } finally { rmSync(f.dir, { recursive: true }); }
  });
}
test('cookbook refuses existing paths and symlinks without changing foreign files', () => {
  const f = fixture();
  try {
    mkdirSync(join(f.dir, 'existing'));
    writeFileSync(join(f.dir, 'existing/sentinel'), 'foreign');
    symlinkSync(join(f.dir, 'existing'), join(f.dir, 'linked'));
    for (const name of ['existing', 'linked', '../escape']) {
      assert.notEqual(run(f, 'discover', name).status, 0);
    }
    assert.equal(readFileSync(join(f.dir, 'existing/sentinel'), 'utf8'), 'foreign');
  } finally { rmSync(f.dir, { recursive: true }); }
});

for (const mode of ['invalid-schema', 'invalid-name']) {
  test(`recipe ${mode} stops before the next CLI operation`, () => {
    const f = fixture();
    try {
      const result = run(f, 'recipe', 'run', mode);
      assert.notEqual(result.status, 0);
      assert.equal(existsSync(join(f.dir, 'run/COMPLETE')), false);
      const calls = readFileSync(join(f.dir, 'fake-cli.calls'), 'utf8').trim().split('\n').map(JSON.parse);
      assert.equal(calls.length, 1);
      assert.equal(calls[0][1], 'validate');
    } finally { rmSync(f.dir, { recursive: true }); }
  });
}
