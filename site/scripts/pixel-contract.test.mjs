import assert from 'node:assert/strict';
import { test } from 'node:test';
import { assertVisiblePixelsEqual } from './pixel-contract.mjs';

test('identical RGBA pixels compare equally', () => {
  assert.doesNotThrow(() => assertVisiblePixelsEqual(
    Buffer.from([10, 20, 30, 255]), Buffer.from([10, 20, 30, 255])));
});

test('RGB differences under fully transparent pixels are ignored', () => {
  assert.doesNotThrow(() => assertVisiblePixelsEqual(
    Buffer.from([0, 0, 0, 0]), Buffer.from([10, 20, 30, 0])));
});

test('alpha differences are rejected even when one pixel is transparent', () => {
  assert.throws(() => assertVisiblePixelsEqual(
    Buffer.from([10, 20, 30, 0]), Buffer.from([10, 20, 30, 128])), { name: 'AssertionError' });
});

for (const [channel, actual] of [
  ['red', [11, 20, 30, 128]],
  ['green', [10, 21, 30, 128]],
  ['blue', [10, 20, 31, 128]],
]) {
  test(`${channel} differences are rejected for a partially visible pixel`, () => {
    assert.throws(() => assertVisiblePixelsEqual(
      Buffer.from(actual), Buffer.from([10, 20, 30, 128])), { name: 'AssertionError' });
  });
}

test('a later visible mismatch is rejected after an ignored transparent RGB difference', () => {
  assert.throws(() => assertVisiblePixelsEqual(
    Buffer.from([0, 0, 0, 0, 11, 20, 30, 255]),
    Buffer.from([10, 20, 30, 0, 10, 20, 30, 255])), { name: 'AssertionError' });
});

test('different byte counts are rejected', () => {
  assert.throws(() => assertVisiblePixelsEqual(
    Buffer.from([10, 20, 30, 255]), Buffer.alloc(0)), { name: 'AssertionError' });
});
