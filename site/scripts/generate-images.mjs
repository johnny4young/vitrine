// Keep the public PNG originals stable for README links and non-WebP clients.
import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, unlink, writeFile } from 'node:fs/promises';
import sharp from 'sharp';

const publicDir = new URL('../public/', import.meta.url);
const mediaDir = new URL('responsive/', publicDir);
const generatedDir = new URL('../src/generated/', import.meta.url);
const screenshots = [
  'editor', 'annotated', 'diff', 'comparison-board', 'workspace-recipes',
  'terminal-htop', 'terminal-lazygit', 'terminal-nvim', 'workspace-recipe-cli',
];
await mkdir(mediaDir, { recursive: true });
await mkdir(generatedDir, { recursive: true });
const manifest = {};
const generated = new Set();
for (const source of ['vitrine-icon.png', ...screenshots.map((name) => `screenshots/${name}.png`)]) {
  const input = await readFile(new URL(source, publicDir));
  const { width, height } = await sharp(input).metadata();
  const icon = source === 'vitrine-icon.png';
  const widths = icon ? [28, 56, 84, 144] : [480, 960, 1440, width];
  const candidates = [];
  for (const target of [...new Set(widths)].filter((value) => value <= width).sort((a, b) => a - b)) {
    const buffer = await sharp(input).resize({ width: target }).webp({ lossless: true }).toBuffer();
    const hash = createHash('sha256').update(buffer).digest('hex').slice(0, 16);
    const filename = `${source.split('/').pop().replace('.png', '')}-${target}-${hash}.webp`;
    await writeFile(new URL(filename, mediaDir), buffer);
    candidates.push({ src: `/responsive/${filename}`, width: target, bytes: buffer.length });
  }
  // A larger lossless image can compress better (especially text at native scale).
  // Omit smaller candidates that would spend more bytes for fewer pixels.
  const efficient = candidates.filter((candidate, index) =>
    !candidates.slice(index + 1).some((larger) => larger.bytes <= candidate.bytes));
  for (const candidate of efficient) generated.add(candidate.src.split('/').pop());
  manifest[`/${source}`] = { width, height, candidates: efficient };
}
// Only remove obsolete files that match this generator's content-addressed names.
for (const filename of await readdir(mediaDir)) {
  if (/^[a-z0-9-]+-\d+-[a-f0-9]{16}\.webp$/.test(filename) && !generated.has(filename)) {
    await unlink(new URL(filename, mediaDir));
  }
}
await writeFile(new URL('images.json', generatedDir), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Generated ${generated.size} lossless responsive images from ${Object.keys(manifest).length} originals`);
