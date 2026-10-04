import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  displayName, hasPdfHeader, isPlainText, ItemKind, kindOfFileName, MAX_NOTE_BYTES, MAX_PDF_BYTES, MAX_VAULT_ITEMS,
  pdfCreationDate
} from '../model/Documents';

// Notes and PDFs the owner imported. Other apps' files cannot be listed on a phone and picker URIs
// stay readable only briefly, so each picked file is validated and copied into the app sandbox.

const VAULT_DIR = 'vault';
const INDEX_FILE = 'index.json';
const PDF_METADATA_BYTES = 64 * 1024;
const MAX_PICK = 20;

export class VaultItem {
  id: string;
  kind: ItemKind;
  name: string;
  createdAt: number;
  size: number;
  path: string;

  constructor(id: string, kind: ItemKind, name: string, createdAt: number, size: number, path: string) {
    this.id = id;
    this.kind = kind;
    this.name = name;
    this.createdAt = createdAt;
    this.size = size;
    this.path = path;
  }
}

export class ImportResult {
  items: VaultItem[];
  message: string;

  constructor(items: VaultItem[], message: string) {
    this.items = items;
    this.message = message;
  }
}

interface VaultRecord {
  id: string;
  kind: string;
  name: string;
  createdAt: number;
  size: number;
}

function vaultDir(context: common.UIAbilityContext): string {
  return `${context.filesDir}/${VAULT_DIR}`;
}

function itemPath(context: common.UIAbilityContext, id: string, kind: ItemKind): string {
  return `${vaultDir(context)}/${id}.${kind === 'pdf' ? 'pdf' : 'txt'}`;
}

function newestFirst(items: VaultItem[]): VaultItem[] {
  return items.sort((left: VaultItem, right: VaultItem) => right.createdAt - left.createdAt);
}

export async function loadVault(context: common.UIAbilityContext): Promise<VaultItem[]> {
  const index = `${vaultDir(context)}/${INDEX_FILE}`;
  if (!fileIo.accessSync(index)) {
    return [];
  }
  const records = JSON.parse(await fileIo.readText(index)) as VaultRecord[];
  const items: VaultItem[] = [];
  for (const record of records) {
    if ((record.kind === 'note' || record.kind === 'pdf') && /^[0-9a-f-]{36}$/.test(record.id)) {
      const kind: ItemKind = record.kind === 'pdf' ? 'pdf' : 'note';
      const path = itemPath(context, record.id, kind);
      if (fileIo.accessSync(path)) {
        items.push(new VaultItem(record.id, kind, record.name, record.createdAt, record.size, path));
      }
    }
  }
  return newestFirst(items);
}

async function saveIndex(context: common.UIAbilityContext, items: VaultItem[]): Promise<void> {
  const records: VaultRecord[] = items.map((item: VaultItem) => {
    const record: VaultRecord = {
      id: item.id, kind: item.kind, name: item.name, createdAt: item.createdAt, size: item.size
    };
    return record;
  });
  const index = `${vaultDir(context)}/${INDEX_FILE}`;
  const file = await fileIo.open(`${index}.part`, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC |
    fileIo.OpenMode.WRITE_ONLY);
  try {
    await fileIo.write(file.fd, JSON.stringify(records));
    await fileIo.fsync(file.fd);
  } finally {
    await fileIo.close(file);
  }
  await fileIo.rename(`${index}.part`, index);
}

function readBytes(fd: number, offset: number, length: number): Uint8Array {
  const buffer = new ArrayBuffer(length);
  const read = fileIo.readSync(fd, buffer, { offset: offset, length: length });
  return new Uint8Array(buffer, 0, read);
}

function latin1(bytes: Uint8Array): string {
  let text = '';
  for (let index = 0; index < bytes.length; index += 4096) {
    text += String.fromCharCode(...Array.from(bytes.subarray(index, index + 4096)));
  }
  return text;
}

