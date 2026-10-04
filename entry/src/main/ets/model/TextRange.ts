import { ALL_KINDS } from './Documents';
import type { ItemKind } from './Documents';
import { dayRange, presetRange, startOfDay } from './SessionRules';
import type { PresetKey, TimeRange } from './SessionRules';

// Text-to-period rules around the on-device model. The model never sees anything this file did not
// accept, may only answer with periods the request text justifies (buildGrammar), and its answer is
// checked again here before the owner is asked to approve it.

export const MAX_REQUEST_LENGTH = 120;
export const MAX_PERIOD_DAYS = 366;

export type RejectReason = 'empty' | 'too_long' | 'characters' | 'off_topic' | 'no_period' | 'unsupported' |
  'model_reject' | 'invalid_output' | 'out_of_range' | 'unavailable';

type Period = 'today' | 'yesterday' | 'weekend' | 'last_days' | 'days_ago' | 'dates';

export interface RequestAnalysis {
  ok: boolean;
  reason: RejectReason | null;
  word: string;
  text: string;
  periods: Period[];
  numbers: number[];
  days: number[];
  months: number[];
  year: number;
  kinds: ItemKind[];
  grammar: string;
}

export interface RangeProposal {
  ok: boolean;
  reason: RejectReason | null;
  preset: PresetKey;
  range: TimeRange;
  kinds: ItemKind[];
}

// Short function words and fillers, matched exactly.
const WORDS: string[] = [
  'a', 'an', 'the', 'and', 'or', 'of', 'in', 'on', 'from', 'to', 'for', 'me', 'my', 'please', 'only', 'these',
  'this', 'those', 'all', 'is', 'are', 'be', 'can', 'could', 'would', 'want', 'ok', 'okay', 'hey', 'hello', 'thanks',
  'thank', 'you', 'day', 'days', 'year', 'years'
];

// Domain stems, matched as word prefixes.
const STEMS: string[] = [
  'photo', 'picture', 'image', 'gallery', 'share', 'show', 'display', 'send', 'give', 'select', 'choose', 'set', 'open',
  'keep', 'today', 'yesterday', 'daybeforeyesterday', 'weekend', 'saturday', 'sunday', 'last', 'previous', 'recent', 'past', 'week', 'note',
  'pdf', 'document', 'file', 'month', 'ago', 'before', 'period', 'range', 'date', 'january', 'february', 'march', 'april',
  'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'
];

// Which item kinds a word names; a request naming none covers all kinds.
const KIND_STEMS: Map<string, ItemKind[]> = new Map<string, ItemKind[]>([
  ['photo', ['photo']], ['picture', ['photo']], ['image', ['photo']], ['gallery', ['photo']],
  ['note', ['note']], ['pdf', ['pdf']], ['document', ['note', 'pdf']], ['file', ['note', 'pdf']]
]);

const MONTH_STEMS: string[] = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september',
  'october', 'november', 'december'];

// A Map, not an object literal: "constructor" must not look like a known word.
const NUMERALS: Map<string, number> = new Map<string, number>([
  ['one', 1], ['two', 2], ['three', 3], ['four', 4], ['five', 5], ['six', 6], ['seven', 7], ['eight', 8],
  ['nine', 9], ['ten', 10], ['eleven', 11], ['twelve', 12], ['thirteen', 13], ['fourteen', 14], ['fifteen', 15],
  ['twenty', 20], ['thirty', 30]
]);

function toAscii(text: string): string {
  return text.toLowerCase();
}

function startsWithAny(word: string, stems: string[]): boolean {
  return stems.some((stem: string) => word.startsWith(stem));
}

function isWeekWord(word: string): boolean {
  return word === 'week' || word === 'weeks';
}

function isMonthUnit(word: string): boolean {
  return word.startsWith('month');
}

function addUnique(list: number[], value: number): void {
  if (!list.includes(value)) {
    list.push(value);
  }
}

function rejected(reason: RejectReason, text: string, word: string): RequestAnalysis {
  return {
    ok: false, reason: reason, word: word, text: text, periods: [], numbers: [], days: [], months: [], year: 0,
    kinds: [], grammar: ''
  };
}

