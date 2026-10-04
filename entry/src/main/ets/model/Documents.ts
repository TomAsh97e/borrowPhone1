// Rules for notes (.txt/.md) and PDFs imported into the app's vault.

export type ItemKind = 'photo' | 'note' | 'pdf';

export const ALL_KINDS: ItemKind[] = ['photo', 'note', 'pdf'];
export const MAX_NOTE_BYTES = 512 * 1024;
export const MAX_PDF_BYTES = 50 * 1024 * 1024;
export const MAX_VAULT_ITEMS = 200;

export function kindOfFileName(name: string): ItemKind | null {
  const lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) {
    return 'pdf';
  }
  return lower.endsWith('.txt') || lower.endsWith('.md') ? 'note' : null;
}

export function displayName(name: string): string {
  const dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

// "%PDF-" must appear within the first 1024 bytes (PDF 32000-1, 7.5.2 tolerates leading bytes).
export function hasPdfHeader(head: Uint8Array): boolean {
  const limit = Math.min(head.length, 1024) - 5;
  for (let index = 0; index <= limit; index++) {
    if (head[index] === 0x25 && head[index + 1] === 0x50 && head[index + 2] === 0x44 && head[index + 3] === 0x46 &&
      head[index + 4] === 0x2d) {
      return true;
    }
  }
  return false;
}

// The Info dictionary's /CreationDate (D:YYYYMMDDHHmmSSOHH'mm'), or null when absent or implausible.
// The file system keeps no creation time, so this is the only real "created" date of a PDF.
export function pdfCreationDate(text: string, now: number): number | null {
  const match = /\/CreationDate\s*\(\s*D:(\d{4})(\d{2})?(\d{2})?(\d{2})?(\d{2})?(\d{2})?([Zz+-])?(\d{2})?'?(\d{2})?/
    .exec(text);
  if (match === null) {
    return null;
  }
  const part = (value: string | undefined, fallback: number): number => value === undefined ? fallback :
    parseInt(value, 10);
  const year = part(match[1], 0);
  const month = part(match[2], 1);
  const day = part(match[3], 1);
  const hour = part(match[4], 0);
  const minute = part(match[5], 0);
  const second = part(match[6], 0);
  if (year < 1990 || month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  let time: number;
  const zone = match[7];
  if (zone === undefined) {
    time = new Date(year, month - 1, day, hour, minute, second).getTime();
  } else {
    const offset = (part(match[8], 0) * 60 + part(match[9], 0)) * 60000;
    time = Date.UTC(year, month - 1, day, hour, minute, second) - (zone === '+' ? offset : zone === '-' ? -offset : 0);
  }
  return time <= now + 86400000 ? time : null;
}

// Only full UTF-8 text without NUL bytes counts as a note.
export function isPlainText(text: string): boolean {
  return !text.includes('\u0000');
}
