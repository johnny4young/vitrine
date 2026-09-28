import assert from 'node:assert/strict';

// Inspect generated HTML, not the translation source or a client-side script.
export function messages(html) {
  const found = new Map();
  for (const match of html.matchAll(/<([a-z][\w-]*)\b[^>]*\bdata-copy="([^"]+)"[^>]*>/g)) {
    const [open, tag, key] = match;
    const start = match.index + open.length;
    // Close at the matching depth so nested same-name tags keep the whole message.
    const tags = new RegExp(`<(/?)${tag}\\b[^>]*>`, 'g');
    tags.lastIndex = start;
    let depth = 1;
    let end = html.length;
    for (let next = tags.exec(html); next; next = tags.exec(html)) {
      depth += next[1] ? -1 : 1;
      if (depth === 0) { end = next.index; break; }
    }
    found.set(key, html.slice(start, end));
  }
  return found;
}

export function validateLocalizedHomes(english, spanish) {
  const en = messages(english);
  const es = messages(spanish);
  assert.equal(en.size, 93, 'Every expected marketing message must render');
  assert.deepEqual([...en.keys()].sort(), [...es.keys()].sort(), 'EN/ES message inventory differs');
  const invariant = new Set(['term.eyebrow', 'story4.t1', 'story5.t1']);
  for (const [key, value] of en) {
    assert.ok(value.trim() && es.get(key).trim(), `${key}: empty rendered content`);
    if (!invariant.has(key)) assert.notEqual(value, es.get(key), `${key}: English fallback in Spanish HTML`);
  }
  assert.match(en.get('hero.h1'), /^Put your code /);
  assert.match(es.get('hero.h1'), /^Pon tu código /);
  for (const [html, locale] of [[english, 'en'], [spanish, 'es']]) {
    assert.ok(html.includes(`<html lang="${locale}"`));
    assert.ok(html.includes('href="/download"'), 'No-JS download fallback is missing');
    assert.ok(html.includes('$19.99'), 'Current checkout price changed');
    assert.ok(html.includes('brew install --cask johnny4young/tap/vitrine'));
    assert.equal([...html.matchAll(/\bdata-copy="/g)].length, 93, 'Duplicated marketing message');
  }
}

export function validateLanguageLinks(html, page, locale) {
  for (const language of ['en', 'es']) {
    const tag = html.match(new RegExp(`<a\\b[^>]*\\bid="set-${language}"[^>]*>`))?.[0];
    assert.ok(tag, `${page}: ${language} must be a native language link`);
    const href = `${language === 'es' ? '/es' : ''}${page === 'cli' ? '/cli' : ''}` || '/';
    assert.ok(tag.includes(`href="${href}"`), `${page}: wrong language destination`);
    assert.ok(tag.includes(`hreflang="${language}"`));
    assert.equal(tag.includes('aria-current="page"'), language === locale);
    assert.ok(!tag.includes('aria-pressed') && !tag.includes('data-target'));
  }
}
