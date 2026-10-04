import assert from 'node:assert/strict';
import {
  clampIndex, constantTimeEqual, dayRange, isInRange, isValidPin, normalizeTimestamp, presetRange
} from '../entry/src/main/ets/model/SessionRules.ts';

assert.equal(clampIndex(8, 5), 4);
assert.equal(clampIndex(-1, 5), 0);
assert.equal(isValidPin('2468'), true);
assert.equal(isValidPin('246810'), false);
assert.equal(isValidPin('12a4'), false);
assert.equal(constantTimeEqual(new Uint8Array([1, 2]), new Uint8Array([1, 2])), true);
assert.equal(constantTimeEqual(new Uint8Array([1, 2]), new Uint8Array([1, 3])), false);

const at = (text) => new Date(text).getTime();
const sunday = at('2026-10-04T15:00:00');
const today = presetRange('today', sunday);
assert.equal(isInRange(at('2026-10-04T00:00:00'), today), true);
assert.equal(isInRange(at('2026-10-04T23:59:59'), today), true);
assert.equal(isInRange(at('2026-10-05T00:00:00'), today), false);
assert.equal(isInRange(at('2026-10-03T20:15:00'), presetRange('yesterday', sunday)), true);

const weekendOnSunday = presetRange('weekend', sunday);
assert.equal(weekendOnSunday.start, at('2026-10-03T00:00:00'));
assert.equal(weekendOnSunday.end, at('2026-10-05T00:00:00') - 1);
const weekendOnWednesday = presetRange('weekend', at('2026-09-23T12:00:00'));
assert.equal(weekendOnWednesday.start, at('2026-09-19T00:00:00'));

const reversed = dayRange(at('2026-09-21T10:00:00'), at('2026-09-20T18:00:00'));
assert.equal(reversed.start, at('2026-09-20T00:00:00'));
assert.equal(isInRange(at('2026-09-21T23:00:00'), reversed), true);

assert.equal(normalizeTimestamp(1790000000), 1790000000000);
assert.equal(normalizeTimestamp(1790000000000), 1790000000000);
console.log('SessionRules checks passed.');
