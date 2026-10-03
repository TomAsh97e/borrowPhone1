import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'BorrowPhone';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate<boolean>('privacyReady', false);
    AppStorage.setOrCreate<number>('interruptionEpoch', 0);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Could not follow the system color mode.');
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.loadProtectedWindow(windowStage);
  }

  private async loadProtectedWindow(windowStage: window.WindowStage): Promise<void> {
    try {
      const mainWindow = await windowStage.getMainWindow();
      await mainWindow.setWindowPrivacyMode(true);
      AppStorage.setOrCreate<boolean>('privacyReady', true);
    } catch (error) {
      AppStorage.setOrCreate<boolean>('privacyReady', false);
      hilog.error(DOMAIN, TAG, 'Privacy window could not be enabled.');
    }

    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the main page.');
      }
    });
  }

  onWindowStageDestroy(): void {
    this.interruptSession();
  }

  onBackground(): void {
    this.interruptSession();
  }

  private interruptSession(): void {
    const epoch = AppStorage.get<number>('interruptionEpoch') ?? 0;
    AppStorage.setOrCreate<number>('interruptionEpoch', epoch + 1);
  }
}
