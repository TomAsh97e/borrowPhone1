import { ItemKind } from '../model/Documents';
import { TimeRange } from '../model/SessionRules';

const LOCALE = 'en-US';

const LONG_OPTIONS: Intl.DateTimeFormatOptions = {
  day: 'numeric',
  month: 'long',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit'
};

const DAY_OPTIONS: Intl.DateTimeFormatOptions = {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric'
};

const SHORT_DAY_OPTIONS: Intl.DateTimeFormatOptions = {
  day: 'numeric',
  month: 'short'
};

function format(time: number, options: Intl.DateTimeFormatOptions): string {
  try {
    return new Intl.DateTimeFormat(LOCALE, options).format(new Date(time));
  } catch (error) {
    return new Date(time).toLocaleString();
  }
}

export function formatDateTime(time: number): string {
  return format(time, LONG_OPTIONS);
}

export function formatDay(time: number): string {
  return format(time, DAY_OPTIONS);
}

export function formatRangeShort(range: TimeRange): string {
  const first = format(range.start, SHORT_DAY_OPTIONS);
  const last = format(range.end, SHORT_DAY_OPTIONS);
  return first === last ? first : `${first} – ${last}`;
}

function plural(count: number, one: string, many: string): string {
  return `${count} ${count === 1 ? one : many}`;
}

export function formatCount(kind: ItemKind, count: number): string {
  if (kind === 'photo') {
    return plural(count, 'photo', 'photos');
  }
  return kind === 'note' ? plural(count, 'note', 'notes') : plural(count, 'PDF file', 'PDF files');
}

export function kindLabel(kind: ItemKind): string {
  return kind === 'photo' ? 'Photos' : kind === 'note' ? 'Notes' : 'PDF';
}

export function formatSize(bytes: number): string {
  return bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KB` :
    `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
