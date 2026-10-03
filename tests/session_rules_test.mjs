import assert from 'node:assert/strict';
import { clampIndex, fitSize, hasValidSelection } from '../entry/src/main/ets/model/SessionRules.ts';

assert.equal(hasValidSelection(['one', 'two'], 5), true);
assert.equal(hasValidSelection(['one', 'one'], 5), false);
assert.equal(clampIndex(8, 5), 4);
assert.deepEqual(fitSize(4000, 2000, 1600), { width: 1600, height: 800 });
console.log('SessionRules checks passed.');
