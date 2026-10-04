import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { formatCount, formatDateTime, formatDay, formatRangeShort, formatSize, kindLabel } from '../common/Format';
import { AMBER, DANGER, DARK, EMERALD, LIGHT, Palette } from '../common/Theme';
import {
  dayRange, hidePick, isInRange, isShared, isValidPin, ManualPicks, PIN_LENGTH, PresetKey, presetRange, startOfDay,
  TimeRange, togglePick
} from '../model/SessionRules';
import { PdfView } from '../components/PdfView';
import { ALL_KINDS, ItemKind } from '../model/Documents';
import { MAX_REQUEST_LENGTH, RangeProposal } from '../model/TextRange';
import { AppStore, PinCheck } from '../service/AppStore';
import { GalleryPhoto, loadPhotos, readCameraModel, requestGalleryAccess } from '../service/Gallery';
import { hapticAlarm, hapticLock, hapticTap, hapticUnlock } from '../service/Haptics';
import { AssistantResult, proposeRange, releaseAssistant } from '../service/RangeAssistant';
import { ImportResult, importDocuments, loadVault, readNote, removeDocument, VaultItem } from '../service/Vault';

const BOUNDARY_ALERT_MS = 3000;
const SWIPE_DISTANCE = 40;
const ZOOM_SCALE = 1.5;
const PROPOSAL_THUMBS = 5;

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
  [new PresetOption('today', 'Today', $r('sys.symbol.calendar'), '#EF4444', 'Current day'),
    new PresetOption('yesterday', 'Yesterday', $r('sys.symbol.clock'), '#60A5FA', 'Previous day')],
  [new PresetOption('weekend', 'Weekend', $r('sys.symbol.sunset_fill'), '#F97316', 'Last weekend'),
    new PresetOption('custom', 'Custom range', $r('sys.symbol.slider_horizontal_2'), '#A1A1AA', 'Select dates')]
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
  @State private picks: ManualPicks = { added: [], removed: [] };
  @State private shareKinds: ItemKind[] = ALL_KINDS.slice();
  @State private ownerTab: ItemKind = 'photo';

  // Imported notes and PDFs.
  @State private documents: VaultItem[] = [];
  @State private importBusy: boolean = false;
  @State private importMessage: string = '';
  @State private docPreview: VaultItem | null = null;
  @State private docPreviewText: string = '';
  @State private confirmDelete: boolean = false;
  @State private ownerViewport: number = 0;

  // Text-described period: the assistant only proposes, the owner approves.
  @State private assistantText: string = '';
  @State private assistantBusy: boolean = false;
  @State private assistantMessage: string = '';
  @State private proposal: RangeProposal | null = null;
  @State private proposalExcluded: string[] = [];

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
  @State private guestDocs: VaultItem[] = [];
  @State private guestTab: ItemKind = 'photo';
  @State private guestDoc: VaultItem | null = null;
  @State private guestNote: string = '';
  @State private lockedDocs: number = 0;
  @State private guestIndex: number = 0;
  @State private guestZoom: number = 1;
  @State private guestInfoOpen: boolean = false;
  @State private guestCamera: string = '';
  @State private guestRangeLabel: string = '';
  @State private lockedCount: number = 0;
  @State private boundaryAlert: string = '';

  private store: AppStore = new AppStore();
  private pinFirst: string = '';
  private assistantRequest: number = 0;
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
        'Back/exit attempt blocked! The owner PIN is required.');
      return true;
    }
    if (this.detailIndex >= 0) {
      this.detailIndex = -1;
      return true;
    }
    if (this.docPreview !== null) {
      this.docPreview = null;
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
    this.openPin(PinMode.PANIC, 'App switch or minimize attempt detected! The screen has been locked.');
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
        this.guestDocs = [];
        this.guestMode = true;
        this.setImmersive(true);
        this.openPin(PinMode.RESUME, 'The guest session was interrupted. Enter the owner PIN to return to the gallery.');
      }
    } catch (error) {
      this.storeError = true;
    }
    this.applySystemBars();
    try {
      this.documents = await loadVault(this.context());
    } catch (error) {
      this.importMessage = 'Could not load notes and PDFs.';
    }
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

  // Photos, notes and PDFs share one rule: the kind is enabled, then period plus manual picks.
  private itemShared(kind: ItemKind, uri: string, time: number, range: TimeRange): boolean {
    return this.shareKinds.includes(kind) && isShared(uri, isInRange(time, range), this.picks);
  }

  private itemManual(kind: ItemKind, uri: string, time: number): boolean {
    return this.shareKinds.includes(kind) && this.itemShared(kind, uri, time, this.range()) !==
      isInRange(time, this.range());
  }

  private isAllowed(photo: GalleryPhoto): boolean {
    return this.itemShared('photo', photo.uri, photo.takenAt, this.range());
  }

  private isManual(photo: GalleryPhoto): boolean {
    return this.itemManual('photo', photo.uri, photo.takenAt);
  }

  private isDocAllowed(doc: VaultItem): boolean {
    return this.itemShared(doc.kind, doc.path, doc.createdAt, this.range());
  }

  private isDocManual(doc: VaultItem): boolean {
    return this.itemManual(doc.kind, doc.path, doc.createdAt);
  }

  private allowedPhotos(): GalleryPhoto[] {
    const range = this.range();
    return this.photos.filter((photo: GalleryPhoto) => this.itemShared('photo', photo.uri, photo.takenAt, range));
  }

  private allowedDocs(): VaultItem[] {
    const range = this.range();
    return this.documents.filter((doc: VaultItem) => this.itemShared(doc.kind, doc.path, doc.createdAt, range));
  }

  private docsOf(kind: ItemKind): VaultItem[] {
    return this.documents.filter((doc: VaultItem) => doc.kind === kind);
  }

  private allowedCount(): number {
    return this.allowedPhotos().length + this.allowedDocs().length;
  }

  private totalCount(): number {
    return this.photos.length + this.documents.length;
  }

  // Only picks that change something in the current period count, for enabled kinds.
  private manualCount(added: boolean): number {
    const range = this.range();
    const counts = (kind: ItemKind, uri: string, time: number): boolean => {
      const inRange = isInRange(time, range);
      return this.shareKinds.includes(kind) && inRange !== added && isShared(uri, inRange, this.picks) === added;
    };
    return this.photos.filter((photo: GalleryPhoto) => counts('photo', photo.uri, photo.takenAt)).length +
      this.documents.filter((doc: VaultItem) => counts(doc.kind, doc.path, doc.createdAt)).length;
  }

  private hasManualPicks(): boolean {
    return this.manualCount(true) + this.manualCount(false) > 0;
  }

  private togglePhoto(photo: GalleryPhoto): void {
    hapticTap();
    this.picks = togglePick(photo.uri, isInRange(photo.takenAt, this.range()), this.picks);
  }

  private toggleDoc(doc: VaultItem): void {
    if (!this.shareKinds.includes(doc.kind)) {
      return;
    }
    hapticTap();
    this.picks = togglePick(doc.path, isInRange(doc.createdAt, this.range()), this.picks);
  }

  private toggleKind(kind: ItemKind): void {
    hapticTap();
    this.shareKinds = this.shareKinds.includes(kind) ? this.shareKinds.filter((item: ItemKind) => item !== kind) :
      ALL_KINDS.filter((item: ItemKind) => item === kind || this.shareKinds.includes(item));
  }

  private async importKind(kind: ItemKind): Promise<void> {
    if (this.importBusy) {
      return;
    }
    this.importBusy = true;
    this.importMessage = '';
    let result = new ImportResult(this.documents, '');
    try {
      result = await importDocuments(this.context(), kind, this.documents);
    } catch (error) {
      result = new ImportResult(this.documents, 'Could not import files.');
    }
    this.importBusy = false;
    if (!this.guestMode) {
      this.documents = result.items;
      this.importMessage = result.message;
    }
  }

  private async openDocPreview(doc: VaultItem): Promise<void> {
    this.docPreview = doc;
    this.docPreviewText = '';
    this.confirmDelete = false;
    if (doc.kind === 'note') {
      try {
        const text = await readNote(doc);
        if (this.docPreview !== null && this.docPreview.id === doc.id) {
          this.docPreviewText = text;
        }
      } catch (error) {
        this.docPreviewText = 'Could not read the note.';
      }
    }
  }

  private async deleteDoc(doc: VaultItem): Promise<void> {
    if (!this.confirmDelete) {
      this.confirmDelete = true;
      return;
    }
    try {
      this.documents = await removeDocument(this.context(), this.documents, doc.id);
      this.picks = {
        added: this.picks.added.filter((uri: string) => uri !== doc.path),
        removed: this.picks.removed.filter((uri: string) => uri !== doc.path)
      };
      this.docPreview = null;
    } catch (error) {
      this.importMessage = 'Could not delete the file.';
    }
  }

  private resetPicks(): void {
    hapticTap();
    this.picks = { added: [], removed: [] };
  }

  private rangeLabel(): string {
    if (this.preset === 'today') {
      return 'Today';
    }
    if (this.preset === 'yesterday') {
      return 'Yesterday';
    }
    if (this.preset === 'weekend') {
      return 'Weekend';
    }
    return formatRangeShort(this.range());
  }

  private canHandOff(): boolean {
    return this.storeReady && this.privacyReady && this.allowedCount() > 0;
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

  // ---- Text period assistant ---------------------------------------------------------------

  private async askAssistant(): Promise<void> {
    if (this.assistantBusy) {
      return;
    }
    hapticTap();
    this.getUIContext().getFocusController().clearFocus(); // hide the keyboard over the result
    const request = ++this.assistantRequest;
    this.assistantBusy = true;
    this.assistantMessage = '';
    this.proposal = null;
    this.proposalExcluded = [];
    let result = new AssistantResult(null, '');
    try {
      result = await proposeRange(this.context(), this.assistantText, Date.now());
    } catch (error) {
      result = new AssistantResult(null, 'The AI assistant encountered an error. Select a period using the buttons.');
    }
    if (request !== this.assistantRequest) {
      return; // superseded or cancelled by a hand-off
    }
    this.assistantBusy = false;
    this.proposal = result.proposal;
    this.assistantMessage = result.message;
  }

  // A proposal or message about older text must not stay approvable.
  private editAssistantText(value: string): void {
    if (value !== this.assistantText) {
      this.assistantText = value;
      this.cancelAssistant();
    }
  }

  private cancelAssistant(): void {
    this.assistantRequest++;
    this.assistantBusy = false;
    this.assistantMessage = '';
    this.proposal = null;
    this.proposalExcluded = [];
  }

  private excludeFromProposal(uri: string): void {
    hapticTap();
    this.proposalExcluded = this.proposalExcluded.concat(uri);
  }

  private approveProposal(): void {
    const proposal = this.proposal;
    if (proposal === null) {
      return;
    }
    hapticTap();
    let picks = this.picks;
    this.photos.filter((photo: GalleryPhoto) => this.proposalExcluded.includes(photo.uri)).forEach(
      (photo: GalleryPhoto) => {
        picks = hidePick(photo.uri, isInRange(photo.takenAt, proposal.range), picks);
      });
    this.documents.filter((doc: VaultItem) => this.proposalExcluded.includes(doc.path)).forEach(
      (doc: VaultItem) => {
        picks = hidePick(doc.path, isInRange(doc.createdAt, proposal.range), picks);
      });
    this.picks = picks;
    if (proposal.preset === 'custom') {
      this.customStart = startOfDay(proposal.range.start);
      this.customEnd = startOfDay(proposal.range.end);
    }
    this.preset = proposal.preset;
    this.shareKinds = proposal.kinds.slice();
    this.proposal = null;
    this.proposalExcluded = [];
    this.assistantText = '';
  }

  // Items the guest would see after approval, including the owner's manual picks.
  private proposalPhotos(): GalleryPhoto[] {
    const proposal = this.proposal;
    if (proposal === null || !proposal.kinds.includes('photo')) {
      return [];
    }
    return this.photos.filter((photo: GalleryPhoto) => !this.proposalExcluded.includes(photo.uri) &&
      isShared(photo.uri, isInRange(photo.takenAt, proposal.range), this.picks));
  }

  private proposalDocs(kind: ItemKind): VaultItem[] {
    const proposal = this.proposal;
    if (proposal === null || !proposal.kinds.includes(kind)) {
      return [];
    }
    return this.docsOf(kind).filter((doc: VaultItem) => !this.proposalExcluded.includes(doc.path) &&
      isShared(doc.path, isInRange(doc.createdAt, proposal.range), this.picks));
  }

  private proposalSummary(): string {
    const proposal = this.proposal;
    if (proposal === null) {
      return '';
    }
    return proposal.kinds.map((kind: ItemKind) => formatCount(kind,
      kind === 'photo' ? this.proposalPhotos().length : this.proposalDocs(kind).length)).join(' · ');
  }

  private proposalEmpty(): boolean {
    return this.proposalPhotos().length + this.proposalDocs('note').length + this.proposalDocs('pdf').length === 0;
  }

  private proposalLabel(): string {
    const proposal = this.proposal;
    if (proposal === null) {
      return '';
    }
    if (proposal.preset === 'custom') {
      return formatRangeShort(proposal.range);
    }
    return proposal.preset === 'today' ? 'Today' : proposal.preset === 'yesterday' ? 'Yesterday' : 'Weekend';
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
      this.openPin(PinMode.CREATE, 'Choose a 4-digit code. It will be required to exit guest mode.');
      return;
    }
    this.enterGuest();
  }

  private enterGuest(): void {
    const allowed = this.allowedPhotos();
    const docs = this.allowedDocs();
    if (allowed.length + docs.length === 0) {
      return;
    }
    this.cancelAssistant();
    releaseAssistant();
    this.guestPhotos = allowed;
    this.guestDocs = docs;
    this.guestTab = allowed.length > 0 ? 'photo' : docs[0].kind;
    this.guestDoc = null;
    this.guestNote = '';
    this.docPreview = null;
    this.lockedCount = this.photos.length - allowed.length;
    this.lockedDocs = this.documents.length - docs.length;
    this.guestRangeLabel = this.manualCount(true) > 0 ? `${this.rangeLabel()} + selected` : this.rangeLabel();
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
    this.guestDocs = [];
    this.guestDoc = null;
    this.guestNote = '';
    this.guestInfoOpen = false;
    this.boundaryAlert = '';
    this.setImmersive(false);
    this.applySystemBars();
    this.store.setGuestActive(false).catch(() => {});
    if (this.access === Access.GRANTED) {
      this.reloadPhotos();
    }
  }

  // Tabs the guest can open: only kinds with shared items.
  private guestKinds(): ItemKind[] {
    return ALL_KINDS.filter((kind: ItemKind) => kind === 'photo' ? this.guestPhotos.length > 0 :
      this.guestDocs.some((doc: VaultItem) => doc.kind === kind));
  }

  private showGuestTab(kind: ItemKind): void {
    hapticTap();
    this.guestTab = kind;
    this.guestDoc = null;
    this.guestInfoOpen = false;
  }

  private async openGuestDoc(doc: VaultItem): Promise<void> {
    hapticTap();
    this.guestNote = '';
    this.guestDoc = doc;
    if (doc.kind === 'note') {
      try {
        const text = await readNote(doc);
        if (this.guestDoc !== null && this.guestDoc.id === doc.id) {
          this.guestNote = text;
        }
      } catch (error) {
        this.guestNote = 'Could not read the note.';
      }
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
      this.showBoundary(`End of shared photos from this period. The remaining ${this.lockedCount} gallery photos are locked.`);
    }
  }

  private previousPhoto(): void {
    if (this.guestIndex > 0) {
      hapticTap();
      this.showGuestPhoto(this.guestIndex - 1);
    } else {
      hapticAlarm();
      this.showBoundary('There are no earlier photos in the selected range. The rest of the gallery is safely hidden.');
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
      this.pinFeedback = `Too many failed attempts. Try again in ${seconds} s.`;
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
        return 'Set PIN';
      case PinMode.CONFIRM:
        return 'Repeat PIN';
      case PinMode.PANIC:
        return 'Exit attempt detected!';
      case PinMode.RESUME:
        return 'Gallery locked';
      default:
        return 'Exit Guest Mode';
    }
  }

  private pinSubtitle(): string {
    if (this.pinMessage.length > 0) {
      return this.pinMessage;
    }
    return 'Enter the owner PIN to unlock the rest of the phone gallery.';
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
      this.pinMessage = 'Enter the same code again.';
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
        this.rejectPin(`Too many failed attempts. Try again in ${this.store.lockSecondsLeft()} s.`);
      } else {
        this.pinAttempts++;
        this.rejectPin(`Incorrect PIN. Attempts remaining: ${this.store.attemptsLeft()}.`);
      }
    } catch (error) {
      this.rejectPin('Could not verify the PIN.');
    } finally {
      this.pinBusy = false;
    }
  }

  private async confirmNewPin(pin: string): Promise<void> {
    if (pin !== this.pinFirst) {
      this.pinFirst = '';
      this.pinMode = PinMode.CREATE;
      this.pinMessage = 'Choose a 4-digit code. It will be required to exit guest mode.';
      this.rejectPin('The codes do not match. Set the PIN again.');
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
      this.rejectPin('Could not save the PIN.');
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
      this.settingsError = 'Could not save settings.';
    });
  }

  private async changePin(): Promise<void> {
    this.settingsError = '';
    this.settingsSuccess = '';
    if (!isValidPin(this.newPinInput)) {
      hapticAlarm();
      this.settingsError = 'The new PIN must contain 4 digits!';
      return;
    }
    try {
      if (this.store.hasPin()) {
        const result = await this.store.checkPin(this.currentPinInput);
        if (result !== PinCheck.OK) {
          hapticAlarm();
          this.settingsError = result === PinCheck.LOCKED ?
            `Too many failed attempts. Try again in ${this.store.lockSecondsLeft()} s.` :
            'The current PIN is incorrect!';
          return;
        }
      }
      await this.store.setPin(this.newPinInput);
    } catch (error) {
      this.settingsError = 'Could not save the PIN.';
      return;
    }
    hapticUnlock();
    this.pinConfigured = true;
    this.currentPinInput = '';
    this.newPinInput = '';
    this.settingsSuccess = 'PIN changed successfully!';
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

  // Whole photo, between square (portraits) and 16:9, so the card still fits a phone screen.
  private previewAspect(photo: GalleryPhoto): number {
    if (photo.width <= 0 || photo.height <= 0) {
      return 1;
    }
    return Math.min(Math.max(photo.width / photo.height, 1), 16 / 9);
  }

  private async openDetail(index: number): Promise<void> {
    hapticTap();
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
  private header() {
    Row() {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(20)
          .fontColor([this.pal().text])
      }
      .width(40)
      .height(40)
      .borderRadius(14)
      .backgroundColor(this.pal().surface)
      .border({ width: 1, color: this.pal().border })
      .accessibilityText('Settings')
      .onClick(() => this.openSettings())
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.End)
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
      Text(isStart ? 'Start date (FROM)' : 'End date (TO)')
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
      Text(visible ? `${this.allowedCount()} visible` : `${this.totalCount() - this.allowedCount()} hidden`)
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
  private picksBar() {
    Row({ space: 8 }) {
      SymbolGlyph(this.hasManualPicks() ? $r('sys.symbol.hand_tap') : $r('sys.symbol.info_circle'))
        .fontSize(14)
        .fontColor([this.pal().textMuted])
      Text(this.hasManualPicks() ? `Manual changes: +${this.manualCount(true)} / −${this.manualCount(false)}` :
        'Tap a photo to show or hide it. Hold to preview.')
        .fontSize(11)
        .lineHeight(15)
        .fontColor(this.pal().textMuted)
        .layoutWeight(1)
      if (this.hasManualPicks()) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
            .fontSize(12)
            .fontColor([this.pal().text])
          Text('Undo changes')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal().text)
        }
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(8)
        .backgroundColor(this.pal().surface)
        .border({ width: 1, color: this.pal().border })
        .onClick(() => this.resetPicks())
      }
    }
    .width('100%')
  }

  @Builder
  private assistantBar() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.assistantText, placeholder: 'Describe a period, e.g. photos from the last 3 days' })
          .layoutWeight(1)
          .height(44)
          .maxLength(MAX_REQUEST_LENGTH)
          .fontSize(13)
          .fontColor(this.pal().text)
          .placeholderColor(this.pal().textMuted)
          .backgroundColor(this.pal().surface)
          .border({ width: 1, color: this.pal().border })
          .borderRadius(12)
          .enterKeyType(EnterKeyType.Send)
          .enabled(!this.assistantBusy)
          .onChange((value: string) => this.editAssistantText(value))
          .onSubmit(() => this.askAssistant())
        Button({ type: ButtonType.Normal }) {
          if (this.assistantBusy) {
            LoadingProgress()
              .width(24)
              .height(24)
              .color(this.pal().onPrimary)
          } else {
            SymbolGlyph($r('sys.symbol.wand_and_stars'))
              .fontSize(20)
              .fontColor([this.pal().onPrimary])
          }
        }
        .width(44)
        .height(44)
        .borderRadius(12)
        .backgroundColor(this.pal().primary)
        .enabled(!this.assistantBusy && this.assistantText.trim().length > 0)
        .opacity(this.assistantText.trim().length > 0 ? 1 : 0.4)
        .accessibilityText('Suggest a period from the description')
        .onClick(() => this.askAssistant())
      }
      .width('100%')

      if (this.assistantMessage.length > 0) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(14)
            .fontColor([this.pal().warnText])
          Text(this.assistantMessage)
            .fontSize(12)
            .lineHeight(16)
            .fontColor(this.pal().warnText)
            .layoutWeight(1)
        }
        .width('100%')
        .padding(10)
        .borderRadius(12)
        .backgroundColor(this.pal().warnBg)
        .border({ width: 1, color: this.pal().warnBorder })
      }

      if (this.proposal !== null) {
        this.proposalCard()
      }
    }
    .width('100%')
  }

  @Builder
  private proposalCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.wand_and_stars'))
          .fontSize(16)
          .fontColor([AMBER])
        Text(`Proposal: ${this.proposalLabel()}`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .layoutWeight(1)
      }
      .width('100%')

      Text(this.proposalSummary())
        .width('100%')
        .fontSize(12)
        .fontColor(this.pal().textMuted)

      if (this.proposalPhotos().length > 0) {
        Row({ space: 6 }) {
          ForEach(this.proposalPhotos().slice(0, PROPOSAL_THUMBS), (photo: GalleryPhoto) => {
            Stack({ alignContent: Alignment.TopEnd }) {
              Image(photo.uri)
                .width(44)
                .height(44)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
                .sourceSize({ width: 120, height: 120 })
                .draggable(false)
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(10)
                  .fontColor(['#FFFFFF'])
              }
              .width(20)
              .height(20)
              .backgroundColor(DANGER)
              .accessibilityText(`Remove ${photo.title} from proposal`)
              .onClick(() => this.excludeFromProposal(photo.uri))
            }
          }, (photo: GalleryPhoto) => photo.uri)
          if (this.proposalPhotos().length > PROPOSAL_THUMBS) {
            Text(`+${this.proposalPhotos().length - PROPOSAL_THUMBS}`)
              .width(44)
              .height(44)
              .borderRadius(8)
              .textAlign(TextAlign.Center)
              .fontSize(12)
              .fontColor(this.pal().textMuted)
              .backgroundColor(this.pal().surfaceHover)
          }
        }
        .width('100%')
      }

      ForEach(this.proposalDocs('note').concat(this.proposalDocs('pdf')).slice(0, PROPOSAL_THUMBS),
        (doc: VaultItem) => {
          Row({ space: 6 }) {
            SymbolGlyph(doc.kind === 'pdf' ? $r('sys.symbol.doc') : $r('sys.symbol.notepad'))
              .fontSize(14)
              .fontColor([this.pal().textMuted])
            Text(doc.name)
              .fontSize(12)
              .fontColor(this.pal().text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(10)
                .fontColor([this.pal().textMuted])
            }
            .width(28)
            .height(28)
            .backgroundColor(this.pal().surfaceHover)
            .accessibilityText(`Remove ${doc.name} from proposal`)
            .onClick(() => this.excludeFromProposal(doc.path))
          }
          .width('100%')
        }, (doc: VaultItem) => doc.id)

      Text(this.proposalEmpty() ? 'There are no files in this period. The selection changes only after approval.' :
        'Review the files and remove any you do not want to share. Selection changes only after approval.')
        .width('100%')
        .fontSize(11)
        .fontColor(this.pal().textMuted)

      Row({ space: 8 }) {
        Button('Reject')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontColor(this.pal().text)
          .backgroundColor(this.pal().surfaceHover)
          .onClick(() => this.cancelAssistant())
        Button('Approve')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().onPrimary)
          .backgroundColor(this.pal().primary)
          .onClick(() => this.approveProposal())
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(16)
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: AMBER })
  }

  @Builder
  private filterBar() {
    Column({ space: 14 }) {
      Column({ space: 8 }) {
        Text('PERIOD TO SHOW:')
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

      this.assistantBar()

      if (this.preset === 'custom') {
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(16)
              .fontColor(['#0EA5E9'])
            Text('Select a date range (FROM - TO):')
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

      this.picksBar()
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
    Stack({ alignContent: Alignment.TopEnd }) {
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
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(['#FFFFFF'])
        }
        .width(22)
        .height(22)
        .margin(6)
        .borderRadius(11)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(EMERALD)
        .border({ width: 1.5, color: '#FFFFFF' })
      }
    }
    .width('100%')
    .aspectRatio(1)
    .borderRadius(12)
    .clip(true)
    .backgroundColor(this.pal().surface)
    .border({ width: this.isManual(photo) ? 2 : 1, color: this.isManual(photo) ? AMBER : this.pal().border })
    .opacity(this.isAllowed(photo) ? 1 : 0.4)
    .animation({ duration: 150, curve: Curve.EaseOut })
    .accessibilityText(this.isAllowed(photo) ? `${photo.title}, visible to guest` : `${photo.title}, hidden`)
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture()
          .onAction(() => this.openDetail(index)),
        TapGesture()
          .onAction(() => this.togglePhoto(photo))
      )
    )
  }

  @Builder
  private galleryBody() {
    if (this.access === Access.LOADING) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(this.pal().textMuted)
        Text('Loading gallery…')
          .fontSize(13)
          .fontColor(this.pal().textMuted)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.access === Access.DENIED) {
      this.galleryMessage('No gallery access',
        'SafeShare needs permission to read photos and show them by date. Photos never leave the phone.',
        'Allow access', () => this.refreshGallery(true))
    } else if (this.access === Access.ERROR) {
      this.galleryMessage('Could not load the gallery', 'Try again in a moment.',
        'Try again', () => this.refreshGallery(false))
    } else if (this.photos.length === 0) {
      this.galleryMessage('No photos in the gallery', 'Take a photo or copy photos to the phone.', '', () => {})
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
      .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      .layoutWeight(1)
    }
  }

  @Builder
  private ownerTabs() {
    Row({ space: 8 }) {
      ForEach(ALL_KINDS, (kind: ItemKind) => {
        Row({ space: 6 }) {
          SymbolGlyph(kind === 'photo' ? $r('sys.symbol.picture') : kind === 'note' ? $r('sys.symbol.notepad') :
            $r('sys.symbol.doc'))
            .fontSize(14)
            .fontColor([this.ownerTab === kind ? this.pal().onPrimary : this.pal().textMuted])
          Text(`${kindLabel(kind)} ${kind === 'photo' ? this.photos.length : this.docsOf(kind).length}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.ownerTab === kind ? this.pal().onPrimary : this.pal().text)
        }
        .layoutWeight(1)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .borderRadius(12)
        .backgroundColor(this.ownerTab === kind ? this.pal().primary : this.pal().surface)
        .border({ width: 1, color: this.ownerTab === kind ? this.pal().primary : this.pal().border })
        .accessibilityText(`${kindLabel(kind)} tab`)
        .onClick(() => {
          hapticTap();
          this.ownerTab = kind;
        })
      }, (kind: ItemKind) => kind)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10 })
  }

  @Builder
  private kindToggle(kind: ItemKind) {
    Row({ space: 8 }) {
      Toggle({ type: ToggleType.Switch, isOn: this.shareKinds.includes(kind) })
        .selectedColor(EMERALD)
        .onChange((isOn: boolean) => {
          if (isOn !== this.shareKinds.includes(kind)) {
            this.toggleKind(kind);
          }
        })
      Text(kind === 'photo' ? 'Share photos' : kind === 'note' ? 'Share notes' : 'Share PDFs')
        .fontSize(13)
        .fontColor(this.pal().text)
        .layoutWeight(1)
      if (kind !== 'photo') {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            if (this.importBusy) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(this.pal().text)
            } else {
              SymbolGlyph($r('sys.symbol.folder_badge_plus'))
                .fontSize(16)
                .fontColor([this.pal().text])
            }
            Text('Import')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal().text)
          }
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .borderRadius(10)
        .backgroundColor(this.pal().surface)
        .border({ width: 1, color: this.pal().border })
        .enabled(!this.importBusy)
        .onClick(() => this.importKind(kind))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 8 })
  }

  @Builder
  private docRow(doc: VaultItem) {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph(doc.kind === 'pdf' ? $r('sys.symbol.doc') : $r('sys.symbol.notepad'))
          .fontSize(20)
          .fontColor([doc.kind === 'pdf' ? '#F87171' : '#60A5FA'])
      }
      .width(40)
      .height(40)
      .borderRadius(10)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.pal().surfaceHover)

      Column({ space: 2 }) {
        Text(doc.name)
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${formatDateTime(doc.createdAt)} · ${formatSize(doc.size)}`)
          .width('100%')
          .fontSize(11)
          .fontColor(this.pal().textMuted)
          .maxLines(1)
      }
      .layoutWeight(1)

      SymbolGlyph(this.isDocAllowed(doc) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.lock_fill'))
        .fontSize(18)
        .fontColor([this.isDocAllowed(doc) ? EMERALD : this.pal().textMuted])
    }
    .width('100%')
    .padding(10)
    .borderRadius(12)
    .backgroundColor(this.pal().surface)
    .border({ width: this.isDocManual(doc) ? 2 : 1, color: this.isDocManual(doc) ? AMBER : this.pal().border })
    .opacity(this.isDocAllowed(doc) ? 1 : 0.5)
    .accessibilityText(this.isDocAllowed(doc) ? `${doc.name}, visible to guest` : `${doc.name}, hidden`)
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture()
          .onAction(() => this.openDocPreview(doc)),
        TapGesture()
          .onAction(() => this.toggleDoc(doc))
      )
    )
  }

  @Builder
  private documentsBody(kind: ItemKind) {
    Column({ space: 8 }) {
      this.kindToggle(kind)
      if (this.importMessage.length > 0) {
        Text(this.importMessage)
          .width('100%')
          .padding({ left: 16, right: 16 })
          .fontSize(12)
          .fontColor(this.pal().textMuted)
      }
      if (this.docsOf(kind).length === 0) {
        this.galleryMessage(kind === 'note' ? 'No notes' : 'No PDF files',
          kind === 'note' ? 'Import notes from .txt or .md files. Copies will be stored in the app vault.' :
            'Import PDF files. Copies will be stored in the app vault.',
          'Import', () => this.importKind(kind))
      } else {
        List({ space: 8 }) {
          ForEach(this.docsOf(kind), (doc: VaultItem) => {
            ListItem() {
              this.docRow(doc)
            }
          }, (doc: VaultItem) => doc.id)
        }
        .layoutWeight(1)
        .padding({ left: 12, right: 12, bottom: 100 })
        .scrollBar(BarState.Off)
        .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private docPreviewOverlay(doc: VaultItem) {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([this.pal().text])
        }
        .width(40)
        .height(40)
        .backgroundColor(this.pal().surface)
        .accessibilityText('Close preview')
        .onClick(() => this.docPreview = null)
        Text(doc.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding(12)

      if (doc.kind === 'pdf') {
        PdfView({ path: doc.path })
          .layoutWeight(1)
      } else {
        Scroll() {
          Text(this.docPreviewText)
            .width('100%')
            .fontSize(14)
            .lineHeight(21)
            .fontColor(this.pal().text)
        }
        .layoutWeight(1)
        .padding(16)
        .align(Alignment.TopStart)
      }

      Row({ space: 8 }) {
        Button(this.confirmDelete ? 'Delete permanently?' : 'Delete from vault')
          .layoutWeight(1)
          .height(44)
          .fontSize(13)
          .fontColor('#FFFFFF')
          .backgroundColor(DANGER)
          .onClick(() => this.deleteDoc(doc))
        Button(this.isDocAllowed(doc) ? 'Hide from guest' : 'Show to guest')
          .layoutWeight(1)
          .height(44)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().onPrimary)
          .backgroundColor(this.pal().primary)
          .enabled(this.shareKinds.includes(doc.kind))
          .onClick(() => this.toggleDoc(doc))
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().page)
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

          Text(`Lock and hand over phone (${this.allowedCount()})`)
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
        // The period controls scroll away first, then the grid or list scrolls (nestedScroll).
        Scroll() {
          Column() {
            this.filterBar()
            if (this.storeError) {
              Column() {
                this.notice('App storage is unavailable. Guest mode is blocked.')
              }
              .padding({ left: 16, right: 16, top: 12 })
            } else if (!this.privacyReady) {
              Column() {
                this.notice('Could not enable screenshot protection. Guest mode is blocked.')
              }
              .padding({ left: 16, right: 16, top: 12 })
            }
            this.ownerTabs()
            Column() {
              // One branch per kind: @Builder arguments are copied, so a shared branch would not
              // re-render when the tab changes between notes and PDFs.
              if (this.ownerTab === 'photo') {
                this.kindToggle('photo')
                this.galleryBody()
              } else if (this.ownerTab === 'note') {
                this.documentsBody('note')
              } else {
                this.documentsBody('pdf')
              }
            }
            .width('100%')
            .height(this.ownerViewport)
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .onAreaChange((oldArea: Area, newArea: Area) => this.ownerViewport = Number(newArea.height))
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
            .aspectRatio(this.previewAspect(photo))
            .objectFit(ImageFit.Contain)
            .sourceSize({ width: 1200, height: 1200 })
            .backgroundColor('#000000')
            .draggable(false)

          Row() {
            Row({ space: 4 }) {
              SymbolGlyph(this.isAllowed(photo) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.lock_fill'))
                .fontSize(12)
                .fontColor([this.isAllowed(photo) ? '#FFFFFF' : AMBER])
              Text((this.isAllowed(photo) ? 'Available to guest' : 'Locked') +
                (this.isManual(photo) ? ' · manual' : ''))
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
            .accessibilityText('Close')
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
            Text(this.detailCamera.length > 0 ? this.detailCamera : 'No camera data')
              .fontSize(12)
              .fontColor(this.pal().textMuted)
              .layoutWeight(1)
          }
          .width('100%')
          Divider()
            .color(this.pal().border)

          Row() {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 6 }) {
                SymbolGlyph(this.isAllowed(photo) ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
                  .fontSize(14)
                  .fontColor([this.isAllowed(photo) ? this.pal().text : this.pal().onPrimary])
                Text(this.isAllowed(photo) ? 'Hide from guest' : 'Show to guest')
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isAllowed(photo) ? this.pal().text : this.pal().onPrimary)
              }
            }
            .height(32)
            .padding({ left: 14, right: 14 })
            .borderRadius(16)
            .backgroundColor(this.isAllowed(photo) ? (this.darkTheme ? DARK.surfaceHover : LIGHT.surface) :
              this.pal().primary)
            .onClick(() => this.togglePhoto(photo))

            Blank()

            Button('Close')
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
    .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
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
        Text(dark ? 'Dark theme' : 'Light theme')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
        Text(dark ? 'OLED black' : 'Pure white')
          .fontSize(11)
          .fontColor(this.pal().textMuted)
      }

      if (this.darkTheme === dark) {
        Text('Active')
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
      Text(isCurrent ? 'Current PIN:' : 'New PIN:')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().textMuted)
      TextInput({ text: isCurrent ? this.currentPinInput : this.newPinInput, placeholder: '4 digits' })
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
        Text(isLeaveAlarm ? 'Alert on app exit attempt' : 'Hide photo details')
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
        Text(isLeaveAlarm ?
          'Locks the screen with the PIN immediately when the guest returns to the home screen, switches apps or minimizes it.' :
          'A guest viewing photos will not see the camera model or resolution.')
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
          Text('App settings')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().text)
          Text('Appearance and PIN protection')
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
        .accessibilityText('Close')
        .onClick(() => this.settingsOpen = false)
      }
      .width('100%')
      .padding({ bottom: 16 })
      .border({ width: { bottom: 1 }, color: this.pal().border })

      Scroll() {
        Column({ space: 24 }) {
          Column({ space: 12 }) {
            this.sectionLabel('1. SELECT COLOR THEME')
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
                Text('2. Unlock PIN')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal().text)
              }

              Blank()

              Text(this.pinConfigured ? 'Set' : 'Not set')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pinConfigured ? this.pal().okText : this.pal().warnText)
                .backgroundColor(this.pinConfigured ? this.pal().okBg : this.pal().warnBg)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(8)
            }
            .width('100%')

            Text(this.pinConfigured ?
              'This 4-digit code is required to exit guest mode and return to the full gallery.' :
              'Set a 4-digit code. It will be required to exit guest mode.')
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

            Button('Save new PIN')
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
            this.sectionLabel('3. GUEST MODE PROTECTION')
            this.settingToggle(true)
            this.settingToggle(false)
          }

          Column({ space: 12 }) {
            Row() {
              Row({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                  .fontSize(18)
                  .fontColor([AMBER])
                Text('OpenHarmony system limitations')
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
              Text('SafeShare cannot block system buttons. A guest can return to the home screen and open another app, ' +
                'such as the system Gallery. SafeShare will immediately lock itself with the PIN, but it cannot lock other ' +
                'apps.\n\nBefore handing over the phone, enable the system screen lock. Full confinement to one app ' +
                '(kiosk mode) requires an administrator-managed device (Enterprise Device Management).')
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

      Button('Done')
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
    .accessibilityText(isZoom ? 'Zoom photo in or out' : 'Photo information')
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
    Column({ space: 10 }) {
      Row() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.lock_fill'))
            .fontSize(14)
            .fontColor([AMBER])
          Text(this.guestTab === 'photo' ? `Guest Mode: ${this.guestIndex + 1} / ${this.guestPhotos.length}` :
            `Guest Mode: ${kindLabel(this.guestTab)}`)
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
          if (this.guestTab === 'photo') {
            this.guestIconButton(true)
            if (this.showDetails) {
              this.guestIconButton(false)
            }
          }
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.lock_fill'))
                .fontSize(16)
                .fontColor([AMBER])
              Text('Exit (PIN)')
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

      if (this.guestKinds().length > 1) {
        this.guestTabs()
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
  private guestTabs() {
    Row({ space: 8 }) {
      ForEach(this.guestKinds(), (kind: ItemKind) => {
        Text(`${kindLabel(kind)} ${kind === 'photo' ? this.guestPhotos.length :
          this.guestDocs.filter((doc: VaultItem) => doc.kind === kind).length}`)
          .height(32)
          .padding({ left: 14, right: 14 })
          .borderRadius(999)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.guestTab === kind ? '#020617' : '#E4E4E7')
          .backgroundColor(this.guestTab === kind ? AMBER : '#CC18181B')
          .border({ width: 1, color: this.guestTab === kind ? AMBER : '#3F3F46' })
          .onClick(() => this.showGuestTab(kind))
      }, (kind: ItemKind) => kind)
    }
    .width('100%')
  }

  @Builder
  private guestDocRow(doc: VaultItem) {
    Row({ space: 12 }) {
      SymbolGlyph(doc.kind === 'pdf' ? $r('sys.symbol.doc') : $r('sys.symbol.notepad'))
        .fontSize(20)
        .fontColor([doc.kind === 'pdf' ? '#F87171' : '#60A5FA'])
      Column({ space: 2 }) {
        Text(doc.name)
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(formatDateTime(doc.createdAt))
          .width('100%')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor('#94A3B8')
      }
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor(['#71717A'])
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor('#18181B')
    .border({ width: 1, color: '#27272A' })
    .onClick(() => this.openGuestDoc(doc))
  }

  @Builder
  private guestDocsScreen() {
    Column() {
      this.guestTopBar()
      if (this.guestDoc === null) {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.guestDocs.filter((doc: VaultItem) => doc.kind === this.guestTab), (doc: VaultItem) => {
              this.guestDocRow(doc)
            }, (doc: VaultItem) => doc.id)
            if (this.lockedDocs > 0) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.lock_fill'))
                  .fontSize(14)
                  .fontColor([AMBER])
                Text(`Remaining files (${this.lockedDocs}) are locked.`)
                  .fontSize(12)
                  .fontColor('#FDE68A')
              }
              .width('100%')
              .padding(12)
            }
          }
          .padding({ left: 16, right: 16, bottom: 24 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      } else {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text('List')
                .fontSize(13)
                .fontColor('#FFFFFF')
            }
          }
          .height(36)
          .padding({ left: 10, right: 14 })
          .borderRadius(10)
          .backgroundColor('#27272A')
          .onClick(() => this.guestDoc = null)
          Text(this.guestDoc.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

        if (this.guestDoc.kind === 'pdf') {
          PdfView({ path: this.guestDoc.path })
            .layoutWeight(1)
        } else {
          Scroll() {
            Text(this.guestNote)
              .width('100%')
              .fontSize(15)
              .lineHeight(23)
              .fontColor('#E4E4E7')
              .privacySensitive(true)
          }
          .layoutWeight(1)
          .padding(16)
          .align(Alignment.TopStart)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
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

        Text(`Period: ${this.guestRangeLabel}`)
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
            .accessibilityText('The remaining gallery photos are locked')
            .onClick(() => {
              hapticAlarm();
              this.showBoundary(`${this.lockedCount} remaining private photos are locked.`);
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
          Text('Photo metadata')
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
          Text(this.guestCamera.length > 0 ? this.guestCamera : 'No camera data')
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

      Text('Gallery locked')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
      Text('The guest session was interrupted. The remaining photos are hidden until the owner PIN is entered.')
        .fontSize(14)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .fontColor('#94A3B8')
      Button('Unlock gallery (PIN)')
        .height(40)
        .padding({ left: 24, right: 24 })
        .margin({ top: 12 })
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#020617')
        .backgroundColor(AMBER)
        .onClick(() => this.openPin(PinMode.RESUME,
          'The guest session was interrupted. Enter the owner PIN to return to the gallery.'))
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#020617')
  }

  @Builder
  private guestScreen() {
    if (this.guestPhotos.length === 0 && this.guestDocs.length === 0) {
      this.guestLocked()
    } else if (this.guestTab !== 'photo') {
      this.guestDocsScreen()
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
              .accessibilityText('Delete digit')
              .onClick(() => this.deleteDigit())
            }
          }

          Text('Forgot your PIN?')
            .fontSize(11)
            .fontColor(this.pal().textMuted)
            .margin({ top: 16 })
            .onClick(() => this.pinHintOpen = !this.pinHintOpen)
          if (this.pinHintOpen) {
            Text('The PIN cannot be recovered. To reset it, clear SafeShare app data in System Settings.')
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
            Text(`Failed attempts: ${this.pinAttempts}`)
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
          .accessibilityText('Cancel')
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
      if (!this.guestMode && this.docPreview !== null) {
        this.docPreviewOverlay(this.docPreview)
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
