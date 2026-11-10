import assert from 'node:assert/strict';
import { test } from 'node:test';
import { assertVisiblePixelsEqual } from './pixel-contract.mjs';

function equalViews() {
  const backing = Buffer.alloc(24, 99);
  backing.set([10, 20, 30, 255], 4);
  backing.set([10, 20, 30, 255], 12);
  return { backing, actual: backing.subarray(4, 8), expected: backing.subarray(12, 16) };
}

test('equal pixels at different offsets in one backing store compare equally', () => {
  const { backing, actual, expected } = equalViews();
  assert.equal(actual.buffer, backing.buffer);
  assert.equal(expected.buffer, backing.buffer);
  assert.equal(actual.byteOffset, backing.byteOffset + 4);
  assert.equal(expected.byteOffset, backing.byteOffset + 12);
  assert.notEqual(actual.byteOffset, expected.byteOffset);

  assert.doesNotThrow(() => assertVisiblePixelsEqual(actual, expected));
});

test('a visible RGB difference inside an offset view is rejected', () => {
  const { actual, expected } = equalViews();
  expected[0] = 11;

  assert.throws(() => assertVisiblePixelsEqual(actual, expected), {
    name: 'AssertionError', actual: 10, expected: 11,
  });
});

test('an alpha difference inside an offset view is rejected', () => {
  const { actual, expected } = equalViews();
  expected[3] = 128;

  assert.throws(() => assertVisiblePixelsEqual(actual, expected), {
    name: 'AssertionError', actual: 255, expected: 128,
  });
});

test('changes outside both offset views do not affect their comparison', () => {
  const { backing, actual, expected } = equalViews();
  backing[0] = 1;
  backing[8] = 2;
  backing[23] = 3;
  assert.deepEqual([...actual], [10, 20, 30, 255]);
  assert.deepEqual([...expected], [10, 20, 30, 255]);

  assert.doesNotThrow(() => assertVisiblePixelsEqual(actual, expected));
});

test('different view lengths fail the size assertion even on a shared backing store', () => {
  const { backing, actual } = equalViews();
  const expected = backing.subarray(12, 20);
  assert.equal(actual.buffer, expected.buffer);
  assert.equal(actual.length, 4);
  assert.equal(expected.length, 8);

  assert.throws(() => assertVisiblePixelsEqual(actual, expected), {
    name: 'AssertionError', actual: 4, expected: 8,
  });
});
