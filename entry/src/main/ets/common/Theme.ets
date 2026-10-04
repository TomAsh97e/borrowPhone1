// Zinc-based palettes mirroring the SafeShare web design (Tailwind zinc/amber/emerald).
export interface Palette {
  page: string;
  container: string;
  surface: string;
  surfaceHover: string;
  border: string;
  text: string;
  textMuted: string;
  primary: string;
  onPrimary: string;
  selectedSubtitle: string;
  okBg: string;
  okBorder: string;
  okText: string;
  warnBg: string;
  warnBorder: string;
  warnText: string;
  errorBg: string;
  errorText: string;
  statusBarContent: string;
  // Translucent layers, drawn over blurred content behind them.
  glass: string;
  surfaceGlass: string;
  sheet: string;
  scrim: string;
  fadeFrom: string;
  fadeTo: string;
  warnGlass: string;
  // Guest viewer: tint over the blurred photo backdrop, fades behind the controls and the controls.
  viewerScrim: string;
  viewerFade: string;
  viewerFadeClear: string;
  viewerGlass: string;
  viewerBorder: string;
  viewerText: string;
  viewerMuted: string;
}

export const DARK: Palette = {
  page: '#000000',
  container: '#09090B',
  surface: '#18181B',
  surfaceHover: '#27272A',
  border: '#27272A',
  text: '#F4F4F5',
  textMuted: '#A1A1AA',
  primary: '#FFFFFF',
  onPrimary: '#09090B',
  selectedSubtitle: '#52525B',
  okBg: '#022C22',
  okBorder: '#065F46',
  okText: '#6EE7B7',
  warnBg: '#271A05',
  warnBorder: '#92400E',
  warnText: '#FCD34D',
  errorBg: '#3B0A0A',
  errorText: '#FCA5A5',
  statusBarContent: '#FFFFFF',
  glass: '#BF09090B',
  surfaceGlass: '#B318181B',
  sheet: '#E618181B',
  scrim: '#8C000000',
  fadeFrom: '#0009090B',
  fadeTo: '#F209090B',
  warnGlass: '#D9451A03',
  viewerScrim: '#9909090B',
  viewerFade: '#99000000',
  viewerFadeClear: '#00000000',
  viewerGlass: '#8018181B',
  viewerBorder: '#26FFFFFF',
  viewerText: '#FFFFFF',
  viewerMuted: '#A1A1AA'
};

export const LIGHT: Palette = {
  page: '#FAFAFA',
  container: '#FFFFFF',
  surface: '#F4F4F5',
  surfaceHover: '#E4E4E7',
  border: '#E4E4E7',
  text: '#18181B',
  textMuted: '#71717A',
  primary: '#18181B',
  onPrimary: '#FFFFFF',
  selectedSubtitle: '#D4D4D8',
  okBg: '#ECFDF5',
  okBorder: '#A7F3D0',
  okText: '#047857',
  warnBg: '#FFFBEB',
  warnBorder: '#FDE68A',
  warnText: '#B45309',
  errorBg: '#FEE2E2',
  errorText: '#B91C1C',
  statusBarContent: '#000000',
  glass: '#BFFFFFFF',
  surfaceGlass: '#B3F4F4F5',
  sheet: '#EBFFFFFF',
  scrim: '#5918181B',
  fadeFrom: '#00FFFFFF',
  fadeTo: '#F2FFFFFF',
  warnGlass: '#E6FFFBEB',
  viewerScrim: '#A6FAFAFA',
  viewerFade: '#B3FFFFFF',
  viewerFadeClear: '#00FFFFFF',
  viewerGlass: '#99FFFFFF',
  viewerBorder: '#1A000000',
  viewerText: '#18181B',
  viewerMuted: '#52525B'
};

export const AMBER = '#FBBF24';
export const EMERALD = '#34D399';
export const DANGER = '#EF4444';