function pad(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function alternatives(values: string[]): string {
  return values.map((value: string) => `"${value}"`).join(' | ');
}

const SHARE = '"{\\"intent\\":\\"share\\",\\"period\\":\\""';

// GBNF that only allows "reject" or periods built from values found in the request.
export function buildGrammar(periods: Period[], numbers: number[], days: number[], months: number[]): string {
  const rules: string[] = ['reject ::= "{\\"intent\\":\\"reject\\"}"'];
  const roots: string[] = ['reject'];
  const simple = periods.filter((period: Period) => period === 'today' || period === 'yesterday' ||
    period === 'weekend');
  if (simple.length > 0) {
    roots.push('simple');
    rules.push(`simple ::= ${SHARE} (${alternatives(simple)}) "\\"}"`);
  }
  const counted = periods.filter((period: Period) => period === 'last_days' || period === 'days_ago');
  if (counted.length > 0 && numbers.length > 0) {
    roots.push('counted');
    rules.push(`counted ::= ${SHARE} (${alternatives(counted)}) "\\",\\"n\\":" num "}"`);
    rules.push(`num ::= ${alternatives(numbers.map((value: number) => `${value}`))}`);
  }
  if (periods.includes('dates') && days.length > 0 && months.length > 0) {
    roots.push('dates');
    rules.push(`dates ::= ${SHARE} "dates\\",\\"from\\":\\"" date "\\",\\"to\\":\\"" date "\\"}"`);
    rules.push('date ::= day "." month');
    rules.push(`day ::= ${alternatives(days.map(pad))}`);
    rules.push(`month ::= ${alternatives(months.map(pad))}`);
  }
  return [`root ::= ${roots.join(' | ')}`].concat(rules).join('\n');
}

// Deterministic gate in front of the model: length, characters, topic vocabulary and grounded values.
export function analyzeRequest(raw: string, now: number): RequestAnalysis {
  const text = raw.replace(/\s+/g, ' ').trim();
  if (text.length === 0) {
    return rejected('empty', text, '');
  }
  if (text.length > MAX_REQUEST_LENGTH) {
    return rejected('too_long', text, '');
  }
  if (!/^[0-9a-zA-Z .,!?/-]+$/.test(text)) {
    return rejected('characters', text, '');
  }

  const tokens = toAscii(text).split(/[\s,!?]+/).filter((token: string) => token.length > 0);
  const numbers: number[] = [];
  const days: number[] = [];
  const months: number[] = [];
  const years: number[] = [];
  const words: string[] = [];
  let previousNumber = -1; // "2 tygodnie" = 14 days
  for (const original of tokens) {
    const token = original.replace(/\.$/, '');
    const word = token.replace(/[^a-z]/g, '');
    if (/^[0-9]+([./-][0-9]+){0,2}$/.test(token)) {
      const parts = token.split(/[./-]/).map((part: string) => parseInt(part, 10));
      if (parts.length === 1) {
        if (parts[0] >= 2000 && parts[0] <= 2100) {
          addUnique(years, parts[0]);
        } else if (parts[0] >= 1 && parts[0] <= MAX_PERIOD_DAYS) {
          addUnique(numbers, parts[0]);
          if (parts[0] <= 31) {
            addUnique(days, parts[0]);
          }
        } else {
          return rejected('out_of_range', text, original);
        }
      } else if (token.includes('-') && parts.length === 2 && parts[0] <= 31 && parts[1] <= 31) {
        addUnique(days, parts[0]); // "1-3 October"
        addUnique(days, parts[1]);
      } else if (parts[0] >= 1 && parts[0] <= 31 && parts[1] >= 1 && parts[1] <= 12) {
        addUnique(days, parts[0]); // "12.08" or "12.08.2026"
        addUnique(months, parts[1]);
        if (parts.length === 3) {
          addUnique(years, parts[2]);
        }
      } else {
        return rejected('out_of_range', text, original);
      }
      previousNumber = parts.length === 1 ? parts[0] : -1;
      continue;
    }
    if (word.length === 0 || word !== token.replace(/-/g, '')) {
      return rejected('off_topic', text, original);
    }
    const numeral = NUMERALS.get(word);
    if (numeral !== undefined) {
      addUnique(numbers, numeral);
      addUnique(days, numeral);
      previousNumber = numeral;
      words.push(word);
      continue;
    }
    if (!WORDS.includes(word) && !startsWithAny(word, STEMS)) {
      return rejected('off_topic', text, original);
    }
    if (isWeekWord(word) || isMonthUnit(word)) {
      const unit = isWeekWord(word) ? 7 : 30;
      if (previousNumber > 0) {
        // The number counted weeks or months, so it is not a day count on its own.
        numbers.splice(numbers.indexOf(previousNumber), 1);
      }
      addUnique(numbers, previousNumber > 0 ? previousNumber * unit : unit);
    }
    const month = MONTH_STEMS.findIndex((stem: string) => word.startsWith(stem));
    if (month >= 0 && !isMonthUnit(word)) {
      addUnique(months, month + 1);
    }
    if (word === 'daybeforeyesterday') {
      addUnique(numbers, 2);
    }
    previousNumber = -1;
    words.push(word);
  }
  if (years.length > 1) {
    return rejected('unsupported', text, '');
  }

  const has = (stems: string[]): boolean => words.some((word: string) => startsWithAny(word, stems));
  const periods: Period[] = [];
  if (has(['today'])) {
    periods.push('today');
  }
  if (has(['yesterday'])) {
    periods.push('yesterday');
  }
  if (has(['weekend', 'saturday', 'sunday'])) {
    periods.push('weekend');
  }
  const recent = has(['last', 'previous', 'recent', 'past']);
  const ago = has(['ago', 'before', 'daybeforeyesterday']);
  // A bare number is a date ("from 1 to 3 October"), not a count, unless a unit or keyword says so.
  const counted = numbers.length > 0 && (recent || ago || has(['day', 'week', 'month']));
  if (counted && (recent || !ago)) {
    periods.push('last_days');
  }
  if (counted && (ago || !recent)) {
    periods.push('days_ago');
  }
  if (days.length > 0 && months.length > 0) {
    periods.push('dates');
  }
  if (periods.length === 0) {
    return rejected('no_period', text, '');
  }
  const named: ItemKind[] = [];
  words.forEach((word: string) => KIND_STEMS.forEach((wordKinds: ItemKind[], stem: string) => {
    if (word.startsWith(stem)) {
      named.push(...wordKinds);
    }
  }));
  const kinds = ALL_KINDS.filter((kind: ItemKind) => named.includes(kind));
  const year = years.length === 1 ? years[0] : 0;
  if (year > new Date(now).getFullYear()) {
    return rejected('out_of_range', text, `${year}`);
  }
  return {
    ok: true, reason: null, word: '', text: text, periods: periods, numbers: numbers, days: days, months: months,
    year: year, kinds: kinds.length > 0 ? kinds : ALL_KINDS.slice(), grammar: buildGrammar(periods, numbers, days, months)
  };
}

function rejectProposal(reason: RejectReason): RangeProposal {
  return { ok: false, reason: reason, preset: 'custom', range: { start: 0, end: 0 }, kinds: [] };
}

function shiftDays(dayStart: number, days: number): number {
  const date = new Date(dayStart);
  date.setDate(date.getDate() + days);
  return date.getTime();
}

// Calendar day at local midnight, or -1 for dates such as 31.02.
function calendarDay(year: number, month: number, day: number): number {
  const date = new Date(year, month - 1, day);
  return date.getMonth() === month - 1 && date.getDate() === day ? date.getTime() : -1;
}

function parseDayMonth(value: Object | undefined, analysis: RequestAnalysis): number[] | null {
  if (typeof value !== 'string' || !/^[0-9]{2}\.[0-9]{2}$/.test(value)) {
    return null;
  }
  const day = parseInt(value.substring(0, 2), 10);
  const month = parseInt(value.substring(3, 5), 10);
  return analysis.days.includes(day) && analysis.months.includes(month) ? [day, month] : null;
}

function countedRange(period: Period, n: number, today: number): TimeRange {
  return period === 'last_days' ? dayRange(shiftDays(today, -(n - 1)), today) :
    dayRange(shiftDays(today, -n), shiftDays(today, -n));
}

function datesRange(from: number[], to: number[], analysis: RequestAnalysis, today: number): RangeProposal {
  const currentYear = new Date(today).getFullYear();
  let toYear = analysis.year > 0 ? analysis.year : currentYear;
  let end = calendarDay(toYear, to[1], to[0]);
  if (analysis.year === 0 && end > today) {
    toYear -= 1; // "12.11" asked in October means last November
    end = calendarDay(toYear, to[1], to[0]);
  }
  let start = calendarDay(toYear, from[1], from[0]);
  if (start > end && end >= 0) {
    start = calendarDay(toYear - 1, from[1], from[0]); // "28.12 - 03.01"
  }
  if (start < 0 || end < 0) {
    return rejectProposal('invalid_output');
  }
  if (start > today || shiftDays(start, MAX_PERIOD_DAYS) <= end) {
    return rejectProposal('out_of_range');
  }
  return { ok: true, reason: null, preset: 'custom', range: dayRange(start, Math.min(end, today)), kinds: analysis.kinds };
}

// Checks the model's JSON against the request analysis and turns it into a period proposal.
export function interpretOutput(output: string, analysis: RequestAnalysis, now: number): RangeProposal {
  if (!analysis.ok) {
    return rejectProposal(analysis.reason ?? 'invalid_output');
  }
  let parsed: Record<string, Object> = {};
  try {
    const value: Object = JSON.parse(output) as Object;
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      return rejectProposal('invalid_output');
    }
    parsed = value as Record<string, Object>;
  } catch (error) {
    return rejectProposal('invalid_output');
  }
  const keys = Object.keys(parsed).sort().join(',');
  if (parsed['intent'] === 'reject' && keys === 'intent') {
    return rejectProposal('model_reject');
  }
  const period = parsed['period'] as Period;
  if (parsed['intent'] !== 'share' || !analysis.periods.includes(period)) {
    return rejectProposal('invalid_output');
  }
  const today = startOfDay(now);
  if (period === 'today' || period === 'yesterday' || period === 'weekend') {
    if (keys !== 'intent,period') {
      return rejectProposal('invalid_output');
    }
    return { ok: true, reason: null, preset: period, range: presetRange(period, now), kinds: analysis.kinds };
  }
  if (period === 'last_days' || period === 'days_ago') {
    const n = parsed['n'];
    if (keys !== 'intent,n,period' || typeof n !== 'number' || !Number.isInteger(n) ||
      !analysis.numbers.includes(n)) {
      return rejectProposal('invalid_output');
    }
    if (n < 1 || n > MAX_PERIOD_DAYS) {
      return rejectProposal('out_of_range');
    }
    return { ok: true, reason: null, preset: 'custom', range: countedRange(period, n, today), kinds: analysis.kinds };
  }
  const from = parseDayMonth(parsed['from'], analysis);
  const to = parseDayMonth(parsed['to'], analysis);
  if (keys !== 'from,intent,period,to' || from === null || to === null) {
    return rejectProposal('invalid_output');
  }
  return datesRange(from, to, analysis, today);
}

export function rejectMessage(reason: RejectReason, word: string): string {
  switch (reason) {
    case 'empty':
      return 'Enter the period to show, e.g. “photos from the last 3 days”.';
    case 'too_long':
      return `The request is too long (max. ${MAX_REQUEST_LENGTH} characters).`;
    case 'characters':
      return 'The request contains unsupported characters. Use letters, digits and standard punctuation.';
    case 'off_topic':
      return `“${word}” is not related to selecting photos, notes or PDFs. Describe a period, e.g. “photos from the weekend”.`;
    case 'no_period':
      return 'No period was found in the request. Enter a day, number of days or dates.';
    case 'unsupported':
      return 'Enter a period within one year or select dates manually.';
    case 'model_reject':
      return 'This request is not about selecting files by time, so it was rejected.';
    case 'out_of_range':
      return `The period must be in the past and no longer than ${MAX_PERIOD_DAYS} days.`;
    case 'unavailable':
      return 'The AI assistant is unavailable on this device. Select a period using the buttons.';
    default:
      return 'The period could not be determined. Clarify the request or select dates manually.';
  }
}