// Returns the creation time, or the reason why the file was skipped.
function inspect(fd: number, kind: ItemKind, size: number, modified: number): number | string {
  if (size === 0) {
    return 'empty file';
  }
  if (kind === 'note') {
    if (size > MAX_NOTE_BYTES) {
      return 'note larger than 512 KB';
    }
    try {
      const decoder = util.TextDecoder.create('utf-8', { fatal: true });
      if (!isPlainText(decoder.decodeToString(readBytes(fd, 0, size)))) {
        return 'not plain text';
      }
    } catch (error) {
      return 'not UTF-8 text';
    }
    return modified;
  }
  if (size > MAX_PDF_BYTES) {
    return 'PDF larger than 50 MB';
  }
  const head = readBytes(fd, 0, Math.min(size, PDF_METADATA_BYTES));
  if (!hasPdfHeader(head)) {
    return 'not a PDF file';
  }
  const tail = size > PDF_METADATA_BYTES ? readBytes(fd, Math.max(PDF_METADATA_BYTES, size - PDF_METADATA_BYTES),
    PDF_METADATA_BYTES) : new Uint8Array(0);
  return pdfCreationDate(latin1(tail), Date.now()) ?? pdfCreationDate(latin1(head), Date.now()) ?? modified;
}

async function importOne(context: common.UIAbilityContext, uri: string, kind: ItemKind): Promise<VaultItem | string> {
  const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
  try {
    const name = file.name;
    if (kindOfFileName(name) !== kind) {
      return `${name}: wrong file type`;
    }
    const stat = await fileIo.stat(file.fd);
    const created = inspect(file.fd, kind, stat.size, stat.mtime * 1000);
    if (typeof created === 'string') {
      return `${name}: ${created}`;
    }
    const id = util.generateRandomUUID(false);
    const path = itemPath(context, id, kind);
    await fileIo.copyFile(file.fd, path);
    return new VaultItem(id, kind, displayName(name), created, stat.size, path);
  } finally {
    await fileIo.close(file);
  }
}

// Lets the owner pick .txt/.md notes or PDFs, then copies the valid ones into the vault.
export async function importDocuments(context: common.UIAbilityContext, kind: ItemKind, current: VaultItem[]):
  Promise<ImportResult> {
  const options = new picker.DocumentSelectOptions();
  // One suffix per entry: the emulator's picker only honours the last suffix of "Notes|.txt,.md".
  options.fileSuffixFilters = kind === 'pdf' ? ['PDF|.pdf'] : ['Notes .txt|.txt', 'Notes .md|.md'];
  options.maxSelectNumber = MAX_PICK;
  const uris = await new picker.DocumentViewPicker(context).select(options);
  if (uris.length === 0) {
    return new ImportResult(current, '');
  }
  if (!fileIo.accessSync(vaultDir(context))) {
    fileIo.mkdirSync(vaultDir(context));
  }
  const items = current.slice();
  const problems: string[] = [];
  let imported = 0;
  for (const uri of uris) {
    if (items.length >= MAX_VAULT_ITEMS) {
      problems.push(`vault limit of ${MAX_VAULT_ITEMS} files`);
      break;
    }
    try {
      const result = await importOne(context, uri, kind);
      if (typeof result === 'string') {
        problems.push(result);
      } else if (items.some((item: VaultItem) => item.name === result.name && item.size === result.size)) {
        await fileIo.unlink(result.path);
        problems.push(`${result.name}: already in the vault`);
      } else {
        items.push(result);
        imported++;
      }
    } catch (error) {
      problems.push(`could not read file (${(error as BusinessError).code})`);
    }
  }
  if (imported > 0) {
    await saveIndex(context, items);
  }
  const summary = `Imported: ${imported}.`;
  return new ImportResult(newestFirst(items), problems.length > 0 ? `${summary} Skipped: ${problems.join('; ')}.` :
    summary);
}

export async function removeDocument(context: common.UIAbilityContext, items: VaultItem[], id: string):
  Promise<VaultItem[]> {
  const remaining = items.filter((item: VaultItem) => item.id !== id);
  await saveIndex(context, remaining);
  const removed = items.find((item: VaultItem) => item.id === id);
  if (removed !== undefined) {
    await fileIo.unlink(removed.path).catch(() => {});
  }
  return remaining;
}

export async function readNote(item: VaultItem): Promise<string> {
  return fileIo.readText(item.path, { length: MAX_NOTE_BYTES });
}
