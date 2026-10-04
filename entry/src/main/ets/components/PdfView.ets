import { webview } from '@kit.ArkWeb';

const ENGINE_TIMEOUT_MS = 6000;

// Shows one vault PDF with ArkWeb's built-in PDF viewer. The page may load only that file: links
// inside a PDF must not open other sandbox files (unshared PDFs) or anything else.
@Component
export struct PdfView {
  path: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private timer: number = -1;
  @State private message: string = '';

  aboutToAppear(): void {
    // Without a usable ArkWeb engine (e.g. the x86_64 emulator ships it for arm64 only) no load
    // event ever arrives; say so instead of showing an empty page.
    this.timer = setTimeout(() => {
      this.message = 'PDF preview is unavailable on this device (ArkWeb engine missing).';
    }, ENGINE_TIMEOUT_MS);
  }

  aboutToDisappear(): void {
    clearTimeout(this.timer);
  }

  private isOwnFile(url: string): boolean {
    const own = `file://${this.path}`;
    return url === own || url.startsWith(`${own}#`);
  }

  build() {
    Stack() {
      Web({ src: `file://${this.path}`, controller: this.controller })
        .width('100%')
        .height('100%')
        .fileAccess(true)
        .javaScriptAccess(false)
        .domStorageAccess(false)
        .geolocationAccess(false)
        .onlineImageAccess(false)
        .onLoadIntercept((event: OnLoadInterceptEvent) => !this.isOwnFile(event.data.getRequestUrl()))
        .onPdfLoadEvent((event: OnPdfLoadEvent) => {
          clearTimeout(this.timer);
          this.message = event.result === PdfLoadResult.LOAD_SUCCESS ? '' : 'Could not open this PDF file.';
        })
        .onPageEnd(() => clearTimeout(this.timer))
      if (this.message.length > 0) {
        Text(this.message)
          .width('100%')
          .height('100%')
          .padding(24)
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .fontColor('#FCA5A5')
          .backgroundColor('#18181B')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#18181B')
  }
}
