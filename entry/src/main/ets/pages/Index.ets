import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { formatDateTime, formatDay, formatRangeShort } from '../common/Format';
import { gridColumns, pinScale, presetColumns, uiScale } from '../common/Layout';
import { AMBER, DANGER, DARK, EMERALD, LIGHT, Palette } from '../common/Theme';
import {
  dayRange, isInRange, isValidPin, PIN_LENGTH, PresetKey, presetRange, startOfDay, TimeRange
} from '../model/SessionRules';
import { AppStore, PinCheck } from '../service/AppStore';
import { GalleryPhoto, loadPhotos, readCameraModel, requestGalleryAccess } from '../service/Gallery';
import { hapticAlarm, hapticLock, hapticTap, hapticUnlock } from '../service/Haptics';

const BOUNDARY_ALERT_MS = 3000;
const SWIPE_DISTANCE = 40;
const ZOOM_SCALE = 1.5;
// Blur radius (px) behind translucent bars, sheets and dialogs, and of the guest photo backdrop.
const GLASS_BLUR = 40;
const AMBIENT_BLUR = 30;
const FADE_MS = 220;
const SCREEN_FADE_MS = 380;

enum Access {
  LOADING,
  GRANTED,
  DENIED,
  ERROR
}

enum PinMode {
  NONE,
  CREATE,
  CONFIRM,
  EXIT,
  PANIC,
  RESUME
}

class PresetOption {
  key: PresetKey;
  label: string;
  icon: Resource;
  iconColor: string;
  subtitle: string;

  constructor(key: PresetKey, label: string, icon: Resource, iconColor: string, subtitle: string) {
    this.key = key;
    this.label = label;
    this.icon = icon;
    this.iconColor = iconColor;
    this.subtitle = subtitle;
  }
}

const PRESETS: PresetOption[] = [
  new PresetOption('today', 'Dzisiaj', $r('sys.symbol.calendar'), '#EF4444', 'Bieżący dzień'),
  new PresetOption('yesterday', 'Wczoraj', $r('sys.symbol.clock'), '#60A5FA', 'Poprzedni dzień'),
  new PresetOption('weekend', 'Weekend', $r('sys.symbol.sunset_fill'), '#F97316', 'Ostatni weekend'),
  new PresetOption('custom', 'Własny zakres', $r('sys.symbol.slider_horizontal_2'), '#A1A1AA', 'Wybierz daty')
];

