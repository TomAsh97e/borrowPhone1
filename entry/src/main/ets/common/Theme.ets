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
  statusBarContent: '#FFFFFF'
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
  statusBarContent: '#000000'
};

export const AMBER = '#FBBF24';
export const EMERALD = '#34D399';
export const DANGER = '#EF4444';
