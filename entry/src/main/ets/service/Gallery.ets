import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { normalizeTimestamp } from '../model/SessionRules';

const READ_PERMISSION: Permissions = 'ohos.permission.READ_IMAGEVIDEO';
const MAX_PHOTOS = 500;

export class GalleryPhoto {
  uri: string;
  title: string;
  takenAt: number;
  width: number;
  height: number;

  constructor(uri: string, title: string, takenAt: number, width: number, height: number) {
    this.uri = uri;
    this.title = title;
    this.takenAt = takenAt;
    this.width = width;
    this.height = height;
  }
}

// First call shows the system prompt; once denied, the settings dialog is the only way back.
export async function requestGalleryAccess(context: common.UIAbilityContext, afterDenial: boolean): Promise<boolean> {
  const manager = abilityAccessCtrl.createAtManager();
  if (afterDenial) {
    const states = await manager.requestPermissionOnSetting(context, [READ_PERMISSION]);
    return states.length > 0 && states[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }
  const result = await manager.requestPermissionsFromUser(context, [READ_PERMISSION]);
  return result.authResults.length > 0 && result.authResults[0] === 0;
}

function numberOf(asset: photoAccessHelper.PhotoAsset, key: string): number {
  const value = asset.get(key);
  return typeof value === 'number' ? value : 0;
}

export async function loadPhotos(context: Context): Promise<GalleryPhoto[]> {
  const helper = photoAccessHelper.getPhotoAccessHelper(context);
  try {
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.PHOTO_TYPE, photoAccessHelper.PhotoType.IMAGE);
    predicates.orderByDesc(photoAccessHelper.PhotoKeys.DATE_TAKEN);
    predicates.limit(MAX_PHOTOS, 0);
    const options: photoAccessHelper.FetchOptions = {
      fetchColumns: [
        photoAccessHelper.PhotoKeys.DATE_TAKEN,
        photoAccessHelper.PhotoKeys.WIDTH,
        photoAccessHelper.PhotoKeys.HEIGHT,
        photoAccessHelper.PhotoKeys.TITLE
      ],
      predicates: predicates
    };
    const result = await helper.getAssets(options);
    try {
      const assets = await result.getAllObjects();
      return assets.map((asset: photoAccessHelper.PhotoAsset) => {
        const title = asset.get(photoAccessHelper.PhotoKeys.TITLE);
        return new GalleryPhoto(
          asset.uri,
          typeof title === 'string' && title.length > 0 ? title : asset.displayName,
          normalizeTimestamp(numberOf(asset, photoAccessHelper.PhotoKeys.DATE_TAKEN)),
          numberOf(asset, photoAccessHelper.PhotoKeys.WIDTH),
          numberOf(asset, photoAccessHelper.PhotoKeys.HEIGHT)
        );
      });
    } finally {
      result.close();
    }
  } finally {
    helper.release();
  }
}

async function readProperty(source: image.ImageSource, key: image.PropertyKey): Promise<string> {
  try {
    return (await source.getImageProperty(key)).trim();
  } catch (error) {
    return '';
  }
}

// "Make Model" from EXIF, or an empty string when the photo carries no camera data.
export async function readCameraModel(uri: string): Promise<string> {
  let file: fileIo.File | undefined = undefined;
  let source: image.ImageSource | undefined = undefined;
  try {
    file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    source = image.createImageSource(file.fd);
    const make = await readProperty(source, image.PropertyKey.MAKE);
    const model = await readProperty(source, image.PropertyKey.MODEL);
    return model.startsWith(make) ? model : `${make} ${model}`.trim();
  } catch (error) {
    return '';
  } finally {
    if (source !== undefined) {
      source.release().catch(() => {});
    }
    if (file !== undefined) {
      fileIo.close(file).catch(() => {});
    }
  }
}
