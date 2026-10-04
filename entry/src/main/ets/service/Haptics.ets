import { vibrator } from '@kit.SensorServiceKit';

// Short vibrations replacing the web design's synthesized tap/lock/unlock/alarm sounds.
function vibrate(duration: number): void {
  const effect: vibrator.VibrateTime = { type: 'time', duration: duration };
  const attribute: vibrator.VibrateAttribute = { id: 0, usage: 'touch' };
  try {
    vibrator.startVibration(effect, attribute).catch(() => {});
  } catch (error) {
  }
}

export function hapticTap(): void {
  vibrate(15);
}

export function hapticLock(): void {
  vibrate(60);
}

export function hapticUnlock(): void {
  vibrate(40);
}

export function hapticAlarm(): void {
  vibrate(200);
}
