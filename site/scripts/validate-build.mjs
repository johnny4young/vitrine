import { readFile, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const root = new URL('../dist/', import.meta.url);

async function read(relative) {
  return readFile(new URL(relative, root), 'utf8');
}

function requireText(source, expected, label) {
  if (!source.includes(expected)) {
    throw new Error(`${label}: missing ${expected}`);
  }
}

function requireAbsent(source, unexpected, label) {
  if (source.includes(unexpected)) {
    throw new Error(`${label}: must not include ${unexpected}`);
  }
}

async function requireMissing(relative) {
  try {
    await stat(join(root.pathname, relative));
  } catch (error) {
    if (error.code === 'ENOENT') return;
    throw error;
  }
  throw new Error(`Static output must not contain ${relative}`);
}

const english = await read('index.html');
const spanish = await read('es.html');
const download = await read('download.html');
const notFound = await read('404.html');
const robots = await read('robots.txt');
const headers = await read('_headers');
const siteScript = await readFile(new URL('../public/scripts/site.js', import.meta.url), 'utf8');
const projectSpec = await readFile(resolve(process.cwd(), '..', 'project.yml'), 'utf8');
const version = projectSpec.match(/^\s*MARKETING_VERSION:\s*"?([0-9]+\.[0-9]+\.[0-9]+)"?\s*$/m)?.[1];

if (!version) {
  throw new Error('Could not read MARKETING_VERSION from project.yml.');
}

requireText(english, '<html lang="en"', 'English route');
requireText(spanish, '<html lang="es"', 'Spanish route');
requireText(english, 'hreflang="es"', 'English alternate language');
requireText(spanish, 'hreflang="en"', 'Spanish alternate language');
requireText(english, 'application/ld+json', 'English structured data');
requireText(spanish, 'application/ld+json', 'Spanish structured data');
requireText(english, `"softwareVersion":"${version}"`, 'Project version sync');
requireText(english, 'id="bench"', 'Style bench');
requireText(english, 'class="salon"', 'Gallery hero');
requireText(english, 'id="responsive"', 'Responsive board');
requireText(english, 'id="whats-new"', 'Changelog section');
requireText(english, `data-release-version="${version}"`, 'Release highlights version sync');
requireText(english, 'Terminal captures now explain themselves.', 'Release terminal highlight');
requireText(english, 'The website is faster and easier to maintain.', 'Release website highlight');
requireText(english, 'src="/scripts/site.js"', 'English interactions');
requireText(spanish, 'src="/scripts/site.js"', 'Spanish interactions');
requireText(siteScript, 'Las capturas de terminal ahora se explican solas.', 'Spanish release highlight');
requireAbsent(siteScript, 'raw.githubusercontent.com', 'Static release highlights');
requireText(headers, "connect-src 'self' https://api.github.com;", 'Website connection policy');
requireAbsent(headers, 'raw.githubusercontent.com', 'Website connection policy');
requireAbsent(download, 'src="/scripts/site.js"', 'Download route');
requireAbsent(notFound, 'src="/scripts/site.js"', '404 route');
requireText(notFound, 'noindex', '404 crawl policy');
requireText(robots, 'sitemap-index.xml', 'robots sitemap');

try {
  Function(siteScript);
} catch (error) {
  throw new Error(`site.js must parse as valid JavaScript: ${error.message}`);
}

const packageJson = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'));
const dependencyNames = Object.keys({
  ...packageJson.dependencies,
  ...packageJson.devDependencies,
});
if (dependencyNames.some((name) => name === 'react' || name.startsWith('@astrojs/react')) ) {
  throw new Error('The static site must not depend on React.');
}

const png = await readFile(new URL('../public/og-card.png', import.meta.url));
if (png.toString('ascii', 1, 4) !== 'PNG') {
  throw new Error('og-card.png is not a PNG.');
}
const width = png.readUInt32BE(16);
const height = png.readUInt32BE(20);
if (width !== 1200 || height !== 630) {
  throw new Error(`og-card.png must be 1200x630, found ${width}x${height}.`);
}

for (const required of ['sitemap-index.xml', 'sitemap-0.xml', 'es.html', 'download.html']) {
  await stat(join(root.pathname, required));
}
await requireMissing('es/index.html');
await requireMissing('download/index.html');

const internalLinks = [...english.matchAll(/href="(\/[^"]*)"/g)].map((match) => match[1]);
for (const href of internalLinks) {
  if (href.startsWith('/#') || href === '/') continue;
  const pathname = href.split('#')[0].replace(/^\//, '');
  const target = pathname.includes('.') ? pathname : `${pathname}.html`;
  await stat(join(root.pathname, target));
}

console.log('✓ site build, metadata, crawl files, links, and social card validated');
