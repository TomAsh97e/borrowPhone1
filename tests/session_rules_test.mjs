import assert from 'node:assert/strict';
import { clampIndex, constantTimeEqual, fitSize, hasValidSelection, isValidPin } from '../entry/src/main/ets/model/SessionRules.ts';

assert.equal(hasValidSelection(['one', 'two'], 5), true);
assert.equal(hasValidSelection(['one', 'one'], 5), false);
assert.equal(clampIndex(8, 5), 4);
assert.deepEqual(fitSize(4000, 2000, 1600), { width: 1600, height: 800 });
assert.equal(isValidPin('246810'), true);
assert.equal(isValidPin('12345a'), false);
assert.equal(constantTimeEqual(new Uint8Array([1, 2]), new Uint8Array([1, 2])), true);
assert.equal(constantTimeEqual(new Uint8Array([1, 2]), new Uint8Array([1, 3])), false);
console.log('SessionRules checks passed.');
