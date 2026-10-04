import { TimeRange } from '../model/SessionRules';

const LOCALE = 'pl-PL';

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
