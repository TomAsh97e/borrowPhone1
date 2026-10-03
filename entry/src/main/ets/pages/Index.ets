import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { clampIndex, constantTimeEqual, fitSize, hasValidSelection, isValidPin } from '../model/SessionRules';

const MAX_PHOTOS = 5;
const MAX_FILE_BYTES = 25 * 1024 * 1024;
const MAX_PIXELS = 50 * 1000 * 1000;
const MAX_DISPLAY_EDGE = 1600;
const OWNER_AUTHORIZATION_MS = 2 * 60 * 1000;
const PIN_ITERATIONS = 100000;
const PIN_MAX_FAILURES = 5;
const PIN_LOCKOUT_MS = 30 * 1000;
const PIN_PREFERENCES = 'owner_pin';
const PIN_HASH_KEY = 'hash';
const PIN_SALT_KEY = 'salt';
const PIN_FAILURES_KEY = 'failures';
const PIN_LOCK_UNTIL_KEY = 'lockUntil';

enum Screen {
  LOCKED,
  PIN_SETUP,
  PIN_VERIFY,
  OWNER,
  REVIEW,
  GUEST
}

enum AuthPurpose {
  ENTER_OWNER,
  EXIT_GUEST
}

@Entry
@Component
struct Index {
  @StorageLink('privacyReady') private privacyReady: boolean = false;
  @StorageLink('interruptionEpoch') @Watch('onInterrupted') private interruptionEpoch: number = 0;
  @State private screen: Screen = Screen.LOCKED;
  @State private busy: boolean = false;
  @State private message: string = '';
  @State private pendingCount: number = 0;
  @State private imageCount: number = 0;
  @State private imageIndex: number = 0;
  @State private ownerAuthenticated: boolean = false;
  @State private pinLoaded: boolean = false;
  @State private pinStorageReady: boolean = false;
  @State private pinConfigured: boolean = false;
  @State private pinInput: string = '';
  @State private pinConfirmation: string = '';

  private pendingUris: string[] = [];
  private images: image.PixelMap[] = [];
  private operationId: number = 0;
  private ownerAuthorizationTimer: number = -1;
  private pinPurpose: AuthPurpose = AuthPurpose.ENTER_OWNER;
  private pinHash: Uint8Array = new Uint8Array();
  private pinSalt: Uint8Array = new Uint8Array();
  private pinFailures: number = 0;
  private pinLockUntil: number = 0;
  private pinPreferences: preferences.Preferences | undefined = undefined;

  aboutToAppear(): void {
    this.loadPin();
  }

  aboutToDisappear(): void {
    this.operationId++;
    this.clearOwnerAuthorizationTimer();
    this.clearPinInput();
    this.releaseImages();
  }

  private onInterrupted(): void {
    this.lockAndClear('Session ended because BorrowPhone left the foreground.');
  }

