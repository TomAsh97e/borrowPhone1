export const PIN_LENGTH = 4;

export type PresetKey = 'today' | 'yesterday' | 'weekend' | 'custom';

export interface TimeRange {
  start: number;
  end: number;
}

export function clampIndex(index: number, count: number): number {
  return Math.max(0, Math.min(index, Math.max(0, count - 1)));
}

export function isValidPin(pin: string): boolean {
  return new RegExp(`^\\d{${PIN_LENGTH}}$`).test(pin);
}

export function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  let difference = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index++) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return difference === 0;
}

export function startOfDay(time: number): number {
  const date = new Date(time);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

function addDays(dayStart: number, days: number): number {
  const date = new Date(dayStart);
  date.setDate(date.getDate() + days);
  return date.getTime();
}

// Whole local days, inclusive; the order of the two days does not matter.
export function dayRange(firstDay: number, lastDay: number): TimeRange {
  const first = startOfDay(Math.min(firstDay, lastDay));
  const last = startOfDay(Math.max(firstDay, lastDay));
  return { start: first, end: addDays(last, 1) - 1 };
}

// "Weekend" is the most recent Saturday–Sunday, including the current one.
export function presetRange(preset: PresetKey, now: number): TimeRange {
  const today = startOfDay(now);
  if (preset === 'yesterday') {
    const yesterday = addDays(today, -1);
    return dayRange(yesterday, yesterday);
  }
  if (preset === 'weekend') {
    const daysSinceSaturday = (new Date(today).getDay() + 1) % 7;
    const saturday = addDays(today, -daysSinceSaturday);
    return dayRange(saturday, addDays(saturday, 1));
  }
  return dayRange(today, today);
}

export function isInRange(time: number, range: TimeRange): boolean {
  return time >= range.start && time <= range.end;
}

// Owner's picks on top of the period: `added` photos are shared although outside it,
// `removed` photos are hidden although inside it.
export interface ManualPicks {
  added: string[];
  removed: string[];
}

export function isShared(uri: string, inRange: boolean, picks: ManualPicks): boolean {
  return inRange ? !picks.removed.includes(uri) : picks.added.includes(uri);
}

// The latest tap wins: the photo is kept only in the list that differs from the period rule.
export function togglePick(uri: string, inRange: boolean, picks: ManualPicks): ManualPicks {
  const share = !isShared(uri, inRange, picks);
  const added = picks.added.filter((item: string) => item !== uri);
  const removed = picks.removed.filter((item: string) => item !== uri);
  if (share && !inRange) {
    added.push(uri);
  }
  if (!share && inRange) {
    removed.push(uri);
  }
  return { added: added, removed: removed };
}

// Media library timestamps are milliseconds; older records may hold seconds.
export function normalizeTimestamp(value: number): number {
  return value > 0 && value < 100000000000 ? value * 1000 : value;
}
