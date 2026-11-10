import assert from 'node:assert/strict';

export function assertVisiblePixelsEqual(actual, expected) {
  assert.equal(actual.length, expected.length);
  if (actual.equals(expected)) return;
  // RGB under a fully transparent pixel is not visible and may be canonicalized.
  for (let index = 0; index < actual.length; index += 4) {
    assert.equal(actual[index + 3], expected[index + 3]);
    if (actual[index + 3] !== 0) {
      for (let channel = 0; channel < 3; channel++) assert.equal(actual[index + channel], expected[index + channel]);
    }
  }
}
