import assert from 'node:assert/strict';

export function imageReferences(html) {
  const images = [...html.matchAll(/<img\b[^>]*>/g)].map(([tag]) => {
    assert.match(tag, /\bwidth="[1-9]\d*"/, 'Image must reserve width');
    assert.match(tag, /\bheight="[1-9]\d*"/, 'Image must reserve height');
    assert.match(tag, /\balt(?:="[^"]*")?(?=[\s>])/, 'Image must declare alt text');
    return tag.match(/\bsrc="([^"]+)"/)[1];
  });
  assert.ok(images.length > 0, 'Expected visible images');
  const variants = [];
  for (const [picture] of html.matchAll(/<picture>[\s\S]*?<\/picture>/g)) {
    assert.match(picture, /type="image\/webp"/, 'Picture must offer WebP');
    assert.match(picture, /\bsizes="[^"]+"/, 'Picture must declare responsive sizes');
    const set = picture.match(/\bsrcset="([^"]+)"/);
    assert.ok(set, 'Picture must offer responsive candidates');
    let previousWidth = 0;
    for (const candidate of set[1].split(', ')) {
      const parts = candidate.match(/^(\/responsive\/[a-z0-9-]+-\d+-[a-f0-9]{16}\.webp) (\d+)w$/);
      assert.ok(parts, `Invalid responsive candidate: ${candidate}`);
      assert.ok(Number(parts[2]) > previousWidth, 'Candidate widths must be unique and ascending');
      previousWidth = Number(parts[2]);
      variants.push({ src: parts[1], width: previousWidth });
    }
    assert.match(picture, /<img\b[^>]*src="[^"]+\.png"/, 'Retain the PNG fallback');
  }
  return { images, variants };
}
