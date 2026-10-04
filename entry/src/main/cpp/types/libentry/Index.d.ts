// Resolves with the model's grammar-constrained JSON; rejects when the model cannot run.
export const parseRange: (modelPath: string, request: string, grammar: string) => Promise<string>;
// Copies `length` bytes at `offset` of `fd` (a raw-file descriptor) to `destPath` via a temporary file.
export const installModel: (fd: number, offset: number, length: number, destPath: string) => Promise<string>;
export const releaseModel: () => void;
