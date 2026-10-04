// Size scaling for the current window. UI sizes are written for a 392 vp wide phone (the web design's
// reference width) and multiplied by these factors, so the layout keeps its proportions on smaller and
// larger screens.
const BASE_WIDTH = 392;
// Height of the PIN card at scale 1, including some breathing room around it.
const PIN_CARD_HEIGHT = 720;
const PHONE_ASPECT = 1.7;

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

// Phone-shaped screens (long side at least 1.7× the short side) scale with their short side, so a large or
// low-density phone shows the same layout bigger instead of tiny text. Tablets and unfolded foldables get a
// moderate scale and more grid columns instead.
export function uiScale(screenWidth: number, screenHeight: number): number {
  const shortSide = Math.min(screenWidth, screenHeight);
  const longSide = Math.max(screenWidth, screenHeight);
  const max = longSide / shortSide >= PHONE_ASPECT ? 2 : 1.3;
  return clamp(shortSide / BASE_WIDTH, 0.85, max);
}

// The PIN pad must fit on short screens (and in landscape) without scrolling.
export function pinScale(ui: number, height: number): number {
  return Math.max(0.55, Math.min(ui, height / PIN_CARD_HEIGHT));
}

// Three columns on phones, more on tablets and in landscape.
export function gridColumns(width: number, ui: number): number {
  return clamp(Math.floor(width / (120 * ui)), 3, 8);
}

// Period buttons: 2×2 on phones, one row of 4 when the window is wide at the current scale.
export function presetColumns(width: number, ui: number): number {
  return width / ui >= 600 ? 4 : 2;
}
