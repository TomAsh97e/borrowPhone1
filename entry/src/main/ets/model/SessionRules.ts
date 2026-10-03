export interface DisplaySize {
  width: number;
  height: number;
}

export function hasValidSelection(uris: string[], limit: number): boolean {
  if (uris.length < 1 || uris.length > limit) {
    return false;
  }
  for (let index = 0; index < uris.length; index++) {
    if (uris.indexOf(uris[index]) !== index) {
      return false;
    }
  }
  return true;
}

export function fitSize(width: number, height: number, maxEdge: number): DisplaySize {
  if (width < 1 || height < 1 || maxEdge < 1) {
    throw new Error('Invalid image dimensions');
  }
  const scale = Math.min(1, maxEdge / Math.max(width, height));
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale))
  };
}

export function clampIndex(index: number, count: number): number {
  return Math.max(0, Math.min(index, Math.max(0, count - 1)));
}

export function isValidPin(pin: string): boolean {
  return /^\d{6}$/.test(pin);
}

export function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  let difference = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index++) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return difference === 0;
}
