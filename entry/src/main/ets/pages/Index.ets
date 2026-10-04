import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { formatDateTime, formatDay, formatRangeShort } from '../common/Format';
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

const PRESET_ROWS: PresetOption[][] = [
  [new PresetOption('today', 'Dzisiaj', $r('sys.symbol.calendar'), '#EF4444', 'Bieżący dzień'),
    new PresetOption('yesterday', 'Wczoraj', $r('sys.symbol.clock'), '#60A5FA', 'Poprzedni dzień')],
  [new PresetOption('weekend', 'Weekend', $r('sys.symbol.sunset_fill'), '#F97316', 'Ostatni weekend'),
    new PresetOption('custom', 'Własny zakres', $r('sys.symbol.slider_horizontal_2'), '#A1A1AA', 'Wybierz daty')]
];

const KEYPAD_ROWS: string[][] = [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']];
const PIN_SLOTS: number[] = [0, 1, 2, 3];

@Entry
@Component
struct Index {
  @StorageLink('privacyReady') private privacyReady: boolean = false;
  @StorageLink('interruptionEpoch') @Watch('onInterrupted') private interruptionEpoch: number = 0;

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
  @State private boundaryAlert: string = '';

  private store: AppStore = new AppStore();
  private pinFirst: string = '';
  private boundaryTimer: number = -1;

  aboutToAppear(): void {
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

  private pal(): Palette {
    return this.darkTheme ? DARK : LIGHT;
  }

  private cardColor(): string {
    return this.darkTheme ? DARK.surface : LIGHT.container;
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

  private showGuestPhoto(index: number): void {
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

  // ---- Owner screen -----------------------------------------------------------------------

  @Builder
  private headerButton(isTheme: boolean) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(isTheme ? (this.darkTheme ? $r('sys.symbol.sun_max') : $r('sys.symbol.moon')) :
        $r('sys.symbol.gearshape'))
        .fontSize(20)
        .fontColor([isTheme && this.darkTheme ? AMBER : this.pal().text])
    }
    .width(44)
    .height(44)
    .borderRadius(16)
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: this.pal().border })
    .accessibilityText(isTheme ? (this.darkTheme ? 'Włącz jasny motyw' : 'Włącz ciemny motyw') : 'Ustawienia')
    .onClick(() => isTheme ? this.setDarkTheme(!this.darkTheme) : this.openSettings())
  }

  @Builder
  private header() {
    Row() {
      Row({ space: 12 }) {
        Image($r('app.media.app_icon_lock'))
          .width(40)
          .height(40)
          .borderRadius(16)
          .objectFit(ImageFit.Cover)
          .border({ width: 2, color: this.pal().border })
        Column({ space: 2 }) {
          Text('SafeShare')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().text)
          Row({ space: 6 }) {
            Circle()
              .width(8)
              .height(8)
              .fill(EMERALD)
            Text('Galeria telefonu')
              .fontSize(12)
              .fontColor(this.pal().textMuted)
          }
        }
        .alignItems(HorizontalAlign.Start)
      }

      Blank()

      Row({ space: 8 }) {
        this.headerButton(true)
        this.headerButton(false)
      }
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.pal().container)
    .border({ width: { bottom: 1 }, color: this.pal().border })
  }

  @Builder
  private presetButton(option: PresetOption) {
    Row() {
      Row({ space: 10 }) {
        SymbolGlyph(option.icon)
          .fontSize(20)
          .fontColor([option.iconColor])
        Column() {
          Text(option.label)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.preset === option.key ? this.pal().onPrimary : this.pal().text)
          Text(option.subtitle)
            .fontSize(10)
            .margin({ top: 2 })
            .fontColor(this.preset === option.key ? this.pal().selectedSubtitle : this.pal().textMuted)
        }
        .alignItems(HorizontalAlign.Start)
      }

      Blank()

      if (this.preset === option.key) {
        Circle()
          .width(10)
          .height(10)
          .fill(EMERALD)
      }
    }
    .layoutWeight(1)
    .height(58)
    .padding(12)
    .borderRadius(16)
    .backgroundColor(this.preset === option.key ? this.pal().primary : this.pal().surface)
    .border({ width: 1, color: this.preset === option.key ? this.pal().primary : this.pal().border })
    .onClick(() => this.selectPreset(option.key))
  }

  @Builder
  private dateField(isStart: boolean) {
    Column({ space: 4 }) {
      Text(isStart ? 'Data początkowa (OD)' : 'Data końcowa (DO)')
        .fontSize(12)
        .fontColor(this.pal().textMuted)
      Text(formatDay(isStart ? this.customStart : this.customEnd))
        .width('100%')
        .height(44)
        .padding({ left: 12, right: 12 })
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().text)
        .backgroundColor(this.pal().container)
        .borderRadius(12)
        .border({ width: 1, color: this.pal().border })
        .onClick(() => this.pickDate(isStart))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private countChip(visible: boolean) {
    Row({ space: 6 }) {
      SymbolGlyph(visible ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.lock_fill'))
        .fontSize(14)
        .fontColor([visible ? this.pal().okText : this.pal().warnText])
      Text(visible ? `${this.allowedCount()} widocznych` : `${this.photos.length - this.allowedCount()} ukrytych`)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(visible ? this.pal().okText : this.pal().warnText)
    }
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .borderRadius(8)
    .backgroundColor(visible ? this.pal().okBg : this.pal().warnBg)
    .border({ width: 1, color: visible ? this.pal().okBorder : this.pal().warnBorder })
  }

  @Builder
  private filterBar() {
    Column({ space: 14 }) {
      Column({ space: 8 }) {
        Text('OKRES ZDJĘĆ DO POKAZANIA:')
          .width('100%')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(0.6)
          .fontColor(this.pal().textMuted)
        ForEach(PRESET_ROWS, (row: PresetOption[]) => {
          Row({ space: 10 }) {
            ForEach(row, (option: PresetOption) => {
              this.presetButton(option)
            }, (option: PresetOption) => option.key)
          }
          .width('100%')
        }, (row: PresetOption[]) => row[0].key)
      }

      if (this.preset === 'custom') {
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(16)
              .fontColor(['#0EA5E9'])
            Text('Wskaż zakres dat (OD - DO):')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal().text)
          }
          .width('100%')

          Row({ space: 12 }) {
            this.dateField(true)
            this.dateField(false)
          }
          .width('100%')

        }
        .padding(16)
        .borderRadius(16)
        .backgroundColor(this.pal().surface)
        .border({ width: 1, color: this.pal().border })
      }

      Row() {
        Row({ space: 8 }) {
          this.countChip(true)
          this.countChip(false)
        }

        Blank()

        Text(this.rangeLabel())
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(this.pal().textMuted)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(this.pal().container)
    .border({ width: { bottom: 1 }, color: this.pal().border })
  }

  @Builder
  private notice(text: string) {
    Text(text)
      .width('100%')
      .padding(12)
      .fontSize(13)
      .fontColor(this.pal().errorText)
      .backgroundColor(this.pal().errorBg)
      .borderRadius(12)
  }

  @Builder
  private galleryMessage(title: string, body: string, action: string, onAction: () => void) {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.lock'))
        .fontSize(32)
        .fontColor([AMBER])
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
      Text(body)
        .fontSize(13)
        .lineHeight(19)
        .textAlign(TextAlign.Center)
        .fontColor(this.pal().textMuted)
      if (action.length > 0) {
        Button(action)
          .height(44)
          .padding({ left: 20, right: 20 })
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().onPrimary)
          .backgroundColor(this.pal().primary)
          .onClick(onAction)
      }
    }
    .layoutWeight(1)
    .width('100%')
    .padding(32)
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
              .fontSize(12)
              .fontColor(['#E6FFFFFF'])
          }
          .width(24)
          .height(24)
          .borderRadius(12)
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
    .borderRadius(12)
    .clip(true)
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: this.pal().border })
    .opacity(this.isAllowed(photo) ? 1 : 0.4)
    .accessibilityText(this.isAllowed(photo) ? photo.title : `${photo.title}, zablokowane`)
    .onClick(() => this.openDetail(index))
  }

  @Builder
  private galleryBody() {
    if (this.access === Access.LOADING) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(this.pal().textMuted)
        Text('Wczytywanie galerii…')
          .fontSize(13)
          .fontColor(this.pal().textMuted)
      }
      .layoutWeight(1)
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
      Grid() {
        ForEach(this.photos, (photo: GalleryPhoto, index: number) => {
          GridItem() {
            this.photoTile(photo, index)
          }
        }, (photo: GalleryPhoto) => photo.uri)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .padding({ left: 12, right: 12, top: 12, bottom: 100 })
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
  }

  @Builder
  private handOffButton() {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Column() {
            SymbolGlyph($r('sys.symbol.lock_fill'))
              .fontSize(16)
              .fontColor([AMBER])
          }
          .width(32)
          .height(32)
          .borderRadius(12)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#33FBBF24')

          Text(`Zablokuj i przekaż telefon (${this.allowedCount()})`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().onPrimary)

          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(16)
            .fontColor([this.pal().onPrimary])
        }
      }
      .width('100%')
      .height(60)
      .borderRadius(16)
      .backgroundColor(this.pal().primary)
      .shadow({ radius: 24, color: '#66000000', offsetY: 8 })
      .enabled(this.canHandOff())
      .opacity(this.canHandOff() ? 1 : 0.4)
      .onClick(() => this.startHandOff())
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 20 })
  }

  @Builder
  private ownerScreen() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.header()
        this.filterBar()
        if (this.storeError) {
          Column() {
            this.notice('Pamięć aplikacji jest niedostępna. Tryb gościa jest zablokowany.')
          }
          .padding({ left: 16, right: 16, top: 12 })
        } else if (!this.privacyReady) {
          Column() {
            this.notice('Nie udało się włączyć ochrony okna przed zrzutami ekranu. Tryb gościa jest zablokowany.')
          }
          .padding({ left: 16, right: 16, top: 12 })
        }
        this.galleryBody()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal().container)

      this.handOffButton()
    }
    .width('100%')
    .height('100%')
  }

  // ---- Photo detail overlay ---------------------------------------------------------------

  @Builder
  private infoRow(icon: Resource, text: string) {
    Row({ space: 8 }) {
      SymbolGlyph(icon)
        .fontSize(14)
        .fontColor([this.pal().textMuted])
      Text(text)
        .fontSize(12)
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
            .backgroundColor('#000000')
            .draggable(false)

          Row() {
            Row({ space: 4 }) {
              SymbolGlyph(this.isAllowed(photo) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.lock_fill'))
                .fontSize(12)
                .fontColor([this.isAllowed(photo) ? '#FFFFFF' : AMBER])
              Text(this.isAllowed(photo) ? 'Dostępne dla gościa' : 'Zablokowane')
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isAllowed(photo) ? '#FFFFFF' : '#D4D4D8')
            }
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(999)
            .backgroundColor(this.isAllowed(photo) ? '#E610B981' : '#E618181B')

            Blank()

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
            }
            .width(32)
            .height(32)
            .backgroundColor('#99000000')
            .accessibilityText('Zamknij')
            .onClick(() => this.detailIndex = -1)
          }
          .width('100%')
          .padding(12)
        }

        Column({ space: 12 }) {
          Column({ space: 2 }) {
            Text(photo.title)
              .width('100%')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal().text)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(formatDateTime(photo.takenAt))
              .width('100%')
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor(this.pal().textMuted)
          }

          Divider()
            .color(this.pal().border)
          this.infoRow($r('sys.symbol.picture'), `${photo.width} × ${photo.height} px`)
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.camera'))
              .fontSize(14)
              .fontColor([this.pal().textMuted])
            Text(this.detailCamera.length > 0 ? this.detailCamera : 'Brak danych o aparacie')
              .fontSize(12)
              .fontColor(this.pal().textMuted)
              .layoutWeight(1)
          }
          .width('100%')
          Divider()
            .color(this.pal().border)

          Row() {
            Blank()
            Button('Zamknij')
              .height(32)
              .padding({ left: 16, right: 16 })
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal().text)
              .backgroundColor(this.darkTheme ? DARK.surfaceHover : LIGHT.surface)
              .onClick(() => this.detailIndex = -1)
          }
          .width('100%')
        }
        .padding(16)
      }
      .width('92%')
      .constraintSize({ maxWidth: 400 })
      .borderRadius(24)
      .clip(true)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.pal().border })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#BF000000')
    .onClick(() => this.detailIndex = -1)
  }

  // ---- Settings overlay -------------------------------------------------------------------

  @Builder
  private sectionLabel(text: string) {
    Text(text)
      .width('100%')
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .letterSpacing(0.6)
      .fontColor(this.pal().textMuted)
  }

  @Builder
  private themeCard(dark: boolean) {
    Column({ space: 10 }) {
      Column() {
        SymbolGlyph(dark ? $r('sys.symbol.moon') : $r('sys.symbol.sun_max'))
          .fontSize(24)
          .fontColor([dark ? '#38BDF8' : '#F59E0B'])
      }
      .width(40)
      .height(40)
      .borderRadius(12)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(dark ? '#660C4A6E' : '#FEF3C7')

      Column({ space: 2 }) {
        Text(dark ? 'Ciemny motyw' : 'Jasny motyw')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
        Text(dark ? 'Czerń OLED' : 'Czysta biel')
          .fontSize(11)
          .fontColor(this.pal().textMuted)
      }

      if (this.darkTheme === dark) {
        Text('Aktywny')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().okText)
          .backgroundColor(this.pal().okBg)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(999)
      }
    }
    .layoutWeight(1)
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.darkTheme === dark ? this.pal().surfaceHover : this.pal().container)
    .border({ width: 2, color: this.darkTheme === dark ? this.pal().primary : this.pal().border })
    .onClick(() => this.setDarkTheme(dark))
  }

  @Builder
  private pinField(isCurrent: boolean) {
    Column({ space: 4 }) {
      Text(isCurrent ? 'Obecny PIN:' : 'Nowy PIN:')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().textMuted)
      TextInput({ text: isCurrent ? this.currentPinInput : this.newPinInput, placeholder: '4 cyfry' })
        .type(InputType.NUMBER_PASSWORD)
        .maxLength(PIN_LENGTH)
        .showPasswordIcon(false)
        .height(48)
        .textAlign(TextAlign.Center)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
        .placeholderColor(this.pal().textMuted)
        .backgroundColor(this.pal().container)
        .borderRadius(12)
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
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(isLeaveAlarm ? 'Alarm przy próbie wyjścia z aplikacji' : 'Ukryj szczegóły zdjęcia')
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
        Text(isLeaveAlarm ?
          'Blokuje ekran kodem PIN natychmiast, gdy gość wróci do ekranu głównego, przełączy aplikację lub ją zminimalizuje.' :
          'Gość oglądający zdjęcia nie zobaczy modelu aparatu ani rozdzielczości.')
          .width('100%')
          .fontSize(12)
          .lineHeight(17)
          .fontColor(this.pal().textMuted)
      }
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isLeaveAlarm ? this.preventLeave : !this.showDetails })
        .selectedColor(AMBER)
        .onChange((isOn: boolean) => isLeaveAlarm ? this.setPreventLeave(isOn) : this.setShowDetails(!isOn))
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: this.pal().border })
  }

  @Builder
  private settingsSheet() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('Ustawienia aplikacji')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().text)
          Text('Personalizacja wyglądu i ochrona PIN')
            .fontSize(12)
            .fontColor(this.pal().textMuted)
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(22)
            .fontColor([this.pal().textMuted])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .accessibilityText('Zamknij')
        .onClick(() => this.settingsOpen = false)
      }
      .width('100%')
      .padding({ bottom: 16 })
      .border({ width: { bottom: 1 }, color: this.pal().border })

      Scroll() {
        Column({ space: 24 }) {
          Column({ space: 12 }) {
            this.sectionLabel('1. WYBIERZ MOTYW KOLORYSTYCZNY')
            Row({ space: 12 }) {
              this.themeCard(false)
              this.themeCard(true)
            }
            .width('100%')
          }

          Column({ space: 12 }) {
            Row() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.key'))
                  .fontSize(16)
                  .fontColor([AMBER])
                Text('2. Kod PIN do odblokowania')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal().text)
              }

              Blank()

              Text(this.pinConfigured ? 'Ustawiony' : 'Nieustawiony')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pinConfigured ? this.pal().okText : this.pal().warnText)
                .backgroundColor(this.pinConfigured ? this.pal().okBg : this.pal().warnBg)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(8)
            }
            .width('100%')

            Text(this.pinConfigured ?
              'Ten 4-cyfrowy kod jest wymagany do opuszczenia trybu gościa i powrotu do pełnej galerii.' :
              'Ustaw 4-cyfrowy kod. Będzie wymagany do opuszczenia trybu gościa.')
              .width('100%')
              .fontSize(12)
              .lineHeight(17)
              .fontColor(this.pal().textMuted)

            Row({ space: 12 }) {
              if (this.pinConfigured) {
                this.pinField(true)
              }
              this.pinField(false)
            }
            .width('100%')

            if (this.settingsError.length > 0) {
              Text(this.settingsError)
                .width('100%')
                .padding(10)
                .fontSize(12)
                .fontColor(this.pal().errorText)
                .backgroundColor(this.pal().errorBg)
                .borderRadius(12)
            }
            if (this.settingsSuccess.length > 0) {
              Text(this.settingsSuccess)
                .width('100%')
                .padding(10)
                .fontSize(12)
                .fontColor(this.pal().okText)
                .backgroundColor(this.pal().okBg)
                .borderRadius(12)
            }

            Button('Zapisz nowy kod PIN')
              .width('100%')
              .height(48)
              .borderRadius(12)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal().onPrimary)
              .backgroundColor(this.pal().primary)
              .onClick(() => this.changePin())
          }
          .padding(16)
          .borderRadius(16)
          .backgroundColor(this.pal().surface)
          .border({ width: 1, color: this.pal().border })

          Column({ space: 12 }) {
            this.sectionLabel('3. ZABEZPIECZENIA W TRYBIE GOŚCIA')
            this.settingToggle(true)
            this.settingToggle(false)
          }

          Column({ space: 12 }) {
            Row() {
              Row({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                  .fontSize(18)
                  .fontColor([AMBER])
                Text('Ograniczenia systemu OpenHarmony')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal().warnText)
              }

              Blank()

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(18)
                .fontColor([this.pal().warnText])
                .rotate({ angle: this.guideOpen ? 90 : 0 })
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(this.pal().warnBg)
            .border({ width: 1, color: this.pal().warnBorder })
            .onClick(() => this.guideOpen = !this.guideOpen)

            if (this.guideOpen) {
              Text('SafeShare nie może zablokować przycisków systemowych. Gość może wrócić do ekranu głównego i otworzyć ' +
                'inną aplikację, np. systemową Galerię. SafeShare wtedy natychmiast zablokuje się kodem PIN, ale nie ' +
                'zablokuje innych aplikacji.\n\nPrzed przekazaniem telefonu ustaw systemową blokadę ekranu. Pełna blokada ' +
                'w jednej aplikacji (tryb kiosku) wymaga urządzenia zarządzanego przez administratora (Enterprise Device ' +
                'Management).')
                .width('100%')
                .padding(16)
                .fontSize(12)
                .lineHeight(18)
                .fontColor(this.pal().textMuted)
                .backgroundColor(this.pal().surface)
                .borderRadius(16)
                .border({ width: 1, color: this.pal().border })
            }
          }
        }
        .padding({ top: 20, bottom: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      Button('Gotowe')
        .width('100%')
        .height(56)
        .borderRadius(16)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().onPrimary)
        .backgroundColor(this.pal().primary)
        .onClick(() => this.settingsOpen = false)
    }
    .width('100%')
    .height('90%')
    .padding(24)
    .borderRadius({ topLeft: 24, topRight: 24 })
    .backgroundColor(this.cardColor())
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
    .backgroundColor('#99000000')
    .onClick(() => this.settingsOpen = false)
  }

  // ---- Guest screen -----------------------------------------------------------------------

  @Builder
  private guestIconButton(isZoom: boolean) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(isZoom ? (this.guestZoom > 1 ? $r('sys.symbol.minus_magnifyingglass') :
        $r('sys.symbol.plus_magnifyingglass')) : $r('sys.symbol.info_circle'))
        .fontSize(20)
        .fontColor(['#D4D4D8'])
    }
    .width(44)
    .height(44)
    .borderRadius(16)
    .backgroundColor('#CC18181B')
    .border({ width: 1, color: '#993F3F46' })
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
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.lock_fill'))
          .fontSize(14)
          .fontColor([AMBER])
        Text(`Tryb Gościa: ${this.guestIndex + 1} / ${this.guestPhotos.length}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FCD34D')
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(999)
      .backgroundColor('#33F59E0B')
      .border({ width: 1, color: '#66F59E0B' })

      Blank()

      Row({ space: 8 }) {
        this.guestIconButton(true)
        if (this.showDetails) {
          this.guestIconButton(false)
        }
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.lock_fill'))
              .fontSize(16)
              .fontColor([AMBER])
            Text('Wyjdź (PIN)')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }
        }
        .height(44)
        .padding({ left: 16, right: 16 })
        .borderRadius(16)
        .backgroundColor('#E618181B')
        .border({ width: 1, color: '#3F3F46' })
        .onClick(() => {
          hapticTap();
          this.openPin(PinMode.EXIT, '');
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 28 })
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [['#E6000000', 0], ['#80000000', 0.5], ['#00000000', 1]]
    })
  }

  @Builder
  private guestThumb(photo: GalleryPhoto, index: number) {
    Image(photo.uri)
      .width(48)
      .height(48)
      .objectFit(ImageFit.Cover)
      .sourceSize({ width: 96, height: 96 })
      .borderRadius(8)
      .border({ width: 2, color: index === this.guestIndex ? AMBER : Color.Transparent })
      .opacity(index === this.guestIndex ? 1 : 0.5)
      .scale({ x: index === this.guestIndex ? 1.05 : 1, y: index === this.guestIndex ? 1.05 : 1 })
      .draggable(false)
      .onClick(() => {
        hapticTap();
        this.showGuestPhoto(index);
      })
  }

  @Builder
  private guestFooter() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.currentGuest().title)
            .width('100%')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.showDetails ?
            `${formatDateTime(this.currentGuest().takenAt)} · ${this.currentGuest().width}×${this.currentGuest().height}` :
            formatDateTime(this.currentGuest().takenAt))
            .width('100%')
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor('#94A3B8')
            .maxLines(1)
        }
        .layoutWeight(1)

        Text(`Okres: ${this.guestRangeLabel}`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(EMERALD)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor('#99022C22')
          .border({ width: 1, color: '#4D10B981' })
      }
      .width('100%')

      if (this.guestPhotos.length > 1) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.guestPhotos, (photo: GalleryPhoto, index: number) => {
              this.guestThumb(photo, index)
            }, (photo: GalleryPhoto) => photo.uri)

            Column() {
              SymbolGlyph($r('sys.symbol.lock_fill'))
                .fontSize(16)
                .fontColor(['#CCFBBF24'])
              Text(`+${this.lockedCount}`)
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontFamily('monospace')
                .fontColor('#CCFBBF24')
            }
            .width(48)
            .height(48)
            .borderRadius(8)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#E60F172A')
            .border({ width: 1, color: '#66F59E0B', style: BorderStyle.Dashed })
            .accessibilityText('Pozostałe zdjęcia w galerii są zablokowane')
            .onClick(() => {
              hapticAlarm();
              this.showBoundary(`${this.lockedCount} pozostałych prywatnych zdjęć jest zablokowane.`);
            })
          }
          .padding({ top: 4, bottom: 4, left: 2, right: 2 })
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 32, bottom: 24 })
    .linearGradient({
      direction: GradientDirection.Top,
      colors: [['#F2000000', 0], ['#CC000000', 0.5], ['#00000000', 1]]
    })
  }

  @Builder
  private guestInfoOverlay() {
    Column() {
      Column({ space: 10 }) {
        Row() {
          Text('Metadane zdjęcia')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
          Blank()
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor(['#94A3B8'])
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.guestInfoOpen = false)
        }
        .width('100%')
        .padding({ bottom: 10 })
        .border({ width: { bottom: 1 }, color: '#1E293B' })

        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(16)
            .fontColor([AMBER])
          Text(formatDateTime(this.currentGuest().takenAt))
            .fontSize(12)
            .fontColor('#E2E8F0')
        }
        .width('100%')
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(16)
            .fontColor(['#38BDF8'])
          Text(`${this.currentGuest().width} × ${this.currentGuest().height} px`)
            .fontSize(12)
            .fontColor('#E2E8F0')
        }
        .width('100%')
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.camera'))
            .fontSize(16)
            .fontColor([EMERALD])
          Text(this.guestCamera.length > 0 ? this.guestCamera : 'Brak danych o aparacie')
            .fontSize(12)
            .fontColor('#E2E8F0')
        }
        .width('100%')
      }
      .width('90%')
      .constraintSize({ maxWidth: 380 })
      .padding(20)
      .borderRadius(16)
      .backgroundColor('#0F172A')
      .border({ width: 1, color: '#1E293B' })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#CC000000')
    .onClick(() => this.guestInfoOpen = false)
  }

  @Builder
  private guestLocked() {
    Column({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.lock_fill'))
          .fontSize(32)
          .fontColor([AMBER])
      }
      .width(64)
      .height(64)
      .borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#1AF59E0B')
      .border({ width: 1, color: '#4DF59E0B' })

      Text('Galeria jest zablokowana')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
      Text('Sesja gościa została przerwana. Pozostałe zdjęcia są ukryte do czasu podania kodu PIN właściciela.')
        .fontSize(14)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .fontColor('#94A3B8')
      Button('Odblokuj galerię (kod PIN)')
        .height(40)
        .padding({ left: 24, right: 24 })
        .margin({ top: 12 })
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#020617')
        .backgroundColor(AMBER)
        .onClick(() => this.openPin(PinMode.RESUME,
          'Sesja gościa została przerwana. Wprowadź kod PIN właściciela, aby wrócić do galerii.'))
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#020617')
  }

  @Builder
  private guestScreen() {
    if (this.guestPhotos.length === 0) {
      this.guestLocked()
    } else {
      Stack() {
        Stack() {
          Image(this.currentGuest().uri)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .sourceSize({ width: 1600, height: 1600 })
            .scale({ x: this.guestZoom, y: this.guestZoom })
            .animation({ duration: 300, curve: Curve.EaseOut })
            .privacySensitive(true)
            .draggable(false)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
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
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.lock_fill'))
                .fontSize(16)
                .fontColor([AMBER])
              Text(this.boundaryAlert)
                .fontSize(12)
                .lineHeight(17)
                .fontColor('#FDE68A')
                .layoutWeight(1)
            }
            .margin({ left: 16, right: 16, bottom: 12 })
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .borderRadius(12)
            .backgroundColor('#E6451A03')
            .border({ width: 1, color: '#80F59E0B' })
            .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
          }
          this.guestFooter()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)

        if (this.guestInfoOpen) {
          this.guestInfoOverlay()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
    }
  }

  // ---- PIN overlay ------------------------------------------------------------------------

  @Builder
  private pinKey(digit: string) {
    Button({ type: ButtonType.Circle }) {
      Text(digit)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor(this.pal().text)
    }
    .width(72)
    .height(72)
    .backgroundColor(this.keyColor())
    .onClick(() => this.pressDigit(digit))
  }

  @Builder
  private pinOverlay() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          Column() {
            SymbolGlyph(this.isPanicPin() ? $r('sys.symbol.exclamationmark_triangle') : $r('sys.symbol.lock'))
              .fontSize(28)
              .fontColor([this.isPanicPin() ? DANGER : this.pal().text])
          }
          .width(56)
          .height(56)
          .borderRadius(16)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.isPanicPin() ? '#1AEF4444' : this.keyColor())
          .border({ width: this.isPanicPin() ? 1 : 0, color: '#33EF4444' })
          .margin({ bottom: 14 })

          Text(this.pinTitle())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().text)
            .margin({ bottom: 4 })
          Text(this.pinSubtitle())
            .fontSize(12)
            .lineHeight(18)
            .textAlign(TextAlign.Center)
            .fontColor(this.pal().textMuted)
            .constraintSize({ maxWidth: 270 })
            .margin({ bottom: 24 })

          Row({ space: 16 }) {
            ForEach(PIN_SLOTS, (slot: number) => {
              Circle()
                .width(16)
                .height(16)
                .fill(this.pinEntry.length > slot ? (this.pinError ? DANGER : this.pal().text) : this.keyColor())
                .scale({ x: this.pinEntry.length > slot ? 1.25 : 1, y: this.pinEntry.length > slot ? 1.25 : 1 })
                .animation({ duration: 150 })
            }, (slot: number) => slot.toString())
          }
          .margin({ bottom: 12 })

          Text(this.pinFeedback)
            .height(18)
            .fontSize(11)
            .fontColor(DANGER)
            .margin({ bottom: 12 })

          Column({ space: 14 }) {
            ForEach(KEYPAD_ROWS, (row: string[]) => {
              Row({ space: 18 }) {
                ForEach(row, (digit: string) => {
                  this.pinKey(digit)
                }, (digit: string) => digit)
              }
            }, (row: string[]) => row[0])

            Row({ space: 18 }) {
              Column()
                .width(72)
                .height(72)
              this.pinKey('0')
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.delete_left'))
                  .fontSize(22)
                  .fontColor([this.pal().textMuted])
              }
              .width(72)
              .height(72)
              .backgroundColor(Color.Transparent)
              .accessibilityText('Usuń cyfrę')
              .onClick(() => this.deleteDigit())
            }
          }

          Text('Zapomniałeś kodu PIN?')
            .fontSize(11)
            .fontColor(this.pal().textMuted)
            .margin({ top: 16 })
            .onClick(() => this.pinHintOpen = !this.pinHintOpen)
          if (this.pinHintOpen) {
            Text('Kodu nie da się odzyskać. Aby go zresetować, wyczyść dane aplikacji SafeShare w Ustawieniach systemu.')
              .margin({ top: 6 })
              .padding(8)
              .fontSize(11)
              .lineHeight(16)
              .textAlign(TextAlign.Center)
              .fontColor(this.pal().textMuted)
              .backgroundColor(this.keyColor())
              .borderRadius(8)
          }
          if (this.pinAttempts > 0) {
            Text(`Błędnych prób: ${this.pinAttempts}`)
              .margin({ top: 4 })
              .fontSize(10)
              .fontFamily('monospace')
              .fontColor(DANGER)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        if (this.isPinCancelable()) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(22)
              .fontColor([this.pal().textMuted])
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .accessibilityText('Anuluj')
          .onClick(() => this.closePin())
        }
      }
      .width('92%')
      .constraintSize({ maxWidth: 380 })
      .padding(28)
      .borderRadius(24)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.isPanicPin() ? DANGER : this.pal().border })
      .translate({ x: this.shakeOffset })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#CC000000')
  }

  build() {
    Stack() {
      if (this.guestMode) {
        this.guestScreen()
      } else {
        this.ownerScreen()
      }
      if (!this.guestMode && this.detailIndex >= 0 && this.detailIndex < this.photos.length) {
        this.detailOverlay(this.photos[this.detailIndex])
      }
      if (!this.guestMode && this.settingsOpen) {
        this.settingsOverlay()
      }
      if (this.pinMode !== PinMode.NONE) {
        this.pinOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.guestMode ? '#000000' : this.pal().page)
  }
}
