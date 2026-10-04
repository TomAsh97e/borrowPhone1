import { preferences } from '@kit.ArkData';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { constantTimeEqual, isValidPin } from '../model/SessionRules';

const STORE_NAME = 'safeshare';
const PIN_ITERATIONS = 100000;
const PIN_MAX_FAILURES = 5;
const PIN_LOCKOUT_MS = 30 * 1000;

const PIN_HASH_KEY = 'pinHash';
const PIN_SALT_KEY = 'pinSalt';
const PIN_FAILURES_KEY = 'pinFailures';
const PIN_LOCK_UNTIL_KEY = 'pinLockUntil';
const GUEST_ACTIVE_KEY = 'guestActive';
const DARK_THEME_KEY = 'darkTheme';
const PREVENT_LEAVE_KEY = 'preventLeave';
const SHOW_DETAILS_KEY = 'showDetails';

export enum PinCheck {
  OK,
  WRONG,
  LOCKED
}

export class AppSettings {
  darkTheme: boolean = true;
  preventLeave: boolean = true;
  showDetailsInGuestMode: boolean = false;
}

// Local "backend": owner PIN (PBKDF2 hash + lockout), settings and the guest-session flag.
export class AppStore {
  settings: AppSettings = new AppSettings();
  guestActive: boolean = false;
  private store: preferences.Preferences | undefined = undefined;
  private pinHash: Uint8Array = new Uint8Array();
  private pinSalt: Uint8Array = new Uint8Array();
  private failures: number = 0;
  private lockUntil: number = 0;

  async load(context: Context): Promise<void> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const hash = await store.get(PIN_HASH_KEY, new Uint8Array());
    const salt = await store.get(PIN_SALT_KEY, new Uint8Array());
    const failures = await store.get(PIN_FAILURES_KEY, 0);
    const lockUntil = await store.get(PIN_LOCK_UNTIL_KEY, 0);
    const guestActive = await store.get(GUEST_ACTIVE_KEY, false);
    const darkTheme = await store.get(DARK_THEME_KEY, true);
    const preventLeave = await store.get(PREVENT_LEAVE_KEY, true);
    const showDetails = await store.get(SHOW_DETAILS_KEY, false);
    if (!(hash instanceof Uint8Array) || !(salt instanceof Uint8Array) || typeof failures !== 'number' ||
      typeof lockUntil !== 'number' || typeof guestActive !== 'boolean' || typeof darkTheme !== 'boolean' ||
      typeof preventLeave !== 'boolean' || typeof showDetails !== 'boolean') {
      throw new Error('Invalid SafeShare storage');
    }
    this.store = store;
    this.pinHash = hash;
    this.pinSalt = salt;
    this.failures = failures;
    this.lockUntil = lockUntil;
    this.guestActive = guestActive;
    this.settings.darkTheme = darkTheme;
    this.settings.preventLeave = preventLeave;
    this.settings.showDetailsInGuestMode = showDetails;
  }

  isReady(): boolean {
    return this.store !== undefined;
  }

  hasPin(): boolean {
    return this.pinHash.length > 0 && this.pinSalt.length > 0;
  }

  lockSecondsLeft(): number {
    return Math.max(0, Math.ceil((this.lockUntil - Date.now()) / 1000));
  }

  attemptsLeft(): number {
    return PIN_MAX_FAILURES - this.failures;
  }

  async checkPin(pin: string): Promise<PinCheck> {
    if (this.lockSecondsLeft() > 0) {
      return PinCheck.LOCKED;
    }
    if (!isValidPin(pin) || !this.hasPin()) {
      return PinCheck.WRONG;
    }
    if (constantTimeEqual(this.derive(pin, this.pinSalt), this.pinHash)) {
      this.failures = 0;
      this.lockUntil = 0;
      await this.saveAttempts();
      return PinCheck.OK;
    }
    this.failures++;
    if (this.failures >= PIN_MAX_FAILURES) {
      this.failures = 0;
      this.lockUntil = Date.now() + PIN_LOCKOUT_MS;
    }
    await this.saveAttempts();
    return this.lockUntil > Date.now() ? PinCheck.LOCKED : PinCheck.WRONG;
  }

  async setPin(pin: string): Promise<void> {
    if (!isValidPin(pin)) {
      throw new Error('Invalid PIN');
    }
    const store = this.requireStore();
    const salt = cryptoFramework.createRandom().generateRandomSync(16).data;
    const hash = this.derive(pin, salt);
    await store.put(PIN_SALT_KEY, salt);
    await store.put(PIN_HASH_KEY, hash);
    await store.put(PIN_FAILURES_KEY, 0);
    await store.put(PIN_LOCK_UNTIL_KEY, 0);
    await store.flush();
    this.pinSalt = salt;
    this.pinHash = hash;
    this.failures = 0;
    this.lockUntil = 0;
  }

  async setGuestActive(active: boolean): Promise<void> {
    const store = this.requireStore();
    await store.put(GUEST_ACTIVE_KEY, active);
    await store.flush();
    this.guestActive = active;
  }

  async saveSettings(): Promise<void> {
    const store = this.requireStore();
    await store.put(DARK_THEME_KEY, this.settings.darkTheme);
    await store.put(PREVENT_LEAVE_KEY, this.settings.preventLeave);
    await store.put(SHOW_DETAILS_KEY, this.settings.showDetailsInGuestMode);
    await store.flush();
  }

  private derive(pin: string, salt: Uint8Array): Uint8Array {
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: pin,
      salt: salt,
      iterations: PIN_ITERATIONS,
      keySize: 32
    };
    return cryptoFramework.createKdf('PBKDF2|SHA256').generateSecretSync(spec).data;
  }

  private async saveAttempts(): Promise<void> {
    const store = this.requireStore();
    await store.put(PIN_FAILURES_KEY, this.failures);
    await store.put(PIN_LOCK_UNTIL_KEY, this.lockUntil);
    await store.flush();
  }

  private requireStore(): preferences.Preferences {
    if (this.store === undefined) {
      throw new Error('SafeShare storage unavailable');
    }
    return this.store;
  }
}