  private async loadPin(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        throw new Error('Application context unavailable');
      }
      const store = await preferences.getPreferences(context, PIN_PREFERENCES);
      const hash = await store.get(PIN_HASH_KEY, new Uint8Array());
      const salt = await store.get(PIN_SALT_KEY, new Uint8Array());
      const failures = await store.get(PIN_FAILURES_KEY, 0);
      const lockUntil = await store.get(PIN_LOCK_UNTIL_KEY, 0);
      if (!(hash instanceof Uint8Array) || !(salt instanceof Uint8Array) ||
        typeof failures !== 'number' || typeof lockUntil !== 'number') {
        throw new Error('Invalid PIN storage');
      }
      this.pinPreferences = store;
      this.pinHash = hash;
      this.pinSalt = salt;
      this.pinFailures = failures;
      this.pinLockUntil = lockUntil;
      this.pinConfigured = hash.length > 0 && salt.length > 0;
      this.pinStorageReady = true;
    } catch (error) {
      this.message = 'PIN storage is unavailable. Owner controls remain locked.';
    } finally {
      this.pinLoaded = true;
    }
  }

  private derivePin(pin: string, salt: Uint8Array): Uint8Array {
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: pin,
      salt: salt,
      iterations: PIN_ITERATIONS,
      keySize: 32
    };
    return cryptoFramework.createKdf('PBKDF2|SHA256').generateSecretSync(spec).data;
  }

  private authenticate(purpose: AuthPurpose): void {
    if (!this.privacyReady || this.busy || !this.pinLoaded || !this.pinStorageReady) {
      return;
    }
    if (Date.now() < this.pinLockUntil) {
      const seconds = Math.ceil((this.pinLockUntil - Date.now()) / 1000);
      this.message = `Too many incorrect attempts. Try again in ${seconds} seconds.`;
      return;
    }
    this.pinPurpose = purpose;
    this.clearPinInput();
    this.message = '';
    this.screen = this.pinConfigured ? Screen.PIN_VERIFY : Screen.PIN_SETUP;
  }

  private async createPin(): Promise<void> {
    if (this.busy || !isValidPin(this.pinInput) || this.pinInput !== this.pinConfirmation ||
      this.pinPreferences === undefined) {
      this.message = 'Enter the same six-digit PIN twice.';
      return;
    }
    this.busy = true;
    try {
      const salt = cryptoFramework.createRandom().generateRandomSync(16).data;
      const hash = this.derivePin(this.pinInput, salt);
      await this.pinPreferences.put(PIN_SALT_KEY, salt);
      await this.pinPreferences.put(PIN_HASH_KEY, hash);
      await this.pinPreferences.put(PIN_FAILURES_KEY, 0);
      await this.pinPreferences.put(PIN_LOCK_UNTIL_KEY, 0);
      await this.pinPreferences.flush();
      this.pinSalt = salt;
      this.pinHash = hash;
      this.pinFailures = 0;
      this.pinLockUntil = 0;
      this.pinConfigured = true;
      this.clearPinInput();
      this.completeAuthentication(AuthPurpose.ENTER_OWNER);
    } catch (error) {
      this.message = 'The PIN could not be saved. Owner controls remain locked.';
    } finally {
      this.busy = false;
    }
  }

  private async verifyPin(): Promise<void> {
    if (this.busy || !isValidPin(this.pinInput) || this.pinPreferences === undefined) {
      this.message = 'Enter the six-digit PIN.';
      return;
    }
    if (Date.now() < this.pinLockUntil) {
      this.authenticate(this.pinPurpose);
      return;
    }

    this.busy = true;
    try {
      const matches = constantTimeEqual(this.derivePin(this.pinInput, this.pinSalt), this.pinHash);
      this.pinInput = '';
      if (!matches) {
        this.pinFailures++;
        if (this.pinFailures >= PIN_MAX_FAILURES) {
          this.pinFailures = 0;
          this.pinLockUntil = Date.now() + PIN_LOCKOUT_MS;
          this.message = 'Too many incorrect attempts. PIN entry is locked for 30 seconds.';
        } else {
          this.message = `Incorrect PIN. ${PIN_MAX_FAILURES - this.pinFailures} attempts remaining.`;
        }
        await this.savePinAttemptState();
        return;
      }
      this.pinFailures = 0;
      this.pinLockUntil = 0;
      await this.savePinAttemptState();
      this.completeAuthentication(this.pinPurpose);
    } catch (error) {
      this.lockAndClear('PIN verification failed. Owner controls remain locked.');
    } finally {
      this.busy = false;
    }
  }

  private async savePinAttemptState(): Promise<void> {
    if (this.pinPreferences === undefined) {
      throw new Error('PIN storage unavailable');
    }
    await this.pinPreferences.put(PIN_FAILURES_KEY, this.pinFailures);
    await this.pinPreferences.put(PIN_LOCK_UNTIL_KEY, this.pinLockUntil);
    await this.pinPreferences.flush();
  }

  private completeAuthentication(purpose: AuthPurpose): void {
    this.ownerAuthenticated = true;
    this.armOwnerAuthorizationTimer();
    if (purpose === AuthPurpose.EXIT_GUEST) {
      this.releaseImages();
      this.message = 'Session ended. Select new photos to continue.';
    } else {
      this.message = 'Owner authenticated. Viewer-only mode is available on this device.';
    }
    this.screen = Screen.OWNER;
  }

  private cancelPinEntry(): void {
    const returnToGuest = this.pinPurpose === AuthPurpose.EXIT_GUEST && this.imageCount > 0;
    this.clearPinInput();
    this.message = returnToGuest ? 'Owner return cancelled. Guest access remains restricted.' : 'Access remains locked.';
    this.screen = returnToGuest ? Screen.GUEST : Screen.LOCKED;
  }

  private clearPinInput(): void {
    this.pinInput = '';
    this.pinConfirmation = '';
  }

  private async choosePhotos(): Promise<void> {
    if (this.busy || this.screen !== Screen.OWNER) {
      return;
    }

    const attempt = ++this.operationId;
    this.busy = true;
    this.message = '';
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = MAX_PHOTOS;
      options.isPhotoTakingSupported = false;
      const result = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (attempt !== this.operationId) {
        return;
      }
      if (!hasValidSelection(result.photoUris, MAX_PHOTOS)) {
        this.pendingUris = [];
        this.pendingCount = 0;
        this.message = result.photoUris.length === 0 ? 'No photos selected.' : 'Choose one to five different photos.';
        return;
      }
      this.pendingUris = result.photoUris.slice();
      this.pendingCount = this.pendingUris.length;
      this.message = `${this.pendingCount} photo${this.pendingCount === 1 ? '' : 's'} selected. Prepare them before starting the viewer.`;
    } catch (error) {
      if (attempt === this.operationId) {
        this.message = 'Photo selection was cancelled or is unavailable.';
      }
    } finally {
      if (attempt === this.operationId) {
        this.busy = false;
      }
    }
  }

  private async prepareSelection(): Promise<void> {
    if (this.busy || !hasValidSelection(this.pendingUris, MAX_PHOTOS)) {
      return;
    }

    const attempt = ++this.operationId;
    const uris = this.pendingUris.slice();
    const decoded: image.PixelMap[] = [];
    this.busy = true;
    this.message = 'Preparing photos in memory…';

    try {
      for (let index = 0; index < uris.length; index++) {
        const pixelMap = await this.importPhoto(uris[index]);
        if (attempt !== this.operationId) {
          await pixelMap.release();
          throw new Error('Import interrupted');
        }
        decoded.push(pixelMap);
      }
      if (attempt !== this.operationId) {
        throw new Error('Import interrupted');
      }
      this.releaseImages();
      this.images = decoded;
      this.imageCount = decoded.length;
      this.imageIndex = 0;
      this.pendingUris = [];
      this.pendingCount = 0;
      this.screen = Screen.REVIEW;
      this.message = 'Review the exact selection before opening the viewer.';
    } catch (error) {
      for (let index = 0; index < decoded.length; index++) {
        await decoded[index].release().catch(() => {});
      }
      if (attempt === this.operationId) {
        this.message = 'Could not prepare every photo. Use JPEG/PNG files up to 25 MiB and 50 MP.';
      }
    } finally {
      if (attempt === this.operationId) {
        this.busy = false;
      }
    }
  }

  private async importPhoto(uri: string): Promise<image.PixelMap> {
    let selectedFile: fileIo.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    try {
      selectedFile = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(selectedFile.fd);
      if (stat.size < 1 || stat.size > MAX_FILE_BYTES) {
        throw new Error('Unsupported file size');
      }

      source = image.createImageSource(selectedFile.fd);
      const info = await source.getImageInfo();
      if ((info.mimeType !== 'image/jpeg' && info.mimeType !== 'image/png') ||
        info.size.width < 1 || info.size.height < 1 || info.size.width * info.size.height > MAX_PIXELS) {
        throw new Error('Unsupported image');
      }
      const target = fitSize(info.size.width, info.size.height, MAX_DISPLAY_EDGE);
      return await source.createPixelMap({
        desiredSize: target,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: false
      });
    } catch (error) {
      throw new Error('Photo import failed');
    } finally {
      if (source !== undefined) {
        try {
          await source.release();
        } catch (error) {
        }
      }
      if (selectedFile !== undefined) {
        try {
          await fileIo.close(selectedFile);
        } catch (error) {
        }
      }
    }
  }

  private removeCurrentPhoto(): void {
    if (this.screen !== Screen.REVIEW || this.imageCount === 0) {
      return;
    }
    const removed = this.images[this.imageIndex];
    this.images = this.images.filter((item: image.PixelMap, index: number) => index !== this.imageIndex);
    removed.release().catch(() => {});
    this.imageCount = this.images.length;
    this.imageIndex = clampIndex(this.imageIndex, this.imageCount);
    if (this.imageCount === 0) {
      this.screen = Screen.OWNER;
      this.message = 'Selection is empty. Choose photos again.';
    }
  }

  private startGuestViewer(): void {
    if (this.screen !== Screen.REVIEW || this.imageCount === 0 || !this.ownerAuthenticated) {
      return;
    }
    this.ownerAuthenticated = false;
    this.clearOwnerAuthorizationTimer();
    this.imageIndex = 0;
    this.screen = Screen.GUEST;
    this.message = '';
  }

  private endGuestSession(): void {
    this.authenticate(AuthPurpose.EXIT_GUEST);
  }

  private lockAndClear(reason: string): void {
    this.operationId++;
    this.clearOwnerAuthorizationTimer();
    this.clearPinInput();
    this.releaseImages();
    this.pendingUris = [];
    this.pendingCount = 0;
    this.ownerAuthenticated = false;
    this.busy = false;
    this.screen = Screen.LOCKED;
    this.message = reason;
  }

  private armOwnerAuthorizationTimer(): void {
    this.clearOwnerAuthorizationTimer();
    // ponytail: absolute two-minute window; track interaction inactivity only if setup needs longer.
    this.ownerAuthorizationTimer = setTimeout(() => {
      if (this.ownerAuthenticated) {
        this.lockAndClear('Owner authorization expired.');
      }
    }, OWNER_AUTHORIZATION_MS);
  }

  private clearOwnerAuthorizationTimer(): void {
    if (this.ownerAuthorizationTimer >= 0) {
      clearTimeout(this.ownerAuthorizationTimer);
      this.ownerAuthorizationTimer = -1;
    }
  }

  private releaseImages(): void {
    const oldImages = this.images;
    this.images = [];
    this.imageCount = 0;
    this.imageIndex = 0;
    for (let index = 0; index < oldImages.length; index++) {
      oldImages[index].release().catch(() => {});
    }
  }

  private moveImage(offset: number): void {
    this.imageIndex = clampIndex(this.imageIndex + offset, this.imageCount);
  }

  private isLocked(): boolean {
    return this.screen === Screen.LOCKED;
  }

  private isPinSetup(): boolean {
    return this.screen === Screen.PIN_SETUP;
  }

  private isPinVerify(): boolean {
    return this.screen === Screen.PIN_VERIFY;
  }

  private isOwner(): boolean {
    return this.screen === Screen.OWNER;
  }

  private isReview(): boolean {
    return this.screen === Screen.REVIEW;
  }

  private hasProtectedLock(): boolean {
    return this.isLocked() || this.isPinVerify() || this.screen === Screen.GUEST;
  }

  private lockStatusText(): string {
    if (this.isLocked()) {
      return 'APP LOCKED';
    }
    if (this.isPinSetup()) {
      return 'CREATE OWNER PIN';
    }
    if (this.isPinVerify()) {
      return 'OWNER ACCESS LOCKED · PIN REQUIRED';
    }
    if (this.screen === Screen.GUEST) {
      return `GUEST VIEWER ACTIVE · ${this.imageCount} PHOTO${this.imageCount === 1 ? '' : 'S'} · PIN REQUIRED`;
    }
    return 'OWNER AUTHENTICATED · UP TO 2 MIN';
  }

  @Builder
  private lockStatus() {
    Row({ space: 10 }) {
      Text(this.hasProtectedLock() ? '🔒' : '🔓')
        .fontSize(24)
      Text(this.lockStatusText())
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.hasProtectedLock() ? '#185C37' : '#8A3B12')
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.hasProtectedLock() ? '#E1F5E8' : '#FFF0E8')
    .accessibilityText(this.lockStatusText())
  }

  @Builder
  private warningBanner() {
    Text('VIEWER ONLY · Other apps remain accessible')
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor('#7A3E00')
      .backgroundColor('#FFF1D6')
      .borderRadius(12)
      .padding(12)
      .width('100%')
      .textAlign(TextAlign.Center)
  }

  @Builder
  private statusText() {
    if (this.message.length > 0) {
      Text(this.message)
        .fontSize(16)
        .fontColor('#48505E')
        .lineHeight(23)
        .width('100%')
        .textAlign(TextAlign.Center)
        .accessibilityText(this.message)
    }
  }

  @Builder
  private lockedScreen() {
    Scroll() {
      Column({ space: 22 }) {
        this.lockStatus()
        Text('BorrowPhone')
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172033')
        Text('Share selected photos — and nothing else inside this viewer.')
          .fontSize(19)
          .fontColor('#48505E')
          .lineHeight(27)
          .textAlign(TextAlign.Center)
        this.warningBanner()
        if (!this.privacyReady) {
          Text('Privacy-window protection could not be enabled. Photo viewing is blocked.')
            .fontSize(17)
            .fontColor('#A10F2B')
            .textAlign(TextAlign.Center)
        } else if (!this.pinLoaded) {
          LoadingProgress()
            .width(44)
            .height(44)
        } else {
          Button(this.pinConfigured ? 'Enter owner PIN' : 'Create owner PIN')
            .width('100%')
            .height(54)
            .fontSize(17)
            .onClick(() => this.authenticate(AuthPurpose.ENTER_OWNER))
            .enabled(!this.busy && this.pinStorageReady)
            .accessibilityText(this.pinConfigured ? 'Enter owner PIN' : 'Create owner PIN')
        }
        this.statusText()
      }
      .width('100%')
      .padding(24)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private pinScreen() {
    Scroll() {
      Column({ space: 18 }) {
        this.lockStatus()
        Text(this.isPinSetup() ? 'Create owner PIN' : 'Enter owner PIN')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172033')
        Text(this.isPinSetup() ?
          'Choose a six-digit PIN. If forgotten, clear the application data to reset it.' :
          'Enter the six-digit PIN to access owner controls.')
          .fontSize(17)
          .lineHeight(24)
          .fontColor('#48505E')
          .textAlign(TextAlign.Center)
        TextInput({ text: this.pinInput, placeholder: '6-digit PIN' })
          .type(InputType.NUMBER_PASSWORD)
          .maxLength(6)
          .showPasswordIcon(false)
          .height(54)
          .onChange((value: string) => this.pinInput = value)
        if (this.isPinSetup()) {
          TextInput({ text: this.pinConfirmation, placeholder: 'Repeat PIN' })
            .type(InputType.NUMBER_PASSWORD)
            .maxLength(6)
            .showPasswordIcon(false)
            .height(54)
            .onChange((value: string) => this.pinConfirmation = value)
          Button('Save PIN')
            .width('100%')
            .height(54)
            .enabled(!this.busy)
            .onClick(() => this.createPin())
        } else {
          Button('Unlock owner controls')
            .width('100%')
            .height(54)
            .enabled(!this.busy)
            .onClick(() => this.verifyPin())
        }
        Button('Cancel')
          .type(ButtonType.Normal)
          .width('100%')
          .height(50)
          .enabled(!this.busy)
          .onClick(() => this.cancelPinEntry())
        if (this.busy) {
          LoadingProgress()
            .width(36)
            .height(36)
        }
        this.statusText()
      }
      .width('100%')
      .padding(24)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ownerScreen() {
    Scroll() {
      Column({ space: 18 }) {
        this.lockStatus()
        Text('Owner setup')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172033')
        this.warningBanner()
        Text('Choose 1–5 JPEG or PNG photos with the system picker. BorrowPhone requests no broad gallery permission.')
          .fontSize(17)
          .lineHeight(24)
          .fontColor('#48505E')
          .textAlign(TextAlign.Center)
        Button('Choose photos')
          .width('100%')
          .height(54)
          .fontSize(18)
          .onClick(() => this.choosePhotos())
          .enabled(!this.busy)
          .accessibilityText('Choose one to five photos')
        if (this.pendingCount > 0) {
          Text(`${this.pendingCount} selected`)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
          Button('Prepare selection')
            .width('100%')
            .height(54)
            .fontSize(18)
            .onClick(() => this.prepareSelection())
            .enabled(!this.busy)
            .accessibilityText(`Prepare ${this.pendingCount} selected photos`)
        }
        if (this.busy) {
          LoadingProgress()
            .width(44)
            .height(44)
            .color('#3167E3')
        }
        this.statusText()
        Button('Lock')
          .type(ButtonType.Normal)
          .width('100%')
          .height(50)
          .onClick(() => this.lockAndClear('Locked.'))
          .enabled(!this.busy)
      }
      .width('100%')
      .padding(24)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private photo() {
    if (this.imageCount > 0) {
      Image(this.images[this.imageIndex])
        .objectFit(ImageFit.Contain)
        .orientation(ImageRotateOrientation.AUTO)
        .privacySensitive(true)
        .draggable(false)
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#0A0D14')
        .accessibilityText(`Selected photo ${this.imageIndex + 1} of ${this.imageCount}`)
    }
  }

  @Builder
  private navigationControls() {
    Row({ space: 12 }) {
      Button('Previous')
        .layoutWeight(1)
        .height(50)
        .enabled(this.imageIndex > 0 && !this.busy)
        .onClick(() => this.moveImage(-1))
        .accessibilityText('Previous selected photo')
      Text(`${this.imageIndex + 1} / ${this.imageCount}`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#172033')
        .textAlign(TextAlign.Center)
        .width(70)
      Button('Next')
        .layoutWeight(1)
        .height(50)
        .enabled(this.imageIndex < this.imageCount - 1 && !this.busy)
        .onClick(() => this.moveImage(1))
        .accessibilityText('Next selected photo')
    }
    .width('100%')
  }

  @Builder
  private reviewScreen() {
    Column({ space: 14 }) {
      this.lockStatus()
      Text('Review selection')
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
        .fontColor('#172033')
      this.warningBanner()
      this.photo()
      this.navigationControls()
      Row({ space: 12 }) {
        Button('Remove')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(50)
          .onClick(() => this.removeCurrentPhoto())
          .accessibilityText('Remove current photo')
        Button('Start viewer')
          .layoutWeight(1)
          .height(50)
          .onClick(() => this.startGuestViewer())
          .accessibilityText(`Start viewer-only preview with ${this.imageCount} photos`)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }

  @Builder
  private guestScreen() {
    Column({ space: 12 }) {
      this.lockStatus()
      this.warningBanner()
      this.photo()
      this.navigationControls()
      Button('Return to owner')
        .type(ButtonType.Normal)
        .width('100%')
        .height(52)
        .fontSize(17)
        .enabled(!this.busy)
        .onClick(() => this.endGuestSession())
        .accessibilityText('Enter PIN to return to owner controls')
      if (this.busy) {
        LoadingProgress()
          .width(36)
          .height(36)
      }
      this.statusText()
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#F7F8FB')
  }

  build() {
    Stack() {
      if (this.isLocked()) {
        this.lockedScreen()
      } else if (this.isPinSetup() || this.isPinVerify()) {
        this.pinScreen()
      } else if (this.isOwner()) {
        this.ownerScreen()
      } else if (this.isReview()) {
        this.reviewScreen()
      } else {
        this.guestScreen()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8FB')
  }
}