const KEYPAD_ROWS: string[][] = [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']];
const PIN_SLOTS: number[] = [0, 1, 2, 3];

@Entry
@Component
struct Index {
  @StorageLink('privacyReady') private privacyReady: boolean = false;
  @StorageLink('interruptionEpoch') @Watch('onInterrupted') private interruptionEpoch: number = 0;

  @State private winWidth: number = 392;
  @State private winHeight: number = 800;
  @State private ui: number = 1;
  @State private pinUi: number = 1;
  @State private topBarHeight: number = 0;

  @State private storeReady: boolean = false;
  @State private storeError: boolean = false;
  @State private pinConfigured: boolean = false;
  @State private access: Access = Access.LOADING;
  @State private photos: GalleryPhoto[] = [];
  @State private preset: PresetKey = 'weekend';
  @State private customStart: number = startOfDay(Date.now());
  @State private customEnd: number = startOfDay(Date.now());

  @State private darkTheme: boolean = true;
  @State private preventLeave: boolean = true;
  @State private showDetails: boolean = false;

  @State private settingsOpen: boolean = false;
  @State private guideOpen: boolean = false;
  @State private currentPinInput: string = '';
  @State private newPinInput: string = '';
  @State private settingsError: string = '';
  @State private settingsSuccess: string = '';

  @State private detailIndex: number = -1;
  @State private detailCamera: string = '';

  @State private pinMode: PinMode = PinMode.NONE;
  @State private pinEntry: string = '';
  @State private pinMessage: string = '';
  @State private pinFeedback: string = '';
  @State private pinError: boolean = false;
  @State private pinBusy: boolean = false;
  @State private pinAttempts: number = 0;
  @State private pinHintOpen: boolean = false;
  @State private shakeOffset: number = 0;

  @State private guestMode: boolean = false;
  @State private guestPhotos: GalleryPhoto[] = [];
  @State private guestIndex: number = 0;
  @State private guestZoom: number = 1;
  @State private guestInfoOpen: boolean = false;
  @State private guestCamera: string = '';
  @State private guestRangeLabel: string = '';
  @State private lockedCount: number = 0;
  @State private slideFrom: number = 0;
  @State private boundaryAlert: string = '';

  private store: AppStore = new AppStore();
  private pinFirst: string = '';
  private boundaryTimer: number = -1;

  aboutToAppear(): void {
    this.measureDisplay();
    this.initialize();
  }

  aboutToDisappear(): void {
    clearTimeout(this.boundaryTimer);
  }

  onPageShow(): void {
    if (!this.guestMode && this.access === Access.GRANTED) {
      this.reloadPhotos();
    }
  }

  onBackPress(): boolean {
    if (this.pinMode !== PinMode.NONE) {
      if (this.isPinCancelable()) {
        this.closePin();
      }
      return true;
    }
    if (this.guestMode) {
      if (this.guestInfoOpen) {
        this.guestInfoOpen = false;
        return true;
      }
      hapticAlarm();
      this.openPin(PinMode.EXIT,
        'Próba cofnięcia / wyjścia z galerii została zablokowana! Wymagany kod PIN właściciela.');
      return true;
    }
    if (this.detailIndex >= 0) {
      this.detailIndex = -1;
      return true;
    }
    if (this.settingsOpen) {
      this.settingsOpen = false;
      return true;
    }
    return false;
  }

  // EntryAbility bumps the epoch whenever the app leaves the foreground.
  private onInterrupted(): void {
    if (!this.guestMode || !this.preventLeave || this.pinMode === PinMode.RESUME) {
      return;
    }
    this.guestInfoOpen = false;
    hapticAlarm();
    this.openPin(PinMode.PANIC, 'Wykryto przełączenie aplikacji lub próbę zminimalizowania! Ekran został zablokowany.');
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async initialize(): Promise<void> {
    try {
      await this.store.load(this.context());
      this.darkTheme = this.store.settings.darkTheme;
      this.preventLeave = this.store.settings.preventLeave;
      this.showDetails = this.store.settings.showDetailsInGuestMode;
      this.pinConfigured = this.store.hasPin();
      this.storeReady = true;
      if (this.store.guestActive) {
        // A guest session was cut short (app killed or device rebooted): owner PIN first.
        this.guestPhotos = [];
        this.guestMode = true;
        this.setImmersive(true);
        this.openPin(PinMode.RESUME, 'Sesja gościa została przerwana. Wprowadź kod PIN właściciela, aby wrócić do galerii.');
      }
    } catch (error) {
      this.storeError = true;
    }
    this.applySystemBars();
    await this.refreshGallery(false);
  }

  private async refreshGallery(afterDenial: boolean): Promise<void> {
    this.access = Access.LOADING;
    try {
      if (!(await requestGalleryAccess(this.context(), afterDenial))) {
        this.access = Access.DENIED;
        return;
      }
      this.photos = await loadPhotos(this.context());
      this.access = Access.GRANTED;
    } catch (error) {
      this.access = Access.ERROR;
    }
  }

  private async reloadPhotos(): Promise<void> {
    try {
      this.photos = await loadPhotos(this.context());
    } catch (error) {
      this.access = Access.ERROR;
    }
  }

  // First estimate before layout; the root Stack's onAreaChange then reports the real window size.
  private measureDisplay(): void {
    const screen = this.screenSize();
    this.onWindowArea(screen[0], screen[1]);
  }

  // Whole screen in vp. The scale follows the screen, not the window, so it does not jump when the system
  // bars hide in guest mode.
  private screenSize(): number[] {
    try {
      const screen = display.getDefaultDisplaySync();
      return [screen.width / screen.densityPixels, screen.height / screen.densityPixels];
    } catch (error) {
      return [this.winWidth, this.winHeight];
    }
  }

  private onWindowArea(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    const screen = this.screenSize();
    this.winWidth = width;
    this.winHeight = height;
    this.ui = uiScale(screen[0], screen[1]);
    this.pinUi = pinScale(this.ui, height);
  }

  // Sizes (vp) and font sizes (fp) scaled to the current window.
  private s(value: number): number {
    return value * this.ui;
  }

  // Same for the PIN pad, which also shrinks to fit short screens.
  private ps(value: number): number {
    return value * this.pinUi;
  }

  private presetRows(): PresetOption[][] {
    if (presetColumns(this.winWidth, this.ui) === 4) {
      return [PRESETS];
    }
    return [PRESETS.slice(0, 2), PRESETS.slice(2)];
  }

  private pal(): Palette {
    return this.darkTheme ? DARK : LIGHT;
  }

  private keyColor(): string {
    return this.darkTheme ? DARK.surfaceHover : LIGHT.surface;
  }

  private range(): TimeRange {
    return this.preset === 'custom' ? dayRange(this.customStart, this.customEnd) : presetRange(this.preset, Date.now());
  }

  private isAllowed(photo: GalleryPhoto): boolean {
    return isInRange(photo.takenAt, this.range());
  }

  private allowedPhotos(): GalleryPhoto[] {
    const range = this.range();
    return this.photos.filter((photo: GalleryPhoto) => isInRange(photo.takenAt, range));
  }

  private allowedCount(): number {
    return this.allowedPhotos().length;
  }

  private rangeLabel(): string {
    if (this.preset === 'today') {
      return 'Dzisiaj';
    }
    if (this.preset === 'yesterday') {
      return 'Wczoraj';
    }
    if (this.preset === 'weekend') {
      return 'Weekend';
    }
    return formatRangeShort(this.range());
  }

  private canHandOff(): boolean {
    return this.storeReady && this.privacyReady && this.access === Access.GRANTED && this.allowedCount() > 0;
  }

  private selectPreset(key: PresetKey): void {
    hapticTap();
    if (key === 'custom' && this.preset !== 'custom') {
      const current = this.range();
      this.customStart = current.start;
      this.customEnd = current.end;
    }
    this.preset = key;
  }

  private pickDate(isStart: boolean): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2000-01-01'),
      end: new Date(),
      selected: new Date(isStart ? this.customStart : this.customEnd),
      onDateAccept: (value: Date) => {
        if (isStart) {
          this.customStart = startOfDay(value.getTime());
        } else {
          this.customEnd = startOfDay(value.getTime());
        }
      }
    });
  }

  private async setImmersive(enabled: boolean): Promise<void> {
    try {
      const mainWindow = await window.getLastWindow(this.context());
      await mainWindow.setWindowLayoutFullScreen(enabled);
      await mainWindow.setSpecificSystemBarEnabled('status', !enabled);
      await mainWindow.setSpecificSystemBarEnabled('navigation', !enabled);
    } catch (error) {
    }
  }

  private async applySystemBars(): Promise<void> {
    try {
      const mainWindow = await window.getLastWindow(this.context());
      const properties: window.SystemBarProperties = {
        statusBarColor: this.pal().container,
        statusBarContentColor: this.pal().statusBarContent,
        navigationBarColor: this.pal().container,
        navigationBarContentColor: this.pal().statusBarContent
      };
      await mainWindow.setWindowSystemBarProperties(properties);
    } catch (error) {
    }
  }

  // ---- Guest mode -------------------------------------------------------------------------

  private startHandOff(): void {
    if (!this.canHandOff()) {
      return;
    }
    hapticTap();
    if (!this.store.hasPin()) {
      this.openPin(PinMode.CREATE, 'Wybierz 4-cyfrowy kod. Będzie potrzebny, aby wyjść z trybu gościa.');
      return;
    }
    this.enterGuest();
  }

  private enterGuest(): void {
    const allowed = this.allowedPhotos();
    if (allowed.length === 0) {
      return;
    }
    this.guestPhotos = allowed;
    this.lockedCount = this.photos.length - allowed.length;
    this.guestRangeLabel = this.rangeLabel();
    this.guestIndex = 0;
    this.slideFrom = 0;
    this.guestZoom = 1;
    this.guestInfoOpen = false;
    this.boundaryAlert = '';
    this.settingsOpen = false;
    this.detailIndex = -1;
    this.guestMode = true;
    hapticLock();
    this.setImmersive(true);
    this.store.setGuestActive(true).catch(() => {});
    this.loadGuestCamera();
  }

  private exitGuest(): void {
    clearTimeout(this.boundaryTimer);
    this.guestMode = false;
    this.guestPhotos = [];
    this.guestInfoOpen = false;
    this.boundaryAlert = '';
    this.setImmersive(false);
    this.applySystemBars();
    this.store.setGuestActive(false).catch(() => {});
    if (this.access === Access.GRANTED) {
      this.reloadPhotos();
    }
  }

  private currentGuest(): GalleryPhoto {
    return this.guestPhotos[this.guestIndex];
  }

  // The shown photo as a one-item list, so a photo change replays the enter/exit transitions.
  private guestSlide(): GalleryPhoto[] {
    return this.guestPhotos.length > 0 ? [this.currentGuest()] : [];
  }

  private showGuestPhoto(index: number): void {
    if (index === this.guestIndex) {
      return;
    }
    // The next photo slides in from the right, the previous one from the left.
    this.slideFrom = index > this.guestIndex ? this.s(80) : -this.s(80);
    this.guestIndex = index;
    this.guestZoom = 1;
    this.boundaryAlert = '';
    this.loadGuestCamera();
  }

  private nextPhoto(): void {
    if (this.guestIndex < this.guestPhotos.length - 1) {
      hapticTap();
      this.showGuestPhoto(this.guestIndex + 1);
    } else {
      hapticAlarm();
      this.showBoundary(`Koniec udostępnionych zdjęć z tego okresu. Pozostałe ${this.lockedCount} zdjęć w galerii jest zablokowane.`);
    }
  }

  private previousPhoto(): void {
    if (this.guestIndex > 0) {
      hapticTap();
      this.showGuestPhoto(this.guestIndex - 1);
    } else {
      hapticAlarm();
      this.showBoundary('Brak wcześniejszych zdjęć w wybranym przedziale. Reszta galerii jest bezpiecznie ukryta.');
    }
  }

  private handleSwipe(offsetX: number): void {
    if (offsetX <= -SWIPE_DISTANCE) {
      this.nextPhoto();
    } else if (offsetX >= SWIPE_DISTANCE) {
      this.previousPhoto();
    }
  }

  private toggleZoom(): void {
    hapticTap();
    this.guestZoom = this.guestZoom > 1 ? 1 : ZOOM_SCALE;
  }

  private showBoundary(text: string): void {
    clearTimeout(this.boundaryTimer);
    this.boundaryAlert = text;
    this.boundaryTimer = setTimeout(() => {
      this.boundaryAlert = '';
    }, BOUNDARY_ALERT_MS);
  }

  private async loadGuestCamera(): Promise<void> {
    this.guestCamera = '';
    if (!this.showDetails || this.guestPhotos.length === 0) {
      return;
    }
    const uri = this.currentGuest().uri;
    const camera = await readCameraModel(uri);
    if (this.guestMode && this.guestPhotos.length > 0 && this.currentGuest().uri === uri) {
      this.guestCamera = camera;
    }
  }

  // ---- PIN pad ----------------------------------------------------------------------------

  private openPin(mode: PinMode, message: string): void {
    this.pinMode = mode;
    this.pinEntry = '';
    this.pinError = false;
    this.pinHintOpen = false;
    this.pinMessage = message;
    this.pinFeedback = '';
    const seconds = this.store.lockSecondsLeft();
    if (seconds > 0 && mode !== PinMode.CREATE) {
      this.pinFeedback = `Zbyt wiele błędnych prób. Spróbuj ponownie za ${seconds} s.`;
    }
  }

  private closePin(): void {
    this.pinMode = PinMode.NONE;
    this.pinEntry = '';
    this.pinFirst = '';
    this.pinFeedback = '';
  }

  private isPinCancelable(): boolean {
    return this.pinMode === PinMode.EXIT || this.pinMode === PinMode.CREATE || this.pinMode === PinMode.CONFIRM;
  }

  private isPanicPin(): boolean {
    return this.pinMode === PinMode.PANIC || this.pinMode === PinMode.RESUME;
  }

  private pinTitle(): string {
    switch (this.pinMode) {
      case PinMode.CREATE:
        return 'Ustaw kod PIN';
      case PinMode.CONFIRM:
        return 'Powtórz kod PIN';
      case PinMode.PANIC:
        return 'Wykryto próbę wyjścia!';
      case PinMode.RESUME:
        return 'Galeria jest zablokowana';
      default:
        return 'Wyjście z Trybu Gościa';
    }
  }

  private pinSubtitle(): string {
    if (this.pinMessage.length > 0) {
      return this.pinMessage;
    }
    return 'Wprowadź kod PIN właściciela, aby odblokować resztę galerii telefonu.';
  }

  private pressDigit(digit: string): void {
    if (this.pinBusy || this.pinError || this.pinEntry.length >= PIN_LENGTH) {
      return;
    }
    hapticTap();
    this.pinFeedback = '';
    this.pinEntry += digit;
    if (this.pinEntry.length === PIN_LENGTH) {
      this.submitPin();
    }
  }

  private deleteDigit(): void {
    if (this.pinBusy || this.pinEntry.length === 0) {
      return;
    }
    hapticTap();
    this.pinEntry = this.pinEntry.slice(0, -1);
    this.pinError = false;
  }

  private async submitPin(): Promise<void> {
    const pin = this.pinEntry;
    if (this.pinMode === PinMode.CREATE) {
      this.pinFirst = pin;
      this.pinEntry = '';
      this.pinMode = PinMode.CONFIRM;
      this.pinMessage = 'Wpisz ten sam kod jeszcze raz.';
      return;
    }
    if (this.pinMode === PinMode.CONFIRM) {
      await this.confirmNewPin(pin);
      return;
    }

    this.pinBusy = true;
    // Let the fourth dot render before the PBKDF2 check blocks the UI thread.
    await this.delay(60);
    try {
      const result = await this.store.checkPin(pin);
      if (result === PinCheck.OK) {
        hapticUnlock();
        this.pinAttempts = 0;
        this.closePin();
        this.exitGuest();
      } else if (result === PinCheck.LOCKED) {
        this.rejectPin(`Zbyt wiele błędnych prób. Spróbuj ponownie za ${this.store.lockSecondsLeft()} s.`);
      } else {
        this.pinAttempts++;
        this.rejectPin(`Nieprawidłowy kod PIN. Pozostało prób: ${this.store.attemptsLeft()}.`);
      }
    } catch (error) {
      this.rejectPin('Nie udało się sprawdzić kodu PIN.');
    } finally {
      this.pinBusy = false;
    }
  }

  private async confirmNewPin(pin: string): Promise<void> {
    if (pin !== this.pinFirst) {
      this.pinFirst = '';
      this.pinMode = PinMode.CREATE;
      this.pinMessage = 'Wybierz 4-cyfrowy kod. Będzie potrzebny, aby wyjść z trybu gościa.';
      this.rejectPin('Kody nie są takie same. Ustaw kod PIN od nowa.');
      return;
    }
    this.pinBusy = true;
    try {
      await this.store.setPin(pin);
      this.pinConfigured = true;
      this.closePin();
      this.enterGuest();
    } catch (error) {
      this.pinMode = PinMode.CREATE;
      this.rejectPin('Nie udało się zapisać kodu PIN.');
    } finally {
      this.pinBusy = false;
    }
  }

  private rejectPin(feedback: string): void {
    hapticAlarm();
    this.pinError = true;
    this.pinFeedback = feedback;
    this.shake();
    setTimeout(() => {
      this.pinEntry = '';
      this.pinError = false;
    }, 700);
  }

  private shake(): void {
    const frames: KeyframeState[] = [
      { duration: 70, event: () => { this.shakeOffset = -8; } },
      { duration: 70, event: () => { this.shakeOffset = 8; } },
      { duration: 70, event: () => { this.shakeOffset = -8; } },
      { duration: 70, event: () => { this.shakeOffset = 8; } },
      { duration: 70, event: () => { this.shakeOffset = 0; } }
    ];
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, frames);
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  // ---- Settings ---------------------------------------------------------------------------

  private setDarkTheme(dark: boolean): void {
    hapticTap();
    this.darkTheme = dark;
    this.store.settings.darkTheme = dark;
    this.persistSettings();
    this.applySystemBars();
  }

  private setPreventLeave(enabled: boolean): void {
    this.preventLeave = enabled;
    this.store.settings.preventLeave = enabled;
    this.persistSettings();
  }

  private setShowDetails(enabled: boolean): void {
    this.showDetails = enabled;
    this.store.settings.showDetailsInGuestMode = enabled;
    this.persistSettings();
  }

  private persistSettings(): void {
    this.store.saveSettings().catch(() => {
      this.settingsError = 'Nie udało się zapisać ustawień.';
    });
  }

  private async changePin(): Promise<void> {
    this.settingsError = '';
    this.settingsSuccess = '';
    if (!isValidPin(this.newPinInput)) {
      hapticAlarm();
      this.settingsError = 'Nowy kod PIN musi składać się z 4 cyfr!';
      return;
    }
    try {
      if (this.store.hasPin()) {
        const result = await this.store.checkPin(this.currentPinInput);
        if (result !== PinCheck.OK) {
          hapticAlarm();
          this.settingsError = result === PinCheck.LOCKED ?
            `Zbyt wiele błędnych prób. Spróbuj ponownie za ${this.store.lockSecondsLeft()} s.` :
            'Podany stary kod PIN jest nieprawidłowy!';
          return;
        }
      }
      await this.store.setPin(this.newPinInput);
    } catch (error) {
      this.settingsError = 'Nie udało się zapisać kodu PIN.';
      return;
    }
    hapticUnlock();
    this.pinConfigured = true;
    this.currentPinInput = '';
    this.newPinInput = '';
    this.settingsSuccess = 'Kod PIN został pomyślnie zmieniony!';
    setTimeout(() => {
      this.settingsSuccess = '';
    }, 3500);
  }

  private openSettings(): void {
    hapticTap();
    this.currentPinInput = '';
    this.newPinInput = '';
    this.settingsError = '';
    this.settingsSuccess = '';
    this.guideOpen = false;
    this.settingsOpen = true;
  }

  // ---- Photo detail -----------------------------------------------------------------------

  private async openDetail(index: number): Promise<void> {
    this.detailIndex = index;
    this.detailCamera = '';
    const uri = this.photos[index].uri;
    const camera = await readCameraModel(uri);
    if (this.detailIndex === index && this.photos[index].uri === uri) {
      this.detailCamera = camera;
    }
  }

  // ---- Shared layers ----------------------------------------------------------------------

  // Dim, blurred layer behind dialogs; it fades in and out with them.
  @Builder
  private scrim() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal().scrim)
      .backdropBlur(GLASS_BLUR)
      .transition(TransitionEffect.opacity(0).animation({ duration: FADE_MS }))
  }

  // ---- Owner screen -----------------------------------------------------------------------

  @Builder
  private headerButton(isTheme: boolean) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(isTheme ? (this.darkTheme ? $r('sys.symbol.sun_max') : $r('sys.symbol.moon')) :
        $r('sys.symbol.gearshape'))
        .fontSize(this.s(20))
        .fontColor([isTheme && this.darkTheme ? AMBER : this.pal().text])
    }
    .width(this.s(44))
    .height(this.s(44))
    .backgroundColor(this.pal().surfaceGlass)
    // border() without a radius resets a Button's corner radius.
    .border({ width: 1, color: this.pal().border, radius: this.s(16) })
    .accessibilityText(isTheme ? (this.darkTheme ? 'Włącz jasny motyw' : 'Włącz ciemny motyw') : 'Ustawienia')
    .onClick(() => isTheme ? this.setDarkTheme(!this.darkTheme) : this.openSettings())
  }

  @Builder
  private header() {
    Row() {
      Row({ space: this.s(12) }) {
        Image($r('app.media.app_icon_lock'))
          .width(this.s(40))
          .height(this.s(40))
          .borderRadius(this.s(16))
          .objectFit(ImageFit.Cover)
          .border({ width: 2, color: this.pal().border })
        Column({ space: this.s(2) }) {
          Text('SafeShare')
            .fontSize(this.s(16))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().text)
          Row({ space: this.s(6) }) {
            Circle()
              .width(this.s(8))
              .height(this.s(8))
              .fill(EMERALD)
            Text('Galeria telefonu')
              .fontSize(this.s(12))
              .fontColor(this.pal().textMuted)
          }
        }
        .alignItems(HorizontalAlign.Start)
      }

      Blank()

      Row({ space: this.s(8) }) {
        this.headerButton(true)
        this.headerButton(false)
      }
    }
    .width('100%')
    .height(this.s(64))
    .padding({ left: this.s(16), right: this.s(16) })
    .border({ width: { bottom: 1 }, color: this.pal().border })
  }

  @Builder
  private presetButton(option: PresetOption) {
    Row() {
      Row({ space: this.s(10) }) {
        SymbolGlyph(option.icon)
          .fontSize(this.s(20))
          .fontColor([option.iconColor])
        Column() {
          Text(option.label)
            .fontSize(this.s(14))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.preset === option.key ? this.pal().onPrimary : this.pal().text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(option.subtitle)
            .fontSize(this.s(10))
            .margin({ top: this.s(2) })
            .fontColor(this.preset === option.key ? this.pal().selectedSubtitle : this.pal().textMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)

      if (this.preset === option.key) {
        Circle()
          .width(this.s(10))
          .height(this.s(10))
          .fill(EMERALD)
      }
    }
    .layoutWeight(1)
    .height(this.s(58))
    .padding(this.s(12))
    .borderRadius(this.s(16))
    .backgroundColor(this.preset === option.key ? this.pal().primary : this.pal().surfaceGlass)
    .border({ width: 1, color: this.preset === option.key ? this.pal().primary : this.pal().border })
    .animation({ duration: 150 })
    .onClick(() => this.selectPreset(option.key))
  }

  @Builder
  private dateField(isStart: boolean) {
    Column({ space: this.s(4) }) {
      Text(isStart ? 'Data początkowa (OD)' : 'Data końcowa (DO)')
        .fontSize(this.s(12))
        .fontColor(this.pal().textMuted)
      Text(formatDay(isStart ? this.customStart : this.customEnd))
        .width('100%')
        .height(this.s(44))
        .padding({ left: this.s(12), right: this.s(12) })
        .fontSize(this.s(14))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().text)
        .backgroundColor(this.pal().container)
        .borderRadius(this.s(12))
        .border({ width: 1, color: this.pal().border })
        .onClick(() => this.pickDate(isStart))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private countChip(visible: boolean) {
    Row({ space: this.s(6) }) {
      SymbolGlyph(visible ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.lock_fill'))
        .fontSize(this.s(14))
        .fontColor([visible ? this.pal().okText : this.pal().warnText])
      Text(visible ? `${this.allowedCount()} widocznych` : `${this.photos.length - this.allowedCount()} ukrytych`)
        .fontSize(this.s(12))
        .fontWeight(FontWeight.Medium)
        .fontColor(visible ? this.pal().okText : this.pal().warnText)
    }
    .padding({ left: this.s(10), right: this.s(10), top: this.s(4), bottom: this.s(4) })
    .borderRadius(this.s(8))
    .backgroundColor(visible ? this.pal().okBg : this.pal().warnBg)
    .border({ width: 1, color: visible ? this.pal().okBorder : this.pal().warnBorder })
  }

  @Builder
  private filterBar() {
    Column({ space: this.s(14) }) {
      Column({ space: this.s(8) }) {
        Text('OKRES ZDJĘĆ DO POKAZANIA:')
          .width('100%')
          .fontSize(this.s(11))
          .fontWeight(FontWeight.Bold)
          .letterSpacing(0.6)
          .fontColor(this.pal().textMuted)
        ForEach(this.presetRows(), (row: PresetOption[]) => {
          Row({ space: this.s(10) }) {
            ForEach(row, (option: PresetOption) => {
              this.presetButton(option)
            }, (option: PresetOption) => option.key)
          }
          .width('100%')
        }, (row: PresetOption[]) => `${row[0].key}-${row.length}`)
      }

      if (this.preset === 'custom') {
        Column({ space: this.s(12) }) {
          Row({ space: this.s(8) }) {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(this.s(16))
              .fontColor(['#0EA5E9'])
            Text('Wskaż zakres dat (OD - DO):')
              .fontSize(this.s(12))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal().text)
          }
          .width('100%')

          Row({ space: this.s(12) }) {
            this.dateField(true)
            this.dateField(false)
          }
          .width('100%')
        }
        .padding(this.s(16))
        .borderRadius(this.s(16))
        .backgroundColor(this.pal().surfaceGlass)
        .border({ width: 1, color: this.pal().border })
        .transition(TransitionEffect.opacity(0).animation({ duration: 150 }))
      }

      Row() {
        Row({ space: this.s(8) }) {
          this.countChip(true)
          this.countChip(false)
        }

        Blank()

        Text(this.rangeLabel())
          .fontSize(this.s(12))
          .fontFamily('monospace')
          .fontColor(this.pal().textMuted)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: this.s(16), right: this.s(16), top: this.s(14), bottom: this.s(14) })
  }

  @Builder
  private notice(text: string) {
    Text(text)
      .width('100%')
      .padding(this.s(12))
      .fontSize(this.s(13))
      .fontColor(this.pal().errorText)
      .backgroundColor(this.pal().errorBg)
      .borderRadius(this.s(12))
  }

  @Builder
  private galleryMessage(title: string, body: string, action: string, onAction: () => void) {
    Column({ space: this.s(12) }) {
      SymbolGlyph($r('sys.symbol.lock'))
        .fontSize(this.s(32))
        .fontColor([AMBER])
      Text(title)
        .fontSize(this.s(18))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
      Text(body)
        .fontSize(this.s(13))
        .lineHeight(this.s(19))
        .textAlign(TextAlign.Center)
        .fontColor(this.pal().textMuted)
      if (action.length > 0) {
        Button(action)
          .height(this.s(44))
          .padding({ left: this.s(20), right: this.s(20) })
          .fontSize(this.s(14))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().onPrimary)
          .backgroundColor(this.pal().primary)
          .onClick(onAction)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.s(32), right: this.s(32), top: this.topBarHeight, bottom: this.s(100) })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private photoTile(photo: GalleryPhoto, index: number) {
    Stack() {
      Image(photo.uri)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .sourceSize({ width: 320, height: 320 })
        .blur(this.isAllowed(photo) ? 0 : 3)
        .grayscale(this.isAllowed(photo) ? 0 : 1)
        .draggable(false)

      if (!this.isAllowed(photo)) {
        Column() {
          Column() {
            SymbolGlyph($r('sys.symbol.lock_fill'))
              .fontSize(this.s(12))
              .fontColor(['#E6FFFFFF'])
          }
          .width(this.s(24))
          .height(this.s(24))
          .borderRadius(this.s(12))
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#99000000')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#40000000')
      }
    }
    .width('100%')
    .aspectRatio(1)
    .borderRadius(this.s(12))
    .clip(true)
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: this.pal().border })
    .opacity(this.isAllowed(photo) ? 1 : 0.4)
    .animation({ duration: 200 })
    .accessibilityText(this.isAllowed(photo) ? photo.title : `${photo.title}, zablokowane`)
    .onClick(() => this.openDetail(index))
  }

  @Builder
  private galleryBody() {
    if (this.access === Access.LOADING) {
      Column({ space: this.s(12) }) {
        LoadingProgress()
          .width(this.s(40))
          .height(this.s(40))
          .color(this.pal().textMuted)
        Text('Wczytywanie galerii…')
          .fontSize(this.s(13))
          .fontColor(this.pal().textMuted)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.topBarHeight })
      .justifyContent(FlexAlign.Center)
    } else if (this.access === Access.DENIED) {
      this.galleryMessage('Brak dostępu do galerii',
        'SafeShare potrzebuje zgody na odczyt zdjęć, żeby pokazać je według daty. Zdjęcia nie opuszczają telefonu.',
        'Zezwól na dostęp', () => this.refreshGallery(true))
    } else if (this.access === Access.ERROR) {
      this.galleryMessage('Nie udało się wczytać galerii', 'Spróbuj ponownie za chwilę.',
        'Spróbuj ponownie', () => this.refreshGallery(false))
    } else if (this.photos.length === 0) {
      this.galleryMessage('Brak zdjęć w galerii', 'Zrób zdjęcie aparatem albo skopiuj zdjęcia na telefon.', '', () => {})
    } else {
      // The photos scroll underneath the translucent header and the hand-off button.
      List({ space: this.s(8) }) {
        ForEach(this.photos, (photo: GalleryPhoto, index: number) => {
          ListItem() {
            this.photoTile(photo, index)
          }
        }, (photo: GalleryPhoto) => photo.uri)
      }
      .width('100%')
      .height('100%')
      .lanes(gridColumns(this.winWidth, this.ui), this.s(8))
      .contentStartOffset(this.topBarHeight + this.s(12))
      .contentEndOffset(this.s(110))
      .padding({ left: this.s(12), right: this.s(12) })
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  private handOffButton() {
    Column() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: this.s(12) }) {
          Column() {
            SymbolGlyph($r('sys.symbol.lock_fill'))
              .fontSize(this.s(16))
              .fontColor([AMBER])
          }
          .width(this.s(32))
          .height(this.s(32))
          .borderRadius(this.s(12))
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#33FBBF24')

          Text(`Zablokuj i przekaż telefon (${this.allowedCount()})`)
            .fontSize(this.s(14))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().onPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(this.s(16))
            .fontColor([this.pal().onPrimary])
        }
        .padding({ left: this.s(12), right: this.s(12) })
      }
      .width('100%')
      .height(this.s(60))
      .borderRadius(this.s(16))
      .backgroundColor(this.pal().primary)
      .shadow({ radius: this.s(24), color: '#59000000', offsetY: this.s(8) })
      .enabled(this.canHandOff())
      .opacity(this.canHandOff() ? 1 : 0.4)
      .onClick(() => this.startHandOff())
    }
    .width('100%')
    .constraintSize({ maxWidth: this.s(560) })
    .padding({ left: this.s(16), right: this.s(16), top: this.s(28), bottom: this.s(20) })
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [[this.pal().fadeFrom, 0], [this.pal().fadeTo, 0.55]]
    })
  }

  @Builder
  private ownerScreen() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.galleryBody()

      Column() {
        this.header()
        this.filterBar()
        if (this.storeError) {
          Column() {
            this.notice('Pamięć aplikacji jest niedostępna. Tryb gościa jest zablokowany.')
          }
          .padding({ left: this.s(16), right: this.s(16), bottom: this.s(12) })
        } else if (!this.privacyReady) {
          Column() {
            this.notice('Nie udało się włączyć ochrony okna przed zrzutami ekranu. Tryb gościa jest zablokowany.')
          }
          .padding({ left: this.s(16), right: this.s(16), bottom: this.s(12) })
        }
      }
      .width('100%')
      .position({ x: 0, y: 0 })
      .backgroundColor(this.pal().glass)
      .backdropBlur(GLASS_BLUR)
      .border({ width: { bottom: 1 }, color: this.pal().border })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.topBarHeight = Number(newValue.height);
      })

      this.handOffButton()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().container)
    .transition(TransitionEffect.opacity(0).animation({ duration: SCREEN_FADE_MS, curve: Curve.EaseInOut }))
  }

  // ---- Photo detail overlay ---------------------------------------------------------------

  @Builder
  private infoRow(icon: Resource, text: string) {
    Row({ space: this.s(8) }) {
      SymbolGlyph(icon)
        .fontSize(this.s(14))
        .fontColor([this.pal().textMuted])
      Text(text)
        .fontSize(this.s(12))
        .fontColor(this.pal().textMuted)
        .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  private detailOverlay(photo: GalleryPhoto) {
    Column() {
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          Image(photo.uri)
            .width('100%')
            .aspectRatio(4 / 3)
            .objectFit(ImageFit.Cover)
            .sourceSize({ width: 1200, height: 900 })
            .backgroundColor(this.pal().surface)
            .draggable(false)

          Row() {
            Row({ space: this.s(4) }) {
              SymbolGlyph(this.isAllowed(photo) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.lock_fill'))
                .fontSize(this.s(12))
                .fontColor([this.isAllowed(photo) ? '#FFFFFF' : AMBER])
              Text(this.isAllowed(photo) ? 'Dostępne dla gościa' : 'Zablokowane')
                .fontSize(this.s(10))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isAllowed(photo) ? '#FFFFFF' : '#D4D4D8')
            }
            .padding({ left: this.s(10), right: this.s(10), top: this.s(4), bottom: this.s(4) })
            .borderRadius(999)
            .backgroundColor(this.isAllowed(photo) ? '#CC10B981' : '#B318181B')
            .backdropBlur(GLASS_BLUR)

            Blank()

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(this.s(16))
                .fontColor(['#FFFFFF'])
            }
            .width(this.s(32))
            .height(this.s(32))
            .backgroundColor('#73000000')
            .backdropBlur(GLASS_BLUR)
            .accessibilityText('Zamknij')
            .onClick(() => this.detailIndex = -1)
          }
          .width('100%')
          .padding(this.s(12))
        }

        Column({ space: this.s(12) }) {
          Column({ space: this.s(2) }) {
            Text(photo.title)
              .width('100%')
              .fontSize(this.s(16))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal().text)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(formatDateTime(photo.takenAt))
              .width('100%')
              .fontSize(this.s(11))
              .fontFamily('monospace')
              .fontColor(this.pal().textMuted)
          }

          Divider()
            .color(this.pal().border)
          this.infoRow($r('sys.symbol.picture'), `${photo.width} × ${photo.height} px`)
          Row({ space: this.s(8) }) {
            SymbolGlyph($r('sys.symbol.camera'))
              .fontSize(this.s(14))
              .fontColor([this.pal().textMuted])
            Text(this.detailCamera.length > 0 ? this.detailCamera : 'Brak danych o aparacie')
              .fontSize(this.s(12))
              .fontColor(this.pal().textMuted)
              .layoutWeight(1)
          }
          .width('100%')
          Divider()
            .color(this.pal().border)

          Row() {
            Blank()
            Button('Zamknij')
              .height(this.s(32))
              .padding({ left: this.s(16), right: this.s(16) })
              .fontSize(this.s(12))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal().text)
              .backgroundColor(this.keyColor())
              .onClick(() => this.detailIndex = -1)
          }
          .width('100%')
        }
        .padding(this.s(16))
      }
      .width('92%')
      .constraintSize({ maxWidth: this.s(420) })
      .borderRadius(this.s(24))
      .clip(true)
      .backgroundColor(this.pal().sheet)
      .backdropBlur(GLASS_BLUR)
      .border({ width: 1, color: this.pal().border })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.detailIndex = -1)
    .transition(TransitionEffect.opacity(0)
      .animation({ duration: FADE_MS, curve: Curve.FastOutSlowIn })
      .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 })))
  }

  // ---- Settings overlay -------------------------------------------------------------------

  @Builder
  private sectionLabel(text: string) {
    Text(text)
      .width('100%')
      .fontSize(this.s(12))
      .fontWeight(FontWeight.Bold)
      .letterSpacing(0.6)
      .fontColor(this.pal().textMuted)
  }

  @Builder
  private themeCard(dark: boolean) {
    Column({ space: this.s(10) }) {
      Column() {
        SymbolGlyph(dark ? $r('sys.symbol.moon') : $r('sys.symbol.sun_max'))
          .fontSize(this.s(24))
          .fontColor([dark ? '#38BDF8' : '#F59E0B'])
      }
      .width(this.s(40))
      .height(this.s(40))
      .borderRadius(this.s(12))
      .justifyContent(FlexAlign.Center)
      .backgroundColor(dark ? '#660C4A6E' : '#FEF3C7')

      Column({ space: this.s(2) }) {
        Text(dark ? 'Ciemny motyw' : 'Jasny motyw')
          .fontSize(this.s(14))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
        Text(dark ? 'Czerń OLED' : 'Czysta biel')
          .fontSize(this.s(11))
          .fontColor(this.pal().textMuted)
      }

      if (this.darkTheme === dark) {
        Text('Aktywny')
          .fontSize(this.s(10))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().okText)
          .backgroundColor(this.pal().okBg)
          .padding({ left: this.s(8), right: this.s(8), top: this.s(2), bottom: this.s(2) })
          .borderRadius(999)
      }
    }
    .layoutWeight(1)
    .padding(this.s(16))
    .borderRadius(this.s(16))
    .backgroundColor(this.darkTheme === dark ? this.pal().surfaceHover : this.pal().surfaceGlass)
    .border({ width: 2, color: this.darkTheme === dark ? this.pal().primary : this.pal().border })
    .onClick(() => this.setDarkTheme(dark))
  }

  @Builder
  private pinField(isCurrent: boolean) {
    Column({ space: this.s(4) }) {
      Text(isCurrent ? 'Obecny PIN:' : 'Nowy PIN:')
        .fontSize(this.s(11))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().textMuted)
      TextInput({ text: isCurrent ? this.currentPinInput : this.newPinInput, placeholder: '4 cyfry' })
        .type(InputType.NUMBER_PASSWORD)
        .maxLength(PIN_LENGTH)
        .showPasswordIcon(false)
        .height(this.s(48))
        .textAlign(TextAlign.Center)
        .fontSize(this.s(16))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
        .placeholderColor(this.pal().textMuted)
        .placeholderFont({ size: this.s(14) })
        .backgroundColor(this.pal().container)
        .borderRadius(this.s(12))
        .border({ width: 2, color: this.pal().border })
        .onChange((value: string) => {
          if (isCurrent) {
            this.currentPinInput = value;
          } else {
            this.newPinInput = value;
          }
        })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private settingToggle(isLeaveAlarm: boolean) {
    Row({ space: this.s(12) }) {
      Column({ space: this.s(2) }) {
        Text(isLeaveAlarm ? 'Alarm przy próbie wyjścia z aplikacji' : 'Ukryj szczegóły zdjęcia')
          .width('100%')
          .fontSize(this.s(14))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
        Text(isLeaveAlarm ?
          'Blokuje ekran kodem PIN natychmiast, gdy gość wróci do ekranu głównego, przełączy aplikację lub ją zminimalizuje.' :
          'Gość oglądający zdjęcia nie zobaczy modelu aparatu ani rozdzielczości.')
          .width('100%')
          .fontSize(this.s(12))
          .lineHeight(this.s(17))
          .fontColor(this.pal().textMuted)
      }
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isLeaveAlarm ? this.preventLeave : !this.showDetails })
        .width(this.s(44))
        .height(this.s(26))
        .selectedColor(AMBER)
        .onChange((isOn: boolean) => isLeaveAlarm ? this.setPreventLeave(isOn) : this.setShowDetails(!isOn))
    }
    .width('100%')
    .padding(this.s(14))
    .borderRadius(this.s(16))
    .backgroundColor(this.pal().surfaceGlass)
    .border({ width: 1, color: this.pal().border })
  }

  @Builder
  private settingsSheet() {
    Column() {
      Row() {
        Column({ space: this.s(2) }) {
          Text('Ustawienia aplikacji')
            .fontSize(this.s(18))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().text)
          Text('Personalizacja wyglądu i ochrona PIN')
            .fontSize(this.s(12))
            .fontColor(this.pal().textMuted)
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(this.s(22))
            .fontColor([this.pal().textMuted])
        }
        .width(this.s(40))
        .height(this.s(40))
        .backgroundColor(Color.Transparent)
        .accessibilityText('Zamknij')
        .onClick(() => this.settingsOpen = false)
      }
      .width('100%')
      .padding({ bottom: this.s(16) })
      .border({ width: { bottom: 1 }, color: this.pal().border })

      Scroll() {
        Column({ space: this.s(24) }) {
          Column({ space: this.s(12) }) {
            this.sectionLabel('1. WYBIERZ MOTYW KOLORYSTYCZNY')
            Row({ space: this.s(12) }) {
              this.themeCard(false)
              this.themeCard(true)
            }
            .width('100%')
          }

          Column({ space: this.s(12) }) {
            Row() {
              Row({ space: this.s(8) }) {
                SymbolGlyph($r('sys.symbol.key'))
                  .fontSize(this.s(16))
                  .fontColor([AMBER])
                Text('2. Kod PIN do odblokowania')
                  .fontSize(this.s(14))
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal().text)
              }

              Blank()

              Text(this.pinConfigured ? 'Ustawiony' : 'Nieustawiony')
                .fontSize(this.s(11))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pinConfigured ? this.pal().okText : this.pal().warnText)
                .backgroundColor(this.pinConfigured ? this.pal().okBg : this.pal().warnBg)
                .padding({ left: this.s(8), right: this.s(8), top: this.s(4), bottom: this.s(4) })
                .borderRadius(this.s(8))
            }
            .width('100%')

            Text(this.pinConfigured ?
              'Ten 4-cyfrowy kod jest wymagany do opuszczenia trybu gościa i powrotu do pełnej galerii.' :
              'Ustaw 4-cyfrowy kod. Będzie wymagany do opuszczenia trybu gościa.')
              .width('100%')
              .fontSize(this.s(12))
              .lineHeight(this.s(17))
              .fontColor(this.pal().textMuted)

            Row({ space: this.s(12) }) {
              if (this.pinConfigured) {
                this.pinField(true)
              }
              this.pinField(false)
            }
            .width('100%')

            if (this.settingsError.length > 0) {
              Text(this.settingsError)
                .width('100%')
                .padding(this.s(10))
                .fontSize(this.s(12))
                .fontColor(this.pal().errorText)
                .backgroundColor(this.pal().errorBg)
                .borderRadius(this.s(12))
            }
            if (this.settingsSuccess.length > 0) {
              Text(this.settingsSuccess)
                .width('100%')
                .padding(this.s(10))
                .fontSize(this.s(12))
                .fontColor(this.pal().okText)
                .backgroundColor(this.pal().okBg)
                .borderRadius(this.s(12))
            }

            Button('Zapisz nowy kod PIN')
              .width('100%')
              .height(this.s(48))
              .borderRadius(this.s(12))
              .fontSize(this.s(14))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal().onPrimary)
              .backgroundColor(this.pal().primary)
              .onClick(() => this.changePin())
          }
          .padding(this.s(16))
          .borderRadius(this.s(16))
          .backgroundColor(this.pal().surfaceGlass)
          .border({ width: 1, color: this.pal().border })

          Column({ space: this.s(12) }) {
            this.sectionLabel('3. ZABEZPIECZENIA W TRYBIE GOŚCIA')
            this.settingToggle(true)
            this.settingToggle(false)
          }

          Column({ space: this.s(12) }) {
            Row() {
              Row({ space: this.s(10) }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                  .fontSize(this.s(18))
                  .fontColor([AMBER])
                Text('Ograniczenia systemu OpenHarmony')
                  .fontSize(this.s(14))
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal().warnText)
              }

              Blank()

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(this.s(18))
                .fontColor([this.pal().warnText])
                .rotate({ angle: this.guideOpen ? 90 : 0 })
                .animation({ duration: 150 })
            }
            .width('100%')
            .padding(this.s(16))
            .borderRadius(this.s(16))
            .backgroundColor(this.pal().warnGlass)
            .border({ width: 1, color: this.pal().warnBorder })
            .onClick(() => this.guideOpen = !this.guideOpen)

            if (this.guideOpen) {
              Text('SafeShare nie może zablokować przycisków systemowych. Gość może wrócić do ekranu głównego i otworzyć ' +
                'inną aplikację, np. systemową Galerię. SafeShare wtedy natychmiast zablokuje się kodem PIN, ale nie ' +
                'zablokuje innych aplikacji.\n\nPrzed przekazaniem telefonu ustaw systemową blokadę ekranu. Pełna blokada ' +
                'w jednej aplikacji (tryb kiosku) wymaga urządzenia zarządzanego przez administratora (Enterprise Device ' +
                'Management).')
                .width('100%')
                .padding(this.s(16))
                .fontSize(this.s(12))
                .lineHeight(this.s(18))
                .fontColor(this.pal().textMuted)
                .backgroundColor(this.pal().surfaceGlass)
                .borderRadius(this.s(16))
                .border({ width: 1, color: this.pal().border })
                .transition(TransitionEffect.opacity(0).animation({ duration: 150 }))
            }
          }
        }
        .padding({ top: this.s(20), bottom: this.s(20) })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      Button('Gotowe')
        .width('100%')
        .height(this.s(56))
        .borderRadius(this.s(16))
        .fontSize(this.s(16))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().onPrimary)
        .backgroundColor(this.pal().primary)
        .onClick(() => this.settingsOpen = false)
    }
    .width('100%')
    .height('90%')
    .constraintSize({ maxWidth: this.s(560) })
    .padding(this.s(24))
    .borderRadius({ topLeft: this.s(24), topRight: this.s(24) })
    .backgroundColor(this.pal().sheet)
    .backdropBlur(GLASS_BLUR)
    .border({ width: { top: 1 }, color: this.pal().border })
    .onClick(() => {})
  }

  @Builder
  private settingsOverlay() {
    Column() {
      this.settingsSheet()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .onClick(() => this.settingsOpen = false)
    .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
      .animation({ duration: 320, curve: Curve.FastOutSlowIn }))
  }

  // ---- Guest screen -----------------------------------------------------------------------

  @Builder
  private guestIconButton(isZoom: boolean) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(isZoom ? (this.guestZoom > 1 ? $r('sys.symbol.minus_magnifyingglass') :
        $r('sys.symbol.plus_magnifyingglass')) : $r('sys.symbol.info_circle'))
        .fontSize(this.s(20))
        .fontColor([this.pal().viewerText])
    }
    .width(this.s(44))
    .height(this.s(44))
    .backgroundColor(this.pal().viewerGlass)
    .backdropBlur(GLASS_BLUR)
    .border({ width: 1, color: this.pal().viewerBorder, radius: this.s(16) })
    .accessibilityText(isZoom ? 'Przybliż / oddal zdjęcie' : 'Informacje o zdjęciu')
    .onClick(() => {
      if (isZoom) {
        this.toggleZoom();
      } else {
        this.guestInfoOpen = !this.guestInfoOpen;
      }
    })
  }

  @Builder
  private guestTopBar() {
    Row() {
      Row({ space: this.s(6) }) {
        SymbolGlyph($r('sys.symbol.lock_fill'))
          .fontSize(this.s(14))
          .fontColor([AMBER])
        Text(`Tryb Gościa: ${this.guestIndex + 1} / ${this.guestPhotos.length}`)
          .fontSize(this.s(12))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().warnText)
      }
      .padding({ left: this.s(12), right: this.s(12), top: this.s(6), bottom: this.s(6) })
      .borderRadius(999)
      .backgroundColor(this.pal().warnGlass)
      .backdropBlur(GLASS_BLUR)
      .border({ width: 1, color: '#66F59E0B' })

      Blank()

      Row({ space: this.s(8) }) {
        this.guestIconButton(true)
        if (this.showDetails) {
          this.guestIconButton(false)
        }
        Button({ type: ButtonType.Normal }) {
          Row({ space: this.s(8) }) {
            SymbolGlyph($r('sys.symbol.lock_fill'))
              .fontSize(this.s(16))
              .fontColor([AMBER])
            Text('Wyjdź (PIN)')
              .fontSize(this.s(12))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal().viewerText)
          }
        }
        .height(this.s(44))
        .padding({ left: this.s(16), right: this.s(16) })
        .backgroundColor(this.pal().viewerGlass)
        .backdropBlur(GLASS_BLUR)
        .border({ width: 1, color: this.pal().viewerBorder, radius: this.s(16) })
        .onClick(() => {
          hapticTap();
          this.openPin(PinMode.EXIT, '');
        })
      }
    }
    .width('100%')
    .padding({ left: this.s(16), right: this.s(16), top: this.s(16), bottom: this.s(32) })
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [[this.pal().viewerFade, 0], [this.pal().viewerFadeClear, 1]]
    })
  }

  @Builder
  private guestThumb(photo: GalleryPhoto, index: number) {
    Image(photo.uri)
      .width(this.s(48))
      .height(this.s(48))
      .objectFit(ImageFit.Cover)
      .sourceSize({ width: 128, height: 128 })
      .borderRadius(this.s(8))
      .border({ width: 2, color: index === this.guestIndex ? AMBER : Color.Transparent })
      .opacity(index === this.guestIndex ? 1 : 0.55)
      .scale({ x: index === this.guestIndex ? 1.05 : 1, y: index === this.guestIndex ? 1.05 : 1 })
      .animation({ duration: 200 })
      .draggable(false)
      .onClick(() => {
        hapticTap();
        this.showGuestPhoto(index);
      })
  }

  @Builder
  private guestFooter() {
    Column({ space: this.s(8) }) {
      Row({ space: this.s(8) }) {
        Column({ space: this.s(2) }) {
          Text(this.currentGuest().title)
            .width('100%')
            .fontSize(this.s(14))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal().viewerText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.showDetails ?
            `${formatDateTime(this.currentGuest().takenAt)} · ${this.currentGuest().width}×${this.currentGuest().height}` :
            formatDateTime(this.currentGuest().takenAt))
            .width('100%')
            .fontSize(this.s(11))
            .fontFamily('monospace')
            .fontColor(this.pal().viewerMuted)
            .maxLines(1)
        }
        .layoutWeight(1)

        Text(`Okres: ${this.guestRangeLabel}`)
          .fontSize(this.s(11))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().okText)
          .padding({ left: this.s(8), right: this.s(8), top: this.s(2), bottom: this.s(2) })
          .borderRadius(this.s(6))
          .backgroundColor(this.pal().okBg)
          .border({ width: 1, color: this.pal().okBorder })
      }
      .width('100%')

      if (this.guestPhotos.length > 1) {
        Scroll() {
          Row({ space: this.s(6) }) {
            ForEach(this.guestPhotos, (photo: GalleryPhoto, index: number) => {
              this.guestThumb(photo, index)
            }, (photo: GalleryPhoto) => photo.uri)

            Column() {
              SymbolGlyph($r('sys.symbol.lock_fill'))
                .fontSize(this.s(16))
                .fontColor([this.pal().warnText])
              Text(`+${this.lockedCount}`)
                .fontSize(this.s(9))
                .fontWeight(FontWeight.Bold)
                .fontFamily('monospace')
                .fontColor(this.pal().warnText)
            }
            .width(this.s(48))
            .height(this.s(48))
            .borderRadius(this.s(8))
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.pal().viewerGlass)
            .backdropBlur(GLASS_BLUR)
            .border({ width: 1, color: '#80F59E0B', style: BorderStyle.Dashed })
            .accessibilityText('Pozostałe zdjęcia w galerii są zablokowane')
            .onClick(() => {
              hapticAlarm();
              this.showBoundary(`${this.lockedCount} pozostałych prywatnych zdjęć jest zablokowane.`);
            })
          }
          .padding({ top: this.s(4), bottom: this.s(4), left: this.s(2), right: this.s(2) })
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
      }
    }
    .width('100%')
    .padding({ left: this.s(16), right: this.s(16), top: this.s(36), bottom: this.s(24) })
    .linearGradient({
      direction: GradientDirection.Top,
      colors: [[this.pal().viewerFade, 0], [this.pal().viewerFade, 0.4], [this.pal().viewerFadeClear, 1]]
    })
  }

  @Builder
  private guestInfoRow(icon: Resource, color: string, text: string) {
    Row({ space: this.s(8) }) {
      SymbolGlyph(icon)
        .fontSize(this.s(16))
        .fontColor([color])
      Text(text)
        .fontSize(this.s(12))
        .fontColor(this.pal().text)
        .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  private guestInfoOverlay() {
    Column() {
      Column({ space: this.s(10) }) {
        Row() {
          Text('Metadane zdjęcia')
            .fontSize(this.s(14))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal().text)
          Blank()
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(this.s(16))
              .fontColor([this.pal().textMuted])
          }
          .width(this.s(32))
          .height(this.s(32))
          .backgroundColor(Color.Transparent)
          .onClick(() => this.guestInfoOpen = false)
        }
        .width('100%')
        .padding({ bottom: this.s(10) })
        .border({ width: { bottom: 1 }, color: this.pal().border })

        this.guestInfoRow($r('sys.symbol.calendar'), AMBER, formatDateTime(this.currentGuest().takenAt))
        this.guestInfoRow($r('sys.symbol.picture'), '#38BDF8',
          `${this.currentGuest().width} × ${this.currentGuest().height} px`)
        this.guestInfoRow($r('sys.symbol.camera'), EMERALD,
          this.guestCamera.length > 0 ? this.guestCamera : 'Brak danych o aparacie')
      }
      .width('90%')
      .constraintSize({ maxWidth: this.s(380) })
      .padding(this.s(20))
      .borderRadius(this.s(16))
      .backgroundColor(this.pal().sheet)
      .backdropBlur(GLASS_BLUR)
      .border({ width: 1, color: this.pal().border })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.guestInfoOpen = false)
    .transition(TransitionEffect.opacity(0)
      .animation({ duration: FADE_MS, curve: Curve.FastOutSlowIn })
      .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 })))
  }

  @Builder
  private guestLocked() {
    Column({ space: this.s(12) }) {
      Column() {
        SymbolGlyph($r('sys.symbol.lock_fill'))
          .fontSize(this.s(32))
          .fontColor([AMBER])
      }
      .width(this.s(64))
      .height(this.s(64))
      .borderRadius(this.s(16))
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.pal().warnGlass)
      .border({ width: 1, color: '#4DF59E0B' })

      Text('Galeria jest zablokowana')
        .fontSize(this.s(20))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
      Text('Sesja gościa została przerwana. Pozostałe zdjęcia są ukryte do czasu podania kodu PIN właściciela.')
        .fontSize(this.s(14))
        .lineHeight(this.s(20))
        .textAlign(TextAlign.Center)
        .fontColor(this.pal().textMuted)
      Button('Odblokuj galerię (kod PIN)')
        .height(this.s(40))
        .padding({ left: this.s(24), right: this.s(24) })
        .margin({ top: this.s(12) })
        .fontSize(this.s(12))
        .fontWeight(FontWeight.Bold)
        .fontColor('#020617')
        .backgroundColor(AMBER)
        .onClick(() => this.openPin(PinMode.RESUME,
          'Sesja gościa została przerwana. Wprowadź kod PIN właściciela, aby wrócić do galerii.'))
    }
    .width('100%')
    .height('100%')
    .padding(this.s(24))
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pal().container)
    .transition(TransitionEffect.opacity(0).animation({ duration: SCREEN_FADE_MS, curve: Curve.EaseInOut }))
  }

  @Builder
  private guestScreen() {
    if (this.guestPhotos.length === 0) {
      this.guestLocked()
    } else {
      Stack() {
        // Instead of black bars around the photo: a blurred, tinted copy of the photo fills the screen.
        ForEach(this.guestSlide(), (photo: GalleryPhoto) => {
          Image(photo.uri)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .sourceSize({ width: 64, height: 64 })
            .blur(AMBIENT_BLUR)
            .draggable(false)
            .transition(TransitionEffect.opacity(0).animation({ duration: 400 }))
        }, (photo: GalleryPhoto) => photo.uri)

        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.pal().viewerScrim)

        Stack() {
          ForEach(this.guestSlide(), (photo: GalleryPhoto) => {
            Image(photo.uri)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .sourceSize({ width: 1600, height: 1600 })
              .scale({ x: this.guestZoom, y: this.guestZoom })
              .animation({ duration: 300, curve: Curve.EaseOut })
              .privacySensitive(true)
              .draggable(false)
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.opacity(0)
                  .animation({ duration: 280, curve: Curve.FastOutSlowIn })
                  .combine(TransitionEffect.translate({ x: this.slideFrom })),
                TransitionEffect.opacity(0).animation({ duration: 200 })))
          }, (photo: GalleryPhoto) => photo.uri)
        }
        .width('100%')
        .height('100%')
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2 })
              .onAction(() => this.toggleZoom()),
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionEnd((event: GestureEvent) => this.handleSwipe(event.offsetX))
          )
        )

        Column() {
          this.guestTopBar()
          Blank()
          if (this.boundaryAlert.length > 0) {
            Row({ space: this.s(10) }) {
              SymbolGlyph($r('sys.symbol.lock_fill'))
                .fontSize(this.s(16))
                .fontColor([AMBER])
              Text(this.boundaryAlert)
                .fontSize(this.s(12))
                .lineHeight(this.s(17))
                .fontColor(this.pal().warnText)
                .layoutWeight(1)
            }
            .margin({ left: this.s(16), right: this.s(16), bottom: this.s(12) })
            .padding({ left: this.s(16), right: this.s(16), top: this.s(10), bottom: this.s(10) })
            .borderRadius(this.s(12))
            .backgroundColor(this.pal().warnGlass)
            .backdropBlur(GLASS_BLUR)
            .border({ width: 1, color: '#80F59E0B' })
            .transition(TransitionEffect.opacity(0).animation({ duration: 200 }))
          }
          this.guestFooter()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)

        if (this.guestInfoOpen) {
          this.scrim()
          this.guestInfoOverlay()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal().container)
      .transition(TransitionEffect.opacity(0)
        .animation({ duration: SCREEN_FADE_MS, curve: Curve.EaseInOut })
        .combine(TransitionEffect.scale({ x: 1.04, y: 1.04 })))
    }
  }

  // ---- PIN overlay ------------------------------------------------------------------------

  @Builder
  private pinKey(digit: string) {
    Button({ type: ButtonType.Circle }) {
      Text(digit)
        .fontSize(this.ps(26))
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor(this.pal().text)
    }
    .width(this.ps(72))
    .height(this.ps(72))
    .backgroundColor(this.keyColor())
    .onClick(() => this.pressDigit(digit))
  }

  @Builder
  private pinOverlay() {
    Scroll() {
      Column() {
        Stack({ alignContent: Alignment.TopEnd }) {
          Column() {
            Column() {
              SymbolGlyph(this.isPanicPin() ? $r('sys.symbol.exclamationmark_triangle') : $r('sys.symbol.lock'))
                .fontSize(this.ps(28))
                .fontColor([this.isPanicPin() ? DANGER : this.pal().text])
            }
            .width(this.ps(56))
            .height(this.ps(56))
            .borderRadius(this.ps(16))
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.isPanicPin() ? '#1AEF4444' : this.keyColor())
            .border({ width: this.isPanicPin() ? 1 : 0, color: '#33EF4444' })
            .margin({ bottom: this.ps(14) })

            Text(this.pinTitle())
              .fontSize(this.ps(18))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal().text)
              .margin({ bottom: this.ps(4) })
            Text(this.pinSubtitle())
              .fontSize(this.ps(12))
              .lineHeight(this.ps(18))
              .textAlign(TextAlign.Center)
              .fontColor(this.pal().textMuted)
              .constraintSize({ maxWidth: this.ps(270) })
              .margin({ bottom: this.ps(24) })

            Row({ space: this.ps(16) }) {
              ForEach(PIN_SLOTS, (slot: number) => {
                Circle()
                  .width(this.ps(16))
                  .height(this.ps(16))
                  .fill(this.pinEntry.length > slot ? (this.pinError ? DANGER : this.pal().text) : this.keyColor())
                  .scale({ x: this.pinEntry.length > slot ? 1.25 : 1, y: this.pinEntry.length > slot ? 1.25 : 1 })
                  .animation({ duration: 150 })
              }, (slot: number) => slot.toString())
            }
            .margin({ bottom: this.ps(12) })

            Text(this.pinFeedback)
              .height(this.ps(18))
              .fontSize(this.ps(11))
              .fontColor(DANGER)
              .margin({ bottom: this.ps(12) })

            Column({ space: this.ps(14) }) {
              ForEach(KEYPAD_ROWS, (row: string[]) => {
                Row({ space: this.ps(18) }) {
                  ForEach(row, (digit: string) => {
                    this.pinKey(digit)
                  }, (digit: string) => digit)
                }
              }, (row: string[]) => row[0])

              Row({ space: this.ps(18) }) {
                Column()
                  .width(this.ps(72))
                  .height(this.ps(72))
                this.pinKey('0')
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.delete_left'))
                    .fontSize(this.ps(22))
                    .fontColor([this.pal().textMuted])
                }
                .width(this.ps(72))
                .height(this.ps(72))
                .backgroundColor(Color.Transparent)
                .accessibilityText('Usuń cyfrę')
                .onClick(() => this.deleteDigit())
              }
            }

            Text('Zapomniałeś kodu PIN?')
              .fontSize(this.ps(11))
              .fontColor(this.pal().textMuted)
              .margin({ top: this.ps(16) })
              .onClick(() => this.pinHintOpen = !this.pinHintOpen)
            if (this.pinHintOpen) {
              Text('Kodu nie da się odzyskać. Aby go zresetować, wyczyść dane aplikacji SafeShare w Ustawieniach systemu.')
                .margin({ top: this.ps(6) })
                .padding(this.ps(8))
                .fontSize(this.ps(11))
                .lineHeight(this.ps(16))
                .textAlign(TextAlign.Center)
                .fontColor(this.pal().textMuted)
                .backgroundColor(this.keyColor())
                .borderRadius(this.ps(8))
            }
            if (this.pinAttempts > 0) {
              Text(`Błędnych prób: ${this.pinAttempts}`)
                .margin({ top: this.ps(4) })
                .fontSize(this.ps(10))
                .fontFamily('monospace')
                .fontColor(DANGER)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)

          if (this.isPinCancelable()) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(this.ps(22))
                .fontColor([this.pal().textMuted])
            }
            .width(this.ps(40))
            .height(this.ps(40))
            .backgroundColor(Color.Transparent)
            .accessibilityText('Anuluj')
            .onClick(() => this.closePin())
          }
        }
        .width('92%')
        .constraintSize({ maxWidth: this.ps(380) })
        .padding(this.ps(28))
        .borderRadius(this.ps(24))
        .backgroundColor(this.pal().sheet)
        .backdropBlur(GLASS_BLUR)
        .border({ width: 1, color: this.isPanicPin() ? DANGER : this.pal().border })
        .shadow({ radius: this.ps(40), color: '#59000000', offsetY: this.ps(12) })
        .translate({ x: this.shakeOffset })
      }
      .width('100%')
      .constraintSize({ minHeight: this.winHeight })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .transition(TransitionEffect.opacity(0)
      .animation({ duration: FADE_MS, curve: Curve.FastOutSlowIn })
      .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 })))
  }

  build() {
    Stack() {
      if (this.guestMode) {
        this.guestScreen()
      } else {
        this.ownerScreen()
      }
      if (!this.guestMode && this.detailIndex >= 0 && this.detailIndex < this.photos.length) {
        this.scrim()
        this.detailOverlay(this.photos[this.detailIndex])
      }
      if (!this.guestMode && this.settingsOpen) {
        this.scrim()
        this.settingsOverlay()
      }
      if (this.pinMode !== PinMode.NONE) {
        this.scrim()
        this.pinOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().page)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.onWindowArea(Number(newValue.width), Number(newValue.height));
    })
  }
}
