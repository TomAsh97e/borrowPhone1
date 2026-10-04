// Checks of note/PDF import rules.
import './ts_resolve.mjs';
import assert from 'node:assert/strict';

const { displayName, hasPdfHeader, isPlainText, kindOfFileName, pdfCreationDate } =
  await import('../entry/src/main/ets/model/Documents.ts');

assert.equal(kindOfFileName('Report.PDF'), 'pdf');
assert.equal(kindOfFileName('list.md'), 'note');
assert.equal(kindOfFileName('shopping.txt'), 'note');
assert.equal(kindOfFileName('photo.jpg'), null);
assert.equal(kindOfFileName('pdf'), null);
assert.equal(displayName('shopping.txt'), 'shopping');
assert.equal(displayName('.hidden'), '.hidden');

const bytes = (text) => new TextEncoder().encode(text);
assert.equal(hasPdfHeader(bytes('%PDF-1.7\n')), true);
assert.equal(hasPdfHeader(bytes('\n\n%PDF-1.4')), true);
assert.equal(hasPdfHeader(bytes('<html>%PD')), false);
assert.equal(hasPdfHeader(bytes('')), false);

const now = Date.UTC(2026, 9, 4, 12);
assert.equal(pdfCreationDate("/CreationDate (D:20260915103000+02'00')", now), Date.UTC(2026, 8, 15, 8, 30));
assert.equal(pdfCreationDate('/CreationDate(D:20260915103000Z)', now), Date.UTC(2026, 8, 15, 10, 30));
assert.equal(pdfCreationDate("/CreationDate (D:20260915103000-05'00')", now), Date.UTC(2026, 8, 15, 15, 30));
assert.equal(pdfCreationDate('/CreationDate (D:2026)', now), new Date(2026, 0, 1).getTime());
assert.equal(pdfCreationDate('/CreationDate (D:20261399)', now), null);
assert.equal(pdfCreationDate('/CreationDate (D:20301201)', now), null);
assert.equal(pdfCreationDate('/ModDate (D:20260915)', now), null);

assert.equal(isPlainText('Shopping list: milk'), true);
assert.equal(isPlainText('MZ\u0000\u0000'), false);
console.log('Documents checks passed.');
